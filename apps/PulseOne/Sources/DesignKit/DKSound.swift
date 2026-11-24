import AVFoundation
import os

/// The sound family of PULSE ONE (Auftrag 02 §5): three short, soft tones from one world.
/// Files: `Resources/Media/Sounds/*.wav`, synthesized by `scripts/assets/synth-sounds.py`, listed in
/// `docs/media/MEDIA-REGISTER.md`. Not every event makes a sound; see `MotionEvent.sound`.
enum DKSound: String, CaseIterable, Sendable {
    /// Workout start: two rising notes.
    case start = "po-start"
    /// Next phase: one soft note.
    case phase = "po-phase"
    /// Workout complete: three-note rise that settles.
    case complete = "po-complete"

    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "wav") }
}

/// Plays the family sounds. `.ambient` follows the silent switch and mixes with music; the audio
/// coordinator of team 05 may take over the session for spoken workouts and calls `play` from there.
@MainActor
final class DKSoundPlayer {
    static let shared = DKSoundPlayer()

    /// Off in UI tests and when the user turned sounds off.
    var isEnabled = !LaunchOptions.current.isUITesting
    private var players: [DKSound: AVAudioPlayer] = [:]
    private let log = Logger(subsystem: "de.sommerlabs.pulseone", category: "design-sound")

    func play(_ sound: DKSound) {
        guard isEnabled else { return }
        do {
            let player: AVAudioPlayer
            if let cached = players[sound] {
                player = cached
            } else {
                guard let url = sound.url else {
                    log.error("Missing sound file \(sound.rawValue, privacy: .public)")
                    return
                }
                player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            }
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback && session.category != .playAndRecord {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            player.currentTime = 0
            player.play()
        } catch {
            log.error("Sound \(sound.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
