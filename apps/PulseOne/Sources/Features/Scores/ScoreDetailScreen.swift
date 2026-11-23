import Charts
import PulseCore
import SwiftData
import SwiftUI

/// One score: today's number with its building blocks, and the last 30 days as bars.
struct ScoreDetailScreen: View {
    let kind: ScoreKind
    @Environment(SourcesStore.self) private var sources
    @Environment(\.modelContext) private var modelContext
    @State private var today: ScoreResult = .noData
    @State private var history: [DayScore] = []
    @State private var loaded = false

    private var now: Date { LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : .now }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    headline
                    if let score = today.score { componentsCard(score) }
                    if history.count >= 2 { historyCard }
                    Text("Eigene, einfache Berechnung aus deinen gespeicherten Werten, nicht die von Oura. Keine Diagnose.")
                        .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.score")
    }

    private func reload() {
        let model = ScoreModel(reader: SampleReader(context: modelContext), profileID: sources.ownerProfileID, now: now)
        today = model.result(kind, on: now, inputs: model.inputs())
        history = model.history(kind)
        loaded = true
    }

    private var headline: some View {
        Card {
            HStack(spacing: Spacing.l) {
                ScoreRing(value: today.score?.value, tint: kind.tint, lineWidth: 12) {
                    Text(today.score.map { "\($0.value)" } ?? "–")
                        .font(Typography.wordmark.monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(headlineText).font(Typography.title).foregroundStyle(Palette.ink).wraps()
                    Text(kind.explanation).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("score.headline")
    }

    private var headlineText: String {
        switch today {
        case .ready(let score): "\(score.value) · \(score.word)"
        case .noData:
            loaded ? "Für heute gibt es noch keine Werte. Trag den Ring, auch nachts." : ""
        }
    }

    private func componentsCard(_ score: DayScore) -> some View {
        Card {
            SectionHeader(title: "Woraus sich der Wert ergibt")
            ForEach(score.components) { part in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(part.title).font(Typography.label).foregroundStyle(Palette.ink)
                        Spacer(minLength: Spacing.s)
                        Text("\(part.score)").font(Typography.label.monospacedDigit()).foregroundStyle(Palette.ink)
                    }
                    ProgressView(value: Double(part.score), total: 100)
                        .tint(kind.tint)
                        .accessibilityHidden(true)
                    Text(part.detail).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
                .accessibilityElement(children: .combine)
            }
            if let note = score.note {
                Text(note).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
    }

    private var historyCard: some View {
        Card {
            SectionHeader(title: "Letzte 30 Tage")
            Chart(history, id: \.day) { score in
                BarMark(x: .value("Tag", score.day, unit: .day), y: .value(kind.title, score.value))
                    .foregroundStyle(kind.tint)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 160)
            // One summary element instead of 30 thin bar elements (audit: hit area too small).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kind.title) der letzten 30 Tage")
            .accessibilityValue(history.last.map { "zuletzt \($0.value) von 100" } ?? "")
            let mean = history.map(\.value).reduce(0, +) / history.count
            Text("Im Mittel \(mean), an \(history.count) Tagen berechnet.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
        }
    }
}
