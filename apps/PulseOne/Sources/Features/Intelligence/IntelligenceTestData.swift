import Foundation
import PulseCore
import SwiftData

/// Fixed content for the `intelligence` UI-test scenario (only with `-uiTesting YES`, always under the
/// "Testansicht" banner). Runs after the shared test history, so the report cites real context facts and
/// passes the same validator as a live answer. Never used outside test scenarios.
enum IntelligenceTestData {
    @MainActor
    static func insert(into context: ModelContext) {
        let now = TestScenario.fixedTime
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Double = 21) -> Date {
            (calendar.date(byAdding: .day, value: offset, to: today) ?? today).addingTimeInterval(hour * 3600)
        }

        let notes: [(Int, [ContextTag], Int?, String)] = [
            (-1, [.stress, .caffeine], 3, "Viel los im Büro, zwei Kaffee am Nachmittag."),
            (-2, [.training], 4, "Lockerer Lauf am Abend."),
            (-4, [.lateMeal, .screen], 3, "Spät gegessen, lange am Handy."),
            (-6, [.relaxed], 5, "Ruhiger Sonntag."),
        ]
        for (offset, tags, mood, text) in notes {
            context.insert(StoredNote(ContextEvent(date: day(offset), tags: tags, mood: mood, text: text)))
        }

        let samples = SampleReader(context: context).samples(Set(ConsentCategory.allCases.flatMap(\.kinds)),
                                                             since: day(-IntelligenceEngine.historyDays, hour: 0),
                                                             profileID: TestScenario.owner)
        let events = notes.map { ContextEvent(date: day($0.0), tags: $0.1, mood: $0.2, text: $0.3) }
        let weekly = ContextBuilder().build(samples: samples, events: events, kind: .weekly, now: now,
                                            consent: ConsentCategory.defaultConsent,
                                            profile: ProfileSummary(ageRange: "40–49", sex: nil, goals: []))
        let record = StoredAnalysis(kind: AnalysisPeriodKind.weekly.rawValue, title: AnalysisPeriodKind.weekly.title,
                                    model: .opus, contextJSON: weekly.compactJSON())
        record.createdAt = now.addingTimeInterval(-3600)
        record.respondingModel = ClaudeModel.opus.id
        if let validated = try? ResponseValidator(context: weekly).validateReport(json: MockTransport.report(facts: weekly.facts)) {
            record.resultJSON = IntelligenceEngine.json(validated.report)
            record.issuesJSON = IntelligenceEngine.json(validated.issues)
            record.flaggedJSON = IntelligenceEngine.json(validated.flagged)
        }
        let usage = TokenUsage(inputTokens: 4_200, outputTokens: 1_900)
        record.apply(usage, responder: ClaudeModel.opus.id, model: .opus)
        context.insert(record)

        let plan = ExperimentPlan(title: "Kaffee nach 14 Uhr", targetKind: .sleepDuration, conditionA: "Kaffee wie gewohnt",
                                  conditionB: "kein Kaffee nach 14 Uhr", blockDays: 5, blocks: 4, washoutDays: 1,
                                  notesNeeded: ["Uhrzeit des letzten Kaffees"],
                                  rationale: "Schlafdauer reagiert innerhalb weniger Tage; vier Blöcke gleichen Wochentage aus.")
        let experiment = StoredExperiment(question: "Schlafe ich ohne Kaffee am Nachmittag länger?", plan: plan, start: day(-3, hour: 0))
        experiment.createdAt = now.addingTimeInterval(-3 * 86_400)
        context.insert(experiment)

        let card = InsightCard(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1") ?? UUID(),
                               statement: "Nach Nächten mit mehr Schlaf lag dein Ruhepuls am Morgen meist niedriger.",
                               kindA: .sleepDuration, kindB: .restingHeartRate, lagDays: 0, rho: -0.41, n: 28,
                               periodText: "23.08.–20.11.2026", strength: .medium, origin: .correlation,
                               createdAt: day(-20, hour: 8), checkedAt: day(-20, hour: 8),
                               recheckDue: day(70, hour: 8), status: .active)
        context.insert(StoredInsight(card))
    }
}
