import Charts
import PulseCore
import SwiftData
import SwiftUI

/// Codex P1-005: one coherent insight. Observation (measured) → interpretation with alternatives → open
/// questions → one action → planned recheck → how the interpretation changed. Answers revise the
/// interpretation only; the measurements stay untouched. Shared time axis with real gaps.
struct InsightScreen: View {
    /// Test scenario name for the synthetic demo cases ("insightNormal", "insightNights", "insightGap"), else nil.
    var demo: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @State private var insight: Insight?
    @State private var accepted = false

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if demo != nil || LaunchOptions.current.usesTestScenario { TestBanner() }
                    if let insight {
                        content(insight)
                    } else {
                        ProgressView("Ich schaue in deine Nächte …")
                            .foregroundStyle(Palette.ink)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: insight)
            }
        }
        .navigationTitle("Einordnung")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .screenIdentifier(demo ?? "insight")
    }

    // MARK: Sections

    @ViewBuilder
    private func content(_ insight: Insight) -> some View {
        header(insight)
        if !insight.nights.isEmpty { NightAxis(nights: insight.nights, evidence: insight.evidence, reduceMotion: reduceMotion) }
        section("Gemessen", kind: .measured) {
            if insight.evidence.isEmpty {
                paragraph(insight.observation)
            }
            ForEach(insight.evidence) { item in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.text).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                    Text(provenance(item)).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
                .accessibilityElement(children: .combine)
            }
        }
        section("Deutung", kind: .computed) {
            paragraph(insight.interpretation)
        }
        if !insight.hypotheses.isEmpty {
            section("Mögliche Ursachen", kind: .hypothesis) {
                ForEach(insight.hypotheses) { hypothesis in hypothesisView(hypothesis) }
            }
        }
        if !insight.questions.isEmpty {
            section("Was mir noch fehlt", kind: .observed) {
                ForEach(insight.questions) { question in questionView(question, answer: insight.answers[question.id]) }
            }
        }
        section("Eine Aktion", kind: .suggestion) {
            Text(insight.action.text).font(Typography.title).foregroundStyle(Palette.ink).wraps()
            paragraph(insight.action.reason)
            Button {
                accepted = true
            } label: {
                Label(accepted ? "Übernommen" : "Übernehmen", systemImage: accepted ? "checkmark" : "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(accepted)
            .sensoryFeedback(.success, trigger: accepted)
            .accessibilityIdentifier("insight.accept")
        }
        section("Nachprüfung", kind: .observed) {
            Text("\(insight.recheck.at.formatted(date: .abbreviated, time: .shortened)): \(insight.recheck.what)")
                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
            paragraph("Ziel: \(insight.recheck.criterion)")
        }
        if !insight.revisions.isEmpty {
            section("So hat sich die Deutung geändert", kind: .computed) {
                ForEach(Array(insight.revisions.enumerated()), id: \.offset) { _, revision in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("\(revision.at.formatted(date: .omitted, time: .shortened)) · \(revision.reason)")
                            .font(Typography.label).foregroundStyle(Palette.ink).wraps()
                        Text("Vorher: \(revision.previousInterpretation)")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("insight.revisions")
        }
    }

    private func header(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(caseTitle(insight.insightCase), systemImage: caseSymbol(insight.insightCase))
                .font(Typography.label)
                .foregroundStyle(insight.insightCase == .changedNights ? Palette.pulseCoral : Palette.bioCyan)
            Text(insight.headline)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            Text(insight.dataThrough.map { "Datenstand: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Noch keine Daten")
                // Data freshness is key information, so full ink (inkMuted measured too low on run 134).
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
        .accessibilityIdentifier("insight.header")
    }

    private func section<Content: View>(_ title: String, kind: StatementKind, @ViewBuilder content: () -> Content) -> some View {
        Card {
            HStack {
                Text(title).font(Typography.label).foregroundStyle(Palette.bioCyan).accessibilityAddTraits(.isHeader)
                Spacer()
                StatementBadge(kind: kind)
            }
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(Typography.body).foregroundStyle(Palette.ink).wraps()
    }

    private func hypothesisView(_ hypothesis: InsightHypothesis) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(hypothesis.title).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                Spacer()
                Text(hypothesis.fit.title).font(Typography.caption.weight(.semibold))
                    .foregroundStyle(hypothesis.fit == .strong ? Palette.bioCyan : Palette.inkMuted)
            }
            Text(hypothesis.explanation).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            ForEach(hypothesis.supporting, id: \.self) { line in
                Label(line, systemImage: "plus.circle").font(Typography.caption).foregroundStyle(Palette.ink).wraps()
            }
            ForEach(hypothesis.against, id: \.self) { line in
                Label(line, systemImage: "minus.circle").font(Typography.caption).foregroundStyle(Palette.ink).wraps()
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func questionView(_ question: InsightQuestion, answer: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(question.text).font(Typography.body).foregroundStyle(Palette.ink).wraps()
            Text(question.why).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            HStack(spacing: Spacing.s) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        self.answer(question.id, option)
                    } label: {
                        Text(option)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: answer == option ? 3 : 0))
                    .accessibilityAddTraits(answer == option ? .isSelected : [])
                    .accessibilityIdentifier("insight.answer.\(question.id).\(option)")
                }
            }
        }
    }

    // MARK: Data

    private func load() {
        guard insight == nil else { return }
        let input: InsightInput
        if let demo {
            input = InsightDemo.input(for: demo)
        } else {
            input = InsightInputBuilder.make(context: modelContext, owner: sources.ownerProfileID, now: Date())
        }
        insight = InsightEngine.build(input, calendar: .current)
    }

    private func answer(_ question: String, _ option: String) {
        guard let current = insight else { return }
        insight = InsightEngine.revise(current, question: question, answer: option, at: Date())
        if demo == nil { InsightInputBuilder.storeAnswer(question, option) }
    }

    private func provenance(_ item: InsightEvidence) -> String {
        var parts = ["\(item.origin) · \(item.method)"]
        if let band = item.baseline {
            parts.append("Vergleich: \(band.nights) von \(band.windowNights) Nächten mit Daten")
        }
        return parts.joined(separator: " · ")
    }

    private func caseTitle(_ value: InsightCase) -> String {
        switch value {
        case .recovered: "Erholung"
        case .changedNights: "Veränderung, Ursache offen"
        case .dataGap: "Datenlücke"
        case .learning: "Lernphase"
        }
    }

    private func caseSymbol(_ value: InsightCase) -> String {
        switch value {
        case .recovered: "checkmark.seal"
        case .changedNights: MarkerSymbol.warning.systemImage
        case .dataGap: "icloud.slash"
        case .learning: "graduationcap"
        }
    }
}

/// Resting pulse and HRV of the nights on one time axis with the usual range. Missing nights stay gaps:
/// each run of consecutive nights is its own line segment.
private struct NightAxis: View {
    let nights: [NightPoint]
    let evidence: [InsightEvidence]
    let reduceMotion: Bool

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let segment: Int
        var id: Date { date }
    }

    private func points(_ value: (NightPoint) -> Double?) -> [Point] {
        let calendar = Calendar.current
        var result: [Point] = []
        var segment = 0
        var previous: Date?
        for night in nights.suffix(21) {
            guard let v = value(night) else {
                previous = nil
                continue
            }
            if let previous, let gap = calendar.dateComponents([.day], from: previous, to: night.date).day, gap > 1 { segment += 1 }
            if previous == nil, !result.isEmpty { segment += 1 }
            result.append(Point(date: night.date, value: v, segment: segment))
            previous = night.date
        }
        return result
    }

    var body: some View {
        Card {
            Text("Deine Nächte").font(Typography.label).foregroundStyle(Palette.bioCyan).accessibilityAddTraits(.isHeader)
            chart(title: "Ruhepuls (bpm)", points: points(\.restingHeartRate), band: evidence.first { $0.title == "Ruhepuls" }?.baseline,
                  color: Palette.pulseCoral)
            chart(title: "HRV (ms)", points: points(\.hrv), band: evidence.first { $0.title == "HRV" }?.baseline, color: Palette.bioCyan)
            Text(evidence.contains { $0.baseline != nil } ? "Lücken sind Nächte ohne Messung. Das Band ist dein üblicher Bereich."
                 : "Lücken sind Nächte ohne Messung.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
        }
    }

    private func chart(title: String, points: [Point], band: BaselineBand?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.inkMuted)
            Chart {
                if let band, let first = points.first?.date, let last = points.last?.date {
                    RectangleMark(xStart: .value("Start", first), xEnd: .value("Ende", last),
                                  yStart: .value("unten", band.p25), yEnd: .value("oben", band.p75))
                        .foregroundStyle(color.opacity(0.15))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Nacht", point.date), y: .value(title, point.value), series: .value("Abschnitt", point.segment))
                        .foregroundStyle(color)
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Nacht", point.date), y: .value(title, point.value))
                        .foregroundStyle(color)
                        .symbolSize(point.id == points.last?.id ? 80 : 20)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 120)
            // One element per chart: the band and points as separate elements are tiny and say nothing alone.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(points.last.map { "letzte Nacht \(LocalCheckInFormat.number($0.value))" } ?? "keine Werte")
        }
    }
}

enum LocalCheckInFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
    }
}
