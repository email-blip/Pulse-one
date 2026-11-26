import PulseCore
import SwiftUI

/// Component preview in the order of the reference mockup (plan §4), shown only in the UI-test scenario
/// `designKit` with the "Testansicht" banner. All values are invented display examples, no measurements.
/// Teams 03–05 build their screens from these parts; this screen is what the screenshot matrix checks.
struct DesignKitReferenceScreen: View {
    static let scenario = "designKit"

    @State private var range = "Tag"
    @State private var presence: RookPresence = .speaking
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpace.xl) {
                TestBanner()

                RookHeader(presence: presence, onReadAloud: {}, isSpeaking: presence == .speaking)
                CoachHeadline(headline: "Heute ist Platz für einen guten Reiz.",
                              interpretation: "Du bist gut in deinen Rhythmus zurückgekommen. Heute passt eine kontrollierte Einheit, mit sauberer Technik statt maximalem Tempo.")
                actions

                DKSectionHeader(title: "Dein Cockpit", info: "Halte eine Kachel gedrückt und zieh sie an ihren Platz.",
                                actionTitle: "Kacheln anordnen", actionIdentifier: "designKit.arrange", action: {})
                tiles

                DKSectionHeader(title: "Zeitraum")
                FlowLayout(spacing: DKSpace.s) {
                    ForEach(["Tag", "Woche", "Monat", "3 Monate"], id: \.self) { title in
                        DKChip(title: title, isSelected: range == title) { range = title }
                    }
                }
                .dkMotion(.rangeChange, value: range)

                DKSectionHeader(title: "Schlafphasen")
                DKCard {
                    hypnogramSample
                    SleepPhaseLegend()
                }

                DKSectionHeader(title: "ROOK-Zustände")
                presenceRow

                DKCard(isCoach: true) {
                    Label("Diese Veränderung würde ich abklären lassen.", systemImage: "stethoscope")
                        .font(DKFont.bodyEmphasis)
                        .foregroundStyle(DKColor.textPrimary)
                        .wraps()
                    Text("Ich habe dir den Verlauf und die entscheidenden Beobachtungen zusammengestellt.")
                        .font(DKFont.body)
                        .foregroundStyle(DKColor.textSecondary)
                        .wraps()
                }
            }
            .padding(.horizontal, DKSpace.page)
            .padding(.vertical, DKSpace.l)
        }
        .dkPageBackground()
        .dkOpaqueBars()
        .screenIdentifier(Self.scenario)
    }

    @ViewBuilder
    private var actions: some View {
        if DKLayout.isSingleColumn(typeSize) {
            VStack(alignment: .leading, spacing: DKSpace.m) {
                startButton.buttonStyle(DKPrimaryButtonStyle(fullWidth: true))
                whyButton.buttonStyle(DKSecondaryButtonStyle(fullWidth: true))
            }
        } else {
            HStack(spacing: DKSpace.m) {
                startButton.buttonStyle(DKPrimaryButtonStyle())
                whyButton.buttonStyle(DKSecondaryButtonStyle())
            }
        }
    }

    private var startButton: some View {
        Button {} label: { Label("Meine Einheit starten", systemImage: "arrow.up.right").labelStyle(TrailingIconLabelStyle()) }
            .accessibilityIdentifier("designKit.primary")
    }

    private var whyButton: some View {
        Button("Warum?") {}
            .accessibilityIdentifier("designKit.why")
    }

    @ViewBuilder
    private var tiles: some View {
        let heart = MetricTile(kind: .restingHeartRate, value: "56", unit: "bpm", reference: "Nacht · 07:00") {
            Sparkline(values: [61, 59, 60, 57, 58, 56, 57, 56], tint: MetricStyle.of(.restingHeartRate).color)
        }
        let hrv = MetricTile(kind: .ringHRV, value: "54", unit: "ms", reference: "Nacht · 06:45") {
            Sparkline(values: [44, 47, nil, 50, 49, 53, 54], tint: MetricStyle.of(.ringHRV).color)
        }
        let oxygen = MetricTile(kind: .oxygenSaturation, value: "97", unit: "%", reference: "Messung · 06:30") {
            Sparkline(values: [96, 97, 97, 96, 98, 97], tint: MetricStyle.of(.oxygenSaturation).color)
        }
        // Long values on purpose: six digits in a wide tile and five in a large one must stay whole at every
        // Dynamic Type size (DesignKitLargeTextTests).
        let steps = MetricTile(kind: .steps, value: "123.456", unit: "Schritte", reference: "Heute · 14:20", size: .wide) {
            Sparkline(values: [0, 300, 1_800, 3_900, 5_200, 6_100, 8_412], tint: MetricStyle.of(.steps).color)
        }
        let energy = MetricTile(kind: .activeEnergy, value: "12.345", unit: "kcal", reference: "Woche · bis 14:20", size: .large) {
            Sparkline(values: [800, 1_900, 3_400, 5_100, 7_600, 9_800, 12_345], tint: MetricStyle.of(.activeEnergy).color)
        }
        if DKLayout.isSingleColumn(typeSize) {
            VStack(spacing: DKSpace.m) { heart; hrv; oxygen; steps; energy }
        } else {
            Grid(horizontalSpacing: DKSpace.m, verticalSpacing: DKSpace.m) {
                GridRow { heart; hrv }
                GridRow { steps.gridCellColumns(2) }
                GridRow { energy.gridCellColumns(2) }
                GridRow {
                    oxygen
                    MetricTile(kind: .ringStress, value: nil, unit: "", reference: "Noch keine Messung heute") { EmptyView() }
                }
            }
        }
    }

    /// Static sample of phase blocks on their rows (awake top … deep bottom, unknown below).
    private var hypnogramSample: some View {
        let blocks: [(SleepPhase, CGFloat, CGFloat)] = [
            (.awake, 0, 0.05), (.light, 0.05, 0.2), (.deep, 0.2, 0.33), (.light, 0.33, 0.45), (.rem, 0.45, 0.55),
            (.unknown, 0.55, 0.6), (.light, 0.6, 0.72), (.deep, 0.72, 0.8), (.rem, 0.8, 0.93), (.awake, 0.93, 1)
        ]
        return GeometryReader { proxy in
            let rowHeight = proxy.size.height / 5
            ForEach(blocks.indices, id: \.self) { index in
                let block = blocks[index]
                SleepPhaseFill(phase: block.0)
                    .frame(width: max(2, (block.2 - block.1) * proxy.size.width - 2), height: rowHeight - 4)
                    .offset(x: block.1 * proxy.size.width,
                            y: CGFloat(SleepPhaseStyle.of(block.0).level) * rowHeight + 2)
            }
        }
        .frame(height: 110)
        .accessibilityElement()
        .accessibilityLabel("Beispiel-Hypnogramm mit allen Schlafphasen")
    }

    private var presenceRow: some View {
        FlowLayout(spacing: DKSpace.m) {
            ForEach(RookPresence.allCases, id: \.self) { state in
                Button { presence = state } label: {
                    VStack(spacing: DKSpace.xs) {
                        RookOrb(presence: state, size: 40)
                        Text(Self.presenceName(state))
                            .font(DKFont.caption)
                            .foregroundStyle(DKColor.textSecondary)
                    }
                    .frame(minWidth: 72, minHeight: DKSize.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RookOrb.label(for: state))
                .accessibilityAddTraits(presence == state ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private static func presenceName(_ state: RookPresence) -> String {
        switch state {
        case .idle: "Ruhe"
        case .listening: "Zuhören"
        case .thinking: "Denken"
        case .speaking: "Sprechen"
        case .confirming: "Bestätigen"
        case .alerting: "Hinweis"
        }
    }
}

/// Text first, icon after ("Meine Einheit starten ↗").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DKSpace.s) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}
