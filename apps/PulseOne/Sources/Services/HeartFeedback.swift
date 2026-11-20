import AVFoundation
import CoreHaptics
import os
import PulseCore

/// Haptic and sound "lub-dub", triggered once per visual beat so all three stay in sync.
@MainActor
final class HeartFeedback {
    private var haptics: CHHapticEngine?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var soundReady = false
    private let log = Logger(subsystem: "de.sommerlabs.pulseone", category: "heart-feedback")

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {   // Simulator: no haptics
            haptics = try? CHHapticEngine()
            haptics?.isAutoShutdownEnabled = true
        }
    }

    /// One beat. `gap` = seconds between lub and dub at the current tempo.
    func beat(gap: TimeInterval, haptic: Bool, sound: Bool) {
        if haptic { playHaptic(gap: gap) }
        if sound { playSound(gap: gap) }
    }

    func stop() {
        if soundReady {
            player.stop()
            engine.pause()
        }
        haptics?.stop(completionHandler: nil)
    }

    private func playHaptic(gap: TimeInterval) {
        guard let haptics else { return }
        do {
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45)
                ], relativeTime: gap)
            ]
            try haptics.start()
            try haptics.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
        } catch {
            log.error("Haptic beat: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func playSound(gap: TimeInterval) {
        guard let format else { return }
        if !soundReady {
            // .ambient respects the silent switch and mixes with other audio.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            soundReady = true
        }
        let samples = HeartSound.beat(gap: gap, sampleRate: format.sampleRate)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, s) in samples.enumerated() { channel[i] = s }
        do {
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        } catch {
            log.error("Sound beat: \(error.localizedDescription, privacy: .public)")
        }
    }
}
