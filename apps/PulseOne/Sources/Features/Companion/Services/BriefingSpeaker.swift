import AVFoundation
import Foundation
import Observation
import os

/// Reads the morning briefing aloud with the best installed German voice (premium > enhanced > default).
/// Ducks other audio while speaking and releases the session afterwards. Silent in UI tests.
@MainActor
@Observable
final class BriefingSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "de.sommerlabs.pulseone", category: "companion-speech")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !LaunchOptions.current.isUITesting, !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activateSession()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestGermanVoice()
        utterance.postUtteranceDelay = 0.2
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else {
            finish()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        // The delegate's didCancel finishes the session.
    }

    /// Best installed de-DE voice; enhanced/premium voices exist only when the person downloaded them.
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

    // MARK: Audio session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            log.error("Audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finish() {
        isSpeaking = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("Audio session release: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: AVSpeechSynthesizerDelegate (called off the main actor)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishIfIdle() }
    }

    /// A new `speak` may already have started when a cancel callback arrives; only release when idle.
    private func finishIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        finish()
    }
}
