import PulseCore
import SwiftUI

/// "Messungen am Ring": how often the ring measures on its own, what it reported back, and the
/// history fetch. Features are listed by capability (`RingFeatureSupport`), never by model name,
/// so an R09 or a later ring shows what it can do without changes here.
struct RingMeasurementCard: View {
    @Environment(RingStore.self) private var ring

    var body: some View {
        let snapshot = ring.snapshot
        Card {
            Text("Messungen am Ring")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text("Der Ring misst selbstständig und speichert die Werte. PULSE ONE holt sie beim Verbinden und ab und zu beim Öffnen der App.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()

            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(RingMeasurementProfile.allCases) { profile in
                    profileRow(profile, selected: ring.measurementProfile == profile)
                }
            }

            Divider().overlay(Palette.hairline)
            Text("Was dieser Ring kann")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            ForEach(snapshot.features.visibleFeatures, id: \.self) { feature in
                featureRow(feature, snapshot: snapshot)
            }

            Divider().overlay(Palette.hairline)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.historySync.title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                if let detail = snapshot.historySync.detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("historySyncState")

            Button("Verlauf jetzt abrufen") { ring.syncHistoryNow() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(snapshot.connection != .ready || snapshot.historySync.isRunning)
                .accessibilityIdentifier("syncHistory")
        }
        .accessibilityIdentifier("ringMeasurementCard")
    }

    private func profileRow(_ profile: RingMeasurementProfile, selected: Bool) -> some View {
        Button {
            ring.setMeasurementProfile(profile)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.bioCyan : Palette.inkMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Text(profile.summary)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.leading)
                        .wraps()
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("profile.\(profile.rawValue)")
    }

    private func featureRow(_ feature: RingFeature, snapshot: RingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(feature.title)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(Self.status(feature, snapshot: snapshot))
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }

    static func status(_ feature: RingFeature, snapshot: RingSnapshot) -> String {
        if let setting = snapshot.ringSettings[feature] {
            guard setting.enabled else { return "am Ring ausgeschaltet" }
            if let minutes = setting.intervalMinutes { return "am Ring an, alle \(minutes) Minuten" }
            return "am Ring an"
        }
        switch snapshot.features.state(of: feature) {
        case .answered?: return "Ring hat geantwortet"
        case .waitingForTest?: return "vorbereitet, wird nach dem ersten Test mit diesem Ring freigeschaltet"
        case .unsupported?: return "Ring antwortet nicht"
        default: return snapshot.connection == .ready ? "wird geprüft" : "noch nicht geprüft"
        }
    }
}
