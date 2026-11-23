import PulseCore
import SwiftData
import SwiftUI

// MARK: Body detective (creative lab idea 2)

/// Values outside the personal band, similar earlier days and what followed them. All local; Claude
/// only adds possible circumstances on request.
struct DetectiveView: View {
    let engine: IntelligenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @State private var cases: [DetectiveCase] = []
    @State private var loaded = false
    @State private var pending: PendingSend?
    @State private var result: StoredAnalysis?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    if let activity = engine.activity { WorkingCard(text: activity) }
                    if loaded && cases.isEmpty {
                        EmptyState(title: "Alles im üblichen Bereich",
                                   message: "Der Detektiv meldet sich, wenn ein Wert an zwei Tagen in Folge außerhalb deines üblichen Bereichs liegt.",
                                   systemImage: "checkmark.seal")
                    }
                    ForEach(Array(cases.enumerated()), id: \.offset) { _, detectiveCase in
                        caseCard(detectiveCase)
                    }
                    Text("Ähnliche frühere Tage zeigen, was bei dir danach vorkam. Das ist ein Muster, keine Ursache und keine Vorhersage.")
                        .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle("Körper-Detektiv")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pending) { item in
            SendPreviewView(preview: item.preview, blocker: item.blocker, onSend: item.send)
        }
        .navigationDestination(item: $result) { ReportView(analysis: $0) }
        .task {
            cases = engine.detectiveCases(modelContext: modelContext, owner: sources.ownerProfileID)
            loaded = true
        }
    }

    private func caseCard(_ detectiveCase: DetectiveCase) -> some View {
        let d = detectiveCase.deviation
        let shown = FactUnits.display(d.kind, d.value)
        let p25 = FactUnits.display(d.kind, d.p25)
        let p75 = FactUnits.display(d.kind, d.p75)
        let band = "\(FactUnits.text(p25.value, unit: "")) bis \(FactUnits.text(p75.value, unit: p75.unit))"
        return Card {
            StatementBadge(kind: .observed)
            Text("\(d.kind.title): \(FactUnits.text(shown.value, unit: shown.unit)), seit \(d.consecutiveDays) Tagen \(d.direction.text) deinem üblichen Bereich (\(band)).")
                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
            if detectiveCase.analogs.isEmpty {
                Text("Noch keine ähnlichen früheren Tage gefunden.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            } else {
                Text("\(detectiveCase.analogs.count) ähnliche frühere Tage. In den Tagen danach notiert:")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                ForEach(Array(detectiveCase.followUpSummary.enumerated()), id: \.offset) { _, item in
                    Label("\(item.count)× \(item.tag?.title ?? "nichts Besonderes")", systemImage: item.tag?.symbol ?? "minus.circle")
                        .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                }
            }
            if detectiveCase.hasEnoughForClaude {
                Button("Mögliche Begleitumstände mit Claude") { prepare(detectiveCase) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(engine.activity != nil)
            } else {
                Text("Für eine Deutung fehlt noch der Vergleich: An diesem Tag gibt es keine weiteren Messwerte wie Ruhepuls, HRV oder Schlaf und noch keine ähnlichen früheren Tage. Trag den Ring auch nachts, dann lohnt sich die Frage an Claude.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
    }

    private func prepare(_ detectiveCase: DetectiveCase) {
        let context = engine.hypothesesContext(for: detectiveCase, modelContext: modelContext)
        let title = "Detektiv: \(detectiveCase.deviation.kind.title)"
        let preview = engine.preview(title: title, context: context, system: IntelligencePrompts.detective(engine.settings.safetyMode),
                                     expectedOutputTokens: 1_500, modelContext: modelContext)
        pending = PendingSend(preview: preview, blocker: engine.blocker(for: preview, modelContext: modelContext)) {
            Task { result = await engine.runHypotheses(context: context, title: title, modelContext: modelContext) }
        }
    }
}

// MARK: Experiment lab (creative lab idea 3)

struct ExperimentsView: View {
    let engine: IntelligenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Query(sort: \StoredExperiment.createdAt, order: .reverse) private var experiments: [StoredExperiment]
    @State private var question = ""
    @State private var notice: String?
    @State private var draft: ExperimentPlan?
    @State private var draftQuestion = ""
    @State private var pending: PendingSend?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    if let activity = engine.activity { WorkingCard(text: activity) }
                    newCard
                    if let draft { draftCard(draft) }
                    ForEach(experiments) { experiment in
                        ExperimentCard(experiment: experiment, engine: engine)
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle("Experimente")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pending) { item in
            SendPreviewView(preview: item.preview, blocker: item.blocker, onSend: item.send)
        }
    }

    private var newCard: some View {
        Card {
            SectionHeader(title: "Neuer Selbstversuch")
            Text("Eine Alltagsfrage, abwechselnd in Blöcken getestet. Keine Medikamente, keine Nahrungsergänzung.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            TextField("Zum Beispiel: Schlafe ich ohne Kaffee nach 14 Uhr länger?", text: $question, axis: .vertical)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1...3)
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
            Button("Plan von Claude vorschlagen lassen") { prepare() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.activity != nil)
            if let notice {
                Text(notice).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
            }
        }
    }

    private func draftCard(_ plan: ExperimentPlan) -> some View {
        Card {
            SectionHeader(title: "Vorschlag")
            PlanSummary(plan: plan)
            Button("Morgen starten") { start(plan) }
                .buttonStyle(PrimaryButtonStyle())
            Button("Verwerfen") { draft = nil }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func prepare() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        notice = nil
        if case .rejected(let reason) = ExperimentLab.admissibility(of: text) {
            notice = reason
            return
        }
        let context = QuestionTools.context(facts: [], correlations: [], events: [], consent: [], now: engine.now)
        let preview = engine.preview(title: "Experiment planen: \(text)", context: context,
                                     system: IntelligencePrompts.experiment, expectedOutputTokens: 800, modelContext: modelContext)
        pending = PendingSend(preview: preview, blocker: engine.blocker(for: preview, modelContext: modelContext)) {
            Task {
                let outcome = await engine.planExperiment(text, modelContext: modelContext)
                if let plan = outcome.plan {
                    draft = plan
                    draftQuestion = text
                    question = ""
                } else {
                    notice = outcome.record.errorMessage
                }
            }
        }
    }

    private func start(_ plan: ExperimentPlan) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: engine.now)) ?? engine.now
        modelContext.insert(StoredExperiment(question: draftQuestion, plan: plan, start: tomorrow))
        try? modelContext.save()
        draft = nil
    }
}

struct PlanSummary: View {
    let plan: ExperimentPlan

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(plan.title).font(Typography.label).foregroundStyle(Palette.ink).wraps()
            Text("A: \(plan.conditionA)").font(Typography.caption).foregroundStyle(Palette.ink).wraps()
            Text("B: \(plan.conditionB)").font(Typography.caption).foregroundStyle(Palette.ink).wraps()
            Text("Gemessen: \(plan.targetKind.title) · \(plan.blocks) Blöcke à \(plan.blockDays) Tage · \(plan.totalDays) Tage insgesamt")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            if !plan.notesNeeded.isEmpty {
                Text("Täglich notieren: " + plan.notesNeeded.joined(separator: ", "))
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
            if !plan.rationale.isEmpty {
                StatementRow(text: plan.rationale, kind: .interpretation)
            }
        }
    }
}

struct ExperimentCard: View {
    let experiment: StoredExperiment
    let engine: IntelligenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources

    var body: some View {
        Card {
            if let plan = experiment.plan {
                PlanSummary(plan: plan)
                status(plan)
            }
        }
    }

    @ViewBuilder
    private func status(_ plan: ExperimentPlan) -> some View {
        let calendar = Calendar.current
        let schedule = ExperimentLab.schedule(plan, start: experiment.startDate, calendar: calendar)
        let today = calendar.startOfDay(for: engine.now)
        let lastDay = schedule.last?.date ?? experiment.startDate
        if experiment.statusRaw == "finished" {
            StatementRow(text: experiment.resultSummary, kind: .computed)
        } else if experiment.statusRaw == "cancelled" {
            Text("Abgebrochen").font(Typography.caption).foregroundStyle(Palette.inkMuted)
        } else if today < calendar.startOfDay(for: experiment.startDate) {
            Text("Startet am \(experiment.startDate.formatted(date: .abbreviated, time: .omitted)) mit Bedingung A.")
                .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
        } else if today <= lastDay {
            let day = schedule.first { calendar.isDate($0.date, inSameDayAs: today) }
            Text(Self.conditionText(day?.condition, plan: plan)).font(Typography.label).foregroundStyle(Palette.bioCyan).wraps()
            Button("Abbrechen") { setStatus("cancelled") }
                .buttonStyle(SecondaryButtonStyle())
        } else {
            if !experiment.resultSummary.isEmpty {
                Text(experiment.resultSummary).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
            Button("Auswerten") { evaluate(plan) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    static func conditionText(_ condition: ExperimentCondition?, plan: ExperimentPlan) -> String {
        switch condition {
        case .a: return "Heute gilt A: \(plan.conditionA)"
        case .b: return "Heute gilt B: \(plan.conditionB)"
        case nil: return "Heute ist ein Auswaschtag: einfach wie gewohnt."
        }
    }

    private func setStatus(_ status: String) {
        experiment.statusRaw = status
        try? modelContext.save()
    }

    /// Local evaluation on block means; a consistent difference becomes a body biography card.
    private func evaluate(_ plan: ExperimentPlan) {
        let calendar = Calendar.current
        let days = (calendar.dateComponents([.day], from: experiment.startDate, to: engine.now).day ?? 0) + 2
        let series = SampleReader(context: modelContext).daily(plan.targetKind, days: days, profileID: sources.ownerProfileID,
                                                               calendar: calendar, now: engine.now)
        var values: [Date: Double] = [:]
        for value in series { values[value.day] = value.value }
        let result = ExperimentLab.evaluate(plan, start: experiment.startDate, values: values, calendar: calendar)
        experiment.resultSummary = result.summary
        // Without enough data the experiment keeps running; the summary says how many days are missing.
        if result.verdict != .notEnoughData { experiment.statusRaw = "finished" }
        if let card = BodyBiography.card(from: result, plan: plan, start: experiment.startDate, now: engine.now) {
            modelContext.insert(StoredInsight(card))
        }
        try? modelContext.save()
    }
}

// MARK: Body biography (creative lab idea 5)

struct BiographyView: View {
    let engine: IntelligenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Query(sort: \StoredInsight.createdAt, order: .reverse) private var stored: [StoredInsight]
    @State private var suggestions: [InsightCard] = []

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    Text("Erkenntnisse aus deinen eigenen Daten. Jede Karte wird alle 90 Tage neu geprüft und verblasst, wenn sie nicht mehr trägt.")
                        .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    if stored.isEmpty && suggestions.isEmpty {
                        EmptyState(title: "Noch keine Karten",
                                   message: "Nach einigen Wochen mit Messwerten schlägt PULSE ONE hier Zusammenhänge vor. Abgeschlossene Experimente landen auch hier.",
                                   systemImage: "book.closed")
                    }
                    ForEach(suggestions) { card in
                        Card {
                            SectionHeader(title: "Vorschlag")
                            InsightRow(card: card)
                            Button("In die Biografie aufnehmen") { adopt(card) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    ForEach(stored) { item in
                        if let card = item.card { Card { InsightRow(card: card) } }
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle("Körperbiografie")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
    }

    private func refresh() {
        let samples = engine.samples(in: modelContext, owner: sources.ownerProfileID, days: BodyBiography.windowDays + 7)
        for item in stored {
            if let card = item.card, BodyBiography.isDue(card, now: engine.now) {
                item.update(BodyBiography.recheck(card, samples: samples, now: engine.now))
            }
        }
        try? modelContext.save()
        suggestions = BodyBiography.candidates(samples: samples, existing: stored.compactMap(\.card), now: engine.now)
    }

    private func adopt(_ card: InsightCard) {
        modelContext.insert(StoredInsight(card))
        try? modelContext.save()
        suggestions.removeAll { $0.id == card.id }
    }
}

struct InsightRow: View {
    let card: InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            StatementBadge(kind: card.origin == .experiment ? .computed : .observed)
            Text(card.statement).font(Typography.body).foregroundStyle(Palette.ink).wraps()
            Text("\(card.origin.title) · \(card.strength.title)").font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            Text(card.evidenceText).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            if card.status == .faded {
                Label("Zuletzt nicht mehr bestätigt", systemImage: "circle.dashed")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
        .opacity(card.status == .faded ? 0.7 : 1)
    }
}

// MARK: History

struct AnalysisHistoryView: View {
    @Query(sort: \StoredAnalysis.createdAt, order: .reverse) private var analyses: [StoredAnalysis]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    if analyses.isEmpty {
                        EmptyState(title: "Noch keine Analysen", message: "Berichte und Fragen an Claude erscheinen hier mit Datum und Kosten.",
                                   systemImage: "clock")
                    }
                    ForEach(analyses) { analysis in
                        NavigationLink(value: IntelligenceRoute.analysis(analysis)) {
                            Card {
                                Text(analysis.question.isEmpty ? analysis.title : analysis.question)
                                    .font(Typography.label).foregroundStyle(Palette.ink).wraps()
                                RunFooter(analysis: analysis)
                                if analysis.failed {
                                    Text(analysis.errorMessage).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if !analyses.isEmpty {
                        Button("Verlauf löschen", role: .destructive) { deleteAll() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteAll() {
        for analysis in analyses { modelContext.delete(analysis) }
        try? modelContext.save()
    }
}
