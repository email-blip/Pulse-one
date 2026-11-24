import Foundation
import PulseCore

/// Former own speaker of the Begleiter screens; now a thin handle on the one `AudioCoordinator`, so the morning
/// briefing, check-in reading and the activation cues share the app's single speech queue (no overlap).
@MainActor
final class BriefingSpeaker {
    /// Training-style cues (activation) or health interpretation (briefing, check-in).
    private let channel: SpeechChannel

    init(channel: SpeechChannel = .interpretation) {
        self.channel = channel
    }

    /// True while this channel speaks; observable through the coordinator.
    var isSpeaking: Bool { AudioCoordinator.shared.isSpeaking(on: channel) }

    /// A new text replaces what this channel says now.
    func speak(_ text: String) {
        AudioCoordinator.shared.replace(channel: channel, with: text, sensitive: channel == .interpretation)
    }

    func stop() {
        if AudioCoordinator.shared.current?.channel == channel {
            AudioCoordinator.shared.stop()
        }
    }
}
