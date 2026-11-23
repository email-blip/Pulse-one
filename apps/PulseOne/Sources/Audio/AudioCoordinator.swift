import AVFoundation
import Foundation
import Observation
import os
import PulseCore

/// The one voice of PULSE ONE. Greeting, interpretation, training cues and alerts share one queue
/// (`SpeechQueue`), so nothing overlaps. Uses the best installed German voice, pauses for calls and when
/// headphones are pulled, and never continues health content over the built-in speaker after that.
/// Sets `presence` for ROOK (speaking / idle). Silent in UI tests (the queue still runs, nothing is played).
@MainActor
@Observable
final class AudioCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioCoordinator()

    /// What ROOK's figure shows; only this coordinator sets `speaking`.
    private(set) var presence: RookPresence = .idle
    /// The item being spoken (also while paused).
    private(set) var current: SpeechItem?
    /// Paused by the person, a call or lost headphones; `resume()` continues.
    private(set) var isPaused = false
    /// Set when headphones were pulled during health content: that content was dropped, not moved to the speaker.
    private(set) var droppedForPrivacy = false

    /// Training cues are checked against the running session right before they are spoken.
    @ObservationIgnored var trainingValidator: ((WorkoutCueToken) -> Bool)?
    /// Called on a call or lost headphones, so the training pauses with the voice.
    @ObservationIgnored var onInterruption: (() -> Void)?

    @ObservationIgnored private var queue = SpeechQueue()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var utteranceID: ObjectIdentifier?
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let isSilent = LaunchOptions.current.isUITesting
    @ObservationIgnored private let log = Logger(subsystem: "de.sommerlabs.pulseone", category: "audio")
    private static let lastGreetingKey = "audio.lastGreeting"

    override init() {
        super.init()
        synthesizer.delegate = self
        observeAudioSession()
    }

    var isSpeaking: Bool { current != nil && !isPaused }

    func isSpeaking(on channel: SpeechChannel) -> Bool { current?.channel == channel && !isPaused }

    // MARK: Speaking

    func say(_ text: String, channel: SpeechChannel, sensitive: Bool, token: WorkoutCueToken? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        droppedForPrivacy = false
        // A new request after a drop starts fresh; a paused sentence still waits for `resume()`.
        if current == nil { isPaused = false }
        queue.enqueue(SpeechItem(text: trimmed, channel: channel, isSensitive: sensitive, workoutToken: token))
        // Time-critical items cut a running interpretation short instead of waiting behind it.
        if channel == .training || channel == .alert, let current, current.channel != .training, current.channel != .alert {
            stopCurrent()
            return
        }
        speakNext()
    }

    /// Replaces whatever this channel says now (a new "Vorlesen" replaces the old one).
    func replace(channel: SpeechChannel, with text: String, sensitive: Bool) {
        queue.removeAll { $0.channel == channel }
        if current?.channel == channel {
            queue.enqueue(SpeechItem(text: text, channel: channel, isSensitive: sensitive))
            stopCurrent()
        } else {
            say(text, channel: channel, sensitive: sensitive)
        }
    }

    /// Greets at most every few hours, never on a tab change. Returns true when the greeting was queued.
    @discardableResult
    func greetIfDue(_ text: String, now: Date = .now) -> Bool {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.lastGreetingKey) as? Date
        guard GreetingPolicy.shouldGreet(lastGreeting: last, now: now, calendar: .current) else { return false }
        defaults.set(now, forKey: Self.lastGreetingKey)
        say(text, channel: .greeting, sensitive: false)
        return true
    }

    /// Drops training cues and cuts a running one: pause, skip and end make them stale.
    func cancelTraining() {
        queue.removeAll { $0.channel == .training }
        if current?.channel == .training { stopCurrent() }
    }

    func pause() {
        guard current != nil, !isPaused else { return }
        isPaused = true
        presence = .idle
        if !isSilent { synthesizer.pauseSpeaking(at: .word) }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        droppedForPrivacy = false
        guard current != nil else { speakNext(); return }
        if let token = current?.workoutToken, trainingValidator?(token) == false {
            stopCurrent()
            return
        }
        presence = .speaking
        if isSilent || !synthesizer.continueSpeaking() { finishCurrent() }
    }

    /// Stops everything and empties the queue.
    func stop() {
        queue.clear()
        isPaused = false
        stopCurrent()
    }

    private func speakNext() {
        guard current == nil, !isPaused else { return }
        while let item = queue.next() {
            if let token = item.workoutToken, trainingValidator?(token) == false { continue }
            start(item)
            return
        }
        presence = .idle
        releaseSession()
    }

    private func start(_ item: SpeechItem) {
        current = item
        presence = .speaking
        guard !isSilent else {
            // UI tests: nothing is played; the item counts as spoken right away.
            finishCurrent()
            return
        }
        activateSession()
        let utterance = AVSpeechUtterance(string: SpokenGerman.prepare(item.text))
        utterance.voice = VoiceStyle.bestGermanVoice()
        utterance.rate = VoiceStyle.rate(for: item.channel)
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = VoiceStyle.pauseAfter(item.channel)
        utteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    private func stopCurrent() {
        guard current != nil else { speakNext(); return }
        if isSilent || !synthesizer.isSpeaking {
            finishCurrent()
        } else {
            // didCancel finishes and moves on.
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func finishCurrent() {
        current = nil
        utteranceID = nil
        isPaused = false
        speakNext()
    }

    // MARK: AVSpeechSynthesizerDelegate (called off the main actor)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.utteranceEnded(id) }
    }

    /// Only the utterance that is current may end the item; late callbacks of older ones are ignored.
    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard id == utteranceID else { return }
        finishCurrent()
    }

    // MARK: Audio session

    private func activateSession() {
        guard !sessionActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            log.error("Audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func releaseSession() {
        guard sessionActive else { return }
        sessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("Audio session release: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let began = type == .began
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleInterruption(began: began)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleHeadphonesLost()
            }
        })
    }

    /// A call or another app's audio: pause; the person resumes (no automatic restart in the middle of a sentence).
    private func handleInterruption(began: Bool) {
        guard began else { return }
        if current != nil { pause() }
        onInterruption?()
    }

    /// Headphones pulled: pause, and drop health content instead of continuing it over the speaker.
    private func handleHeadphonesLost() {
        let speakerNow = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        if current != nil { pause() }
        if speakerNow {
            let hadSensitive = current?.isSensitive == true || queue.pending.contains(where: \.isSensitive)
            queue.removeAll { $0.isSensitive }
            if current?.isSensitive == true {
                // Dropped without moving on: the queue stays paused until the person resumes.
                current = nil
                utteranceID = nil
                isPaused = true
                if !isSilent { synthesizer.stopSpeaking(at: .immediate) }
            }
            droppedForPrivacy = hadSensitive
        }
        onInterruption?()
    }
}

/// Voice and tempo. One voice for everything; training a touch quicker, interpretation a touch calmer.
enum VoiceStyle {
    static func rate(for channel: SpeechChannel) -> Float {
        let base = AVSpeechUtteranceDefaultSpeechRate
        switch channel {
        case .training: return base * 1.04
        case .interpretation: return base * 0.96
        case .greeting, .alert: return base
        }
    }

    static func pauseAfter(_ channel: SpeechChannel) -> TimeInterval {
        channel == .interpretation ? 0.35 : 0.15
    }

    /// Best installed de-DE voice: premium > enhanced > default (premium/enhanced only when downloaded in Settings).
    static func bestGermanVoice() -> AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "de-DE" }
        let best = german.max { rank($0.quality) < rank($1.quality) }
        return best ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    private static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: 3
        case .enhanced: 2
        case .default: 1
        @unknown default: 0
        }
    }
}
