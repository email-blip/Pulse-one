import PulseCore
import SwiftUI

/// Top of TODAY: what the companion said last, in one headline and up to three sentences, with its
/// symbols. Buttons: read aloud and check now.
struct CheckInCard: View {
    @Environment(CheckInService.self) private var service
    @State private var speaker = BriefingSpeaker()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(service.settings.name, systemImage: "waveform.path.ecg")
                    .font(Typography.label)
                    .foregroundStyle(Palette.bioCyan)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let latest = service.latest {
                    Text("\(latest.slot.title) · \(latest.date.formatted(date: .omitted, time: .shortened))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            if let latest = service.latest {
                content(latest)
            } else {
                Text("Ich melde mich morgens, mittags und abends von selbst mit dem, was deine Werte sagen.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.s))
                : AnyLayout(HStackLayout(spacing: Spacing.m))
            layout {
                if let latest = service.latest {
                    Button {
                        if speaker.isSpeaking { speaker.stop() } else { speaker.speak(spoken(latest)) }
                    } label: {
                        Label(speaker.isSpeaking ? "Stopp" : "Vorlesen", systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    Task { await service.run(slot: currentSlot, trigger: "manual") }
                } label: {
                    if service.isRunning {
                        ProgressView().accessibilityLabel("\(service.settings.name) schaut nach")
                    } else {
                        Label("Jetzt prüfen", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(service.isRunning)
            }
        }
        .accessibilityIdentifier("today.checkin")
    }

    @ViewBuilder
    private func content(_ latest: StoredCheckIn) -> some View {
        if latest.urgency >= .clarify {
            Label(latest.urgency == .urgent ? "Bitte sofort handeln" : "Bitte ärztlich abklären",
                  systemImage: MarkerSymbol.warning.systemImage)
                .font(Typography.label)
                .foregroundStyle(Palette.pulseCoral)
                .wraps()
        }
        Text(latest.headline)
            .font(Typography.title)
            .foregroundStyle(Palette.ink)
            .wraps()
        Text(latest.text)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .wraps()
        if !latest.suggestion.isEmpty {
            Label(latest.suggestion, systemImage: "arrow.right.circle")
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
        }
        ForEach(Array(latest.markers.enumerated()), id: \.offset) { _, marker in
            Label {
                Text(marker.text)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } icon: {
                Image(systemName: marker.symbol.systemImage)
                    .foregroundStyle(color(for: marker.symbol))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(marker.symbol.spokenName): \(marker.text)")
        }
        Text(latest.source == "claude" ? "Gedeutet von Claude" : "Lokal auf dem iPhone formuliert")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkMuted)
    }

    private var currentSlot: CheckInSlot {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return .morning }
        return hour < 17 ? .midday : .evening
    }

    private func spoken(_ latest: StoredCheckIn) -> String {
        [latest.headline + ".", latest.text, latest.suggestion].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func color(for symbol: MarkerSymbol) -> Color {
        switch symbol {
        case .warning: Palette.pulseCoral
        case .above, .below, .pattern: Palette.neuralViolet
        default: Palette.bioCyan
        }
    }
}
