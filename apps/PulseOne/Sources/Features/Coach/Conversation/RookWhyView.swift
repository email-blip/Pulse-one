import PulseCore
import SwiftUI

/// "Warum?": everything a statement rests on. Measurements with their time and comparison, the comparison
/// window, events and the person's own answers, the calculation, other explanations with their fit, how sure
/// it is, when ROOK looks again and earlier versions after corrections. A measurement jumps to the Verlauf
/// when 03 provides `openTimeline`. Identifiers: `screen.why`, `why.evidence.<n>`, `why.close`.
struct RookWhyView: View {
    let statement: RookStatement
    let onClose: () -> Void
    @Environment(\.openTimeline) private var openTimeline

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        Card {
                            Text(statement.headline).font(Typography.title).foregroundStyle(Palette.ink).wraps()
                            Text(statement.insight.interpretation).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                            Label(statement.insight.direction.title, systemImage: symbol(statement.insight.direction))
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted)
                        }
                        if !statement.observation.isEmpty {
                            section("Was die Daten zeigen") { paragraph(statement.observation) }
                        }
                        if !statement.insight.evidence.isEmpty {
                            section("Messwerte") {
                                ForEach(Array(statement.insight.evidence.enumerated()), id: \.offset) { index, ref in
                                    evidenceRow(ref).accessibilityIdentifier("why.evidence.\(index)")
                                }
                            }
                        }
                        if !statement.why.comparison.isEmpty {
                            section("Vergleichszeitraum") { paragraph(statement.why.comparison) }
                        }
                        section("Ereignisse") {
                            if statement.why.events.isEmpty {
                                paragraph("Keine besonderen Ereignisse eingetragen.")
                            } else {
                                ForEach(statement.why.events, id: \.self) { paragraph($0) }
                            }
                        }
                        if !statement.why.calculation.isEmpty {
                            section("Berechnung") { paragraph(statement.why.calculation) }
                        }
                        if !statement.why.alternatives.isEmpty {
                            section("Andere Erklärungen") {
                                ForEach(statement.why.alternatives) { alternative in
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("\(alternative.title) · \(alternative.fit.title)")
                                            .font(Typography.label).foregroundStyle(Palette.ink).wraps()
                                        if !alternative.note.isEmpty { paragraph(alternative.note) }
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        if !statement.why.uncertainty.isEmpty {
                            section("Wie sicher") { paragraph(statement.why.uncertainty) }
                        }
                        if let recheck = statement.insight.recheckAt {
                            section("Nächster Blick") {
                                paragraph("ROOK schaut \(recheck.formatted(date: .abbreviated, time: .shortened)) wieder hin.")
                            }
                        }
                        if !statement.insight.revisions.isEmpty {
                            section("Frühere Fassung") {
                                ForEach(Array(statement.insight.revisions.enumerated()), id: \.offset) { _, revision in
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("\(revision.reason) · \(revision.at.formatted(date: .omitted, time: .shortened))")
                                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                                        paragraph(revision.interpretation)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        Text(statement.source == .claude ? "Formuliert von Claude, geprüft auf deinem iPhone."
                             : "Berechnet auf deinem iPhone.")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    }
                    .padding(Spacing.l)
                }
            }
            // Always present, not only in a test scenario (the M1 walkthrough looks for it).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.why")
            .navigationTitle("Warum?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen", action: onClose).accessibilityIdentifier("why.close")
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            SectionHeader(title: title)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(Typography.body).foregroundStyle(Palette.ink).wraps()
    }

    @ViewBuilder
    private func evidenceRow(_ ref: EvidenceRef) -> some View {
        let row = HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.label).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                if let comparison = ref.comparison {
                    Text(comparison).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
                Text(Self.windowText(ref.window)).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
            Spacer(minLength: Spacing.s)
            if let value = ref.shownValue {
                Text(value).font(Typography.label.weight(.semibold)).foregroundStyle(Palette.bioCyan)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        if let openTimeline {
            Button {
                onClose()
                openTimeline.open(Self.timelineState(for: ref))
            } label: { row }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet den Verlauf an dieser Stelle")
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    /// The Verlauf at the evidence's window, cursor in the middle, the matching track.
    static func timelineState(for ref: EvidenceRef) -> TimelineState {
        let track = ref.kind.flatMap { kind in TimelineTrack.allCases.first { $0.sampleKinds.contains(kind) } }
            ?? (ref.kind == .sleepDuration ? .sleepPhases : .heartRate)
        let range: TimelineRange = ref.window.duration > TimelineRange.originalResolutionLimit ? .week : .day
        return TimelineState(range: range, visible: ref.window,
                             cursor: ref.window.start.addingTimeInterval(ref.window.duration / 2), tracks: [track])
    }

    static func windowText(_ window: DateInterval) -> String {
        "\(window.start.formatted(date: .abbreviated, time: .shortened)) bis \(window.end.formatted(date: .abbreviated, time: .shortened))"
    }

    private func symbol(_ direction: CoachDirection) -> String {
        switch direction {
        case .improving: "arrow.up.right"
        case .stable: "equal"
        case .strained, .watch: "arrow.down.right"
        case .clarify, .urgent: "exclamationmark.triangle"
        }
    }
}
