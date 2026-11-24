import AVFoundation
import Foundation
import Observation
import os
import PulseCore
import Speech

/// Talking with ROOK like with a person: tap once, then hands-free. Apple speech recognition (de-DE, on the
/// device when the iPhone supports it) with a live transcript; an utterance ends after ~1.2 s of silence and goes
/// to ROOK (`utterances`); the answer is spoken through the `AudioCoordinator` (`speak`), then ROOK listens again.
/// Speaking into an answer interrupts it. The microphone is on only while the conversation runs; it ends on
/// "Gespräch beenden", after ~30 s of silence, on a call, or when the app leaves the foreground.
/// Echo of ROOK's own voice is reduced by the voice-chat audio mode (play and record, echo cancellation).
@MainActor
@Observable
final class VoiceConversation {
    static let shared = VoiceConversation()

    enum Problem: Equatable {
        case microphoneDenied, speechDenied, recognizerUnavailable, audio(String)

        var text: String {
            switch self {
            case .microphoneDenied: "Ich darf das Mikrofon nicht nutzen. Du kannst es in den Einstellungen bei PULSE ONE erlauben."
            case .speechDenied: "Die Spracherkennung ist nicht erlaubt. Du kannst sie in den Einstellungen bei PULSE ONE erlauben."
            case .recognizerUnavailable: "Die deutsche Spracherkennung ist gerade nicht erreichbar. Versuch es gleich noch einmal."
            case .audio(let detail): "Das Mikrofon ließ sich nicht starten (\(detail))."
            }
        }
    }

    private(set) var phase: VoicePhase = .idle
    /// What the person says right now.
    private(set) var partial = ""
    /// The conversation so far (this session only, nothing stored here).
    private(set) var turns: [VoiceTurn] = []
    private(set) var problem: Problem?
    /// True when recognition runs on the iPhone itself.
    private(set) var isOnDevice = false

    /// Finished utterances (for observers; ROOK's answers come from `responder`, or from `speak(_:for:)`).
    let utterances: AsyncStream<VoiceUtterance>

    /// ROOK's brain (team 04): gets the transcript, calls `onSentence` for every finished sentence while the answer
    /// streams in and returns the whole text. Cancelling the task ends the stream (barge-in).
    typealias Responder = @MainActor (_ transcript: String, _ onSentence: @escaping (String) -> Void) async -> String
    @ObservationIgnored var responder: Responder?

    @ObservationIgnored private let continuation: AsyncStream<VoiceUtterance>.Continuation
    @ObservationIgnored private var turnTaking = VoiceTurnTaking()
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    /// Recognizer callbacks of an older request carry an older generation and are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var answerTimeout: Task<Void, Never>?
    /// ROOK's answer: the turn it belongs to, its sentences still queued or speaking, and whether the stream ended.
    @ObservationIgnored private var answerTurn: Int?
    @ObservationIgnored private var answerItems: Set<UUID> = []
    @ObservationIgnored private var answerStreamDone = false
    @ObservationIgnored private var answerTask: Task<Void, Never>?
    /// Audio buffers arrive on the audio thread; the box hands them to the current request without the main actor.
    @ObservationIgnored private let buffers = BufferForwarder()
    @ObservationIgnored private let isUITesting = LaunchOptions.current.isUITesting
    @ObservationIgnored private let log = Logger(subsystem: "de.sommerlabs.pulseone", category: "voice")

    /// Safety net only: no first sentence within this time (network stuck), ROOK says so briefly and listens again.
    static let answerTimeoutSeconds: Double = 20

    init(audio: AudioCoordinator = .shared) {
        self.audio = audio
        (utterances, continuation) = AsyncStream.makeStream(of: VoiceUtterance.self, bufferingPolicy: .bufferingNewest(4))
        audio.onFinished = { [weak self] item in self?.audioFinished(item) }
        // ROOK's brain (team 04): streams sentence by sentence, shares the typed conversation's memory.
        responder = { text, onSentence in await RookStore.shared.talk(text, onSentence: onSentence) }
        // A call or pulled headphones ends the conversation; the microphone does not stay open behind it.
        audio.addInterruptionHandler { [weak self] in self?.stop() }
    }

    var isActive: Bool { phase != .idle }

    // MARK: Control

    /// Starts the conversation after asking for microphone and speech permission (first time only).
    func start() async {
        guard phase == .idle else { return }
        problem = nil
        if isUITesting {
            begin(at: .now)
            runScriptIfAny()
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = .microphoneDenied
            return
        }
        guard await Self.speechAuthorization() == .authorized else {
            problem = .speechDenied
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE")), recognizer.isAvailable else {
            problem = .recognizerUnavailable
            return
        }
        self.recognizer = recognizer
        isOnDevice = recognizer.supportsOnDeviceRecognition
        do {
            try startAudio()
        } catch {
            problem = .audio(error.localizedDescription)
            stopAudio()
            return
        }
        begin(at: .now)
        startRecognition()
    }

    func stop() {
        guard phase != .idle else { return }
        turnTaking.stop()
        sync()
        dropAnswer()
        clock?.cancel()
        clock = nil
        stopRecognition()
        stopAudio()
        audio.conversationPresence = nil
    }

    func toggle() async {
        if isActive { stop() } else { await start() }
    }

    /// ROOK's whole answer to `utterance`, for a consumer of `utterances` (when no `responder` is set).
    /// Dropped when the person has moved on in the meantime.
    func speak(_ text: String, for utterance: VoiceUtterance) {
        deliver(text, for: utterance)
        streamEnded(for: utterance)
    }

    // MARK: Turn-taking

    private func begin(at now: Date) {
        turnTaking.start(at: now)
        turns = []
        sync()
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let effect = turnTaking.tick(at: .now) else { return }
        handle(effect)
    }

    private func heard(_ text: String) {
        if let effect = turnTaking.heard(text, at: .now) { handle(effect) }
        sync()
    }

    private func handle(_ effect: VoiceTurnTaking.Effect) {
        switch effect {
        case .interruptRook:
            // The person speaks into the answer: ROOK stops at once (the rest of the stream too) and listens.
            dropAnswer()
        case .utterance(let utterance):
            turns.append(VoiceTurn(speaker: .person, text: utterance.text, at: utterance.at))
            continuation.yield(utterance)
            restartRecognition()
            answer(utterance)
        case .timedOut:
            stop()
        }
        sync()
    }

    /// Asks ROOK's brain (team 04) and speaks the answer sentence by sentence while it streams in, so the first
    /// words come after about a second. Without an answer in time ROOK says so briefly and listens again.
    private func answer(_ utterance: VoiceUtterance) {
        dropAnswer()
        answerTurn = utterance.turn
        let delay = isUITesting ? 5 : Self.answerTimeoutSeconds
        answerTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.answerTurn == utterance.turn, self.turnTaking.phase == .thinking else { return }
            self.answerTask?.cancel()
            self.speak(self.fallbackAnswer(to: utterance), for: utterance)
        }
        guard let responder else { return }
        let holdThinking = isUITesting
        answerTask = Task { [weak self] in
            // UI tests answer locally within milliseconds; "Ich denke nach …" stays up a moment so the M1 video
            // and DurchstichTests can see the phase (team 06).
            if holdThinking { try? await Task.sleep(for: .milliseconds(1500)) }
            guard !Task.isCancelled else { return }
            let full = await responder(utterance.text) { sentence in self?.deliver(sentence, for: utterance) }
            guard !Task.isCancelled, let self else { return }
            // Nothing streamed (e.g. a short local answer): speak the whole text.
            if self.turnTaking.phase == .thinking { self.deliver(full, for: utterance) }
            self.streamEnded(for: utterance)
        }
    }

    /// One sentence of ROOK's answer. The first one switches the turn to ROOK.
    private func deliver(_ text: String, for utterance: VoiceUtterance) {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, answerTurn == utterance.turn else { return }
        switch turnTaking.phase {
        case .thinking:
            guard turnTaking.answerStarted(for: utterance.turn) else { return }
            answerTimeout?.cancel()
            turns.append(VoiceTurn(speaker: .rook, text: sentence, at: .now))
            // A fresh request, so ROOK's own words never end up in the person's next utterance.
            restartRecognition()
        case .speaking where turnTaking.turn == utterance.turn:
            if let last = turns.indices.last, turns[last].speaker == .rook {
                turns[last] = VoiceTurn(id: turns[last].id, speaker: .rook, text: turns[last].text + " " + sentence, at: turns[last].at)
            }
        default:
            return
        }
        if let id = audio.say(sentence, channel: .interpretation, sensitive: true) { answerItems.insert(id) }
        sync()
    }

    private func streamEnded(for utterance: VoiceUtterance) {
        guard answerTurn == utterance.turn else { return }
        answerStreamDone = true
        finishAnswerIfDone()
    }

    /// Back to listening once the stream has ended and every sentence has been spoken.
    private func finishAnswerIfDone() {
        answerItems = answerItems.filter { audio.isPending($0) }
        guard answerStreamDone, answerItems.isEmpty else { return }
        answerTurn = nil
        answerStreamDone = false
        guard turnTaking.phase == .speaking else { return }
        turnTaking.answerFinished(at: .now)
        sync()
        restartRecognition()
    }

    private func dropAnswer() {
        answerTask?.cancel()
        answerTask = nil
        answerTimeout?.cancel()
        let speaking = answerItems
        answerItems = []
        answerTurn = nil
        answerStreamDone = false
        audio.cancel(speaking)
    }

    /// Without an answer from ROOK's brain (offline, team 04 not wired, UI tests): short, honest, no values.
    private func fallbackAnswer(to utterance: VoiceUtterance) -> String {
        if isUITesting {
            return "Testansicht: Ich habe „\(utterance.text)“ verstanden. Echte Antworten kommen hier nicht."
        }
        return "Da hänge ich gerade. Sag es gleich noch einmal?"
    }

    private func audioFinished(_ item: SpeechItem) {
        guard answerItems.remove(item.id) != nil else { return }
        finishAnswerIfDone()
    }

    private func sync() {
        phase = turnTaking.phase
        partial = turnTaking.partial
        audio.conversationPresence = phase == .idle ? nil : phase.presence
    }

    // MARK: Audio and recognition

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)
        audio.conversationOwnsSession = true
        let engine = AVAudioEngine()
        let buffers = self.buffers
        Self.installTap(on: engine.inputNode, forward: { buffer in buffers.append(buffer) })
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if audio.conversationOwnsSession {
            audio.conversationOwnsSession = false
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                log.error("Release: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startRecognition() {
        guard let recognizer, engine != nil else { return }
        generation += 1
        let current = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        buffers.set(request)
        task = Self.recognize(recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.recognized(text, isFinal: isFinal, failed: failed, generation: current) }
        }
    }

    private func stopRecognition() {
        generation += 1
        buffers.set(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func restartRecognition() {
        guard !isUITesting, phase != .idle else { return }
        stopRecognition()
        startRecognition()
    }

    private func recognized(_ text: String?, isFinal: Bool, failed: Bool, generation result: Int) {
        guard result == generation, phase != .idle else { return }
        if let text, !text.isEmpty { heard(text) }
        // Requests end on their own (final result, about a minute, errors): keep listening with a new one.
        if isFinal || failed { restartRecognition() }
    }

    // MARK: Off the main actor

    nonisolated private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    nonisolated private static func installTap(on node: AVAudioInputNode, forward: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in forward(buffer) }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                              handler: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    // MARK: UI tests

    /// `-uiTestVoice "Wie war meine Nacht?|Und mein Puls?"`: the utterances are "spoken" one after another,
    /// the second one into ROOK's answer (interruption). Without the argument nothing is simulated.
    private func runScriptIfAny() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiTestVoice"), index + 1 < arguments.count else { return }
        let lines = arguments[index + 1].split(separator: "|").map(String.init)
        Task { [weak self] in
            for (number, line) in lines.enumerated() {
                // The first line after a short pause; later lines once ROOK is speaking (interruption).
                if number > 0 {
                    for _ in 0..<50 where self?.phase != .speaking {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                } else {
                    try? await Task.sleep(for: .seconds(1))
                }
                var words: [Substring] = []
                for word in line.split(separator: " ") {
                    words.append(word)
                    self?.heard(words.joined(separator: " "))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
    }
}

/// Hands audio buffers from the audio thread to the current recognition request.
final class BufferForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}
