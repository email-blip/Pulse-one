import Foundation
import Testing
@testable import PulseCore

// Codex P1-005: insights as observation → interpretation with alternatives → action → recheck, and the
// rules for when the companion calls Claude or notifies.

private let insightCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private func day(_ offset: Int, hour: Int = 7) -> Date {
    let base = insightCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: hour)) ?? .distantPast
    return insightCalendar.date(byAdding: .day, value: offset, to: base) ?? base
}

private func night(_ offset: Int, rhr: Double?, hrv: Double?, sleep: Double?) -> NightPoint {
    NightPoint(date: insightCalendar.startOfDay(for: day(offset)), restingHeartRate: rhr, hrv: hrv, sleepHours: sleep)
}

/// 28 calm nights (resting pulse 55–58, HRV 40–46, sleep 6.8–7.6 h), the newest `start` days before today.
private func calmHistory(from start: Int = 1) -> [NightPoint] {
    (start...(start + 27)).map { offset in
        night(-offset, rhr: 55 + Double(offset % 4), hrv: 40 + Double(offset % 7), sleep: 6.8 + Double(offset % 5) * 0.2)
    }
}

private func input(_ nights: [NightPoint], newest: Date? = day(0), now: Date = day(0, hour: 8),
                   answers: [String: String] = [:]) -> InsightInput {
    InsightInput(profileID: UUID(), now: now, nights: nights, origin: "Ring R03 · Verlauf", hrvMethod: "Ring-HRV",
                 newestSample: newest, lastSync: newest, answers: answers)
}

@Suite("Insight cases")
struct InsightCaseTests {
    @Test func normalRecoveryKeepsTrainingAndPlansARecheck() {
        let nights = calmHistory() + [night(0, rhr: 54, hrv: 46, sleep: 7.4)]
        let insight = InsightEngine.build(input(nights), calendar: insightCalendar)
        #expect(insight.insightCase == .recovered)
        #expect(insight.action.kind == .trainAsPlanned)
        #expect(insight.evidence.allSatisfy { $0.kind == .measurement && $0.baseline != nil && $0.origin == "Ring R03 · Verlauf" })
        #expect(insight.recheck.at > insight.createdAt)
    }

    @Test func contradictionChangesTheInterpretationNotTheMeasurement() {
        let nights = calmHistory() + [night(0, rhr: 54, hrv: 46, sleep: 7.4)]
        let insight = InsightEngine.build(input(nights), calendar: insightCalendar)
        let revised = InsightEngine.revise(insight, question: "feeling", answer: "Schlapp", at: day(0, hour: 9))
        #expect(revised.evidence == insight.evidence)
        #expect(revised.nights == insight.nights)
        #expect(revised.action.kind == .easeOff)
        #expect(revised.revisions.count == 1)
        #expect(revised.revisions.first?.previousInterpretation == insight.interpretation)
    }

    @Test func severalChangedNightsKeepTheCauseOpenWithAlternatives() {
        let nights = calmHistory(from: 3) + [night(-2, rhr: 62, hrv: 33, sleep: 7.0), night(-1, rhr: 63, hrv: 31, sleep: 6.9),
                                      night(0, rhr: 64, hrv: 30, sleep: 7.1)]
        let insight = InsightEngine.build(input(nights), calendar: insightCalendar)
        #expect(insight.insightCase == .changedNights)
        #expect(insight.action.kind == .easeOff)
        #expect(insight.hypotheses.count >= 3)
        #expect(insight.hypotheses.allSatisfy { $0.fit != .strong })
        #expect(!insight.questions.isEmpty)
        // No diagnosis percentages anywhere.
        let texts = [insight.interpretation] + insight.hypotheses.map(\.explanation)
        #expect(texts.allSatisfy { !$0.contains("%") })
    }

    @Test func answersNarrowTheCauseAndAreLogged() {
        let nights = calmHistory(from: 2) + [night(-1, rhr: 63, hrv: 31, sleep: 6.9), night(0, rhr: 64, hrv: 30, sleep: 7.1)]
        let insight = InsightEngine.build(input(nights), calendar: insightCalendar)
        let revised = InsightEngine.revise(insight, question: "training", answer: "Ja", at: day(0, hour: 9))
        #expect(revised.hypotheses.first?.id == "H-load")
        #expect(revised.hypotheses.first?.fit == .strong)
        #expect(revised.interpretation.contains("Hohe Trainingsbelastung"))
        #expect(revised.revisions.count == 1)
        // The same answer again changes nothing.
        #expect(InsightEngine.revise(revised, question: "training", answer: "Ja", at: day(0, hour: 10)) == revised)
    }

    @Test func oneStrongValueIsEnoughWithoutASecondOne() {
        let nights = calmHistory() + [night(0, rhr: 67, hrv: 43, sleep: 7.2)]
        #expect(InsightEngine.build(input(nights), calendar: insightCalendar).insightCase == .changedNights)
    }

    @Test func missingLastNightIsAGapAndNeverOldDataAsToday() {
        let nights = calmHistory()
        let insight = InsightEngine.build(input(nights, newest: day(-1)), calendar: insightCalendar)
        #expect(insight.insightCase == .dataGap)
        #expect(insight.action.kind == .sync)
        #expect(insight.evidence.allSatisfy { $0.value == nil })
    }

    @Test func staleSyncIsAGapEvenWithANightRow() {
        let nights = calmHistory() + [night(0, rhr: 55, hrv: 42, sleep: 7)]
        let insight = InsightEngine.build(input(nights, newest: day(-1, hour: 6), now: day(0, hour: 12)), calendar: insightCalendar)
        #expect(insight.insightCase == .dataGap)
    }

    @Test func notWornAnswerKeepsTheGapInsteadOfGuessing() {
        let insight = InsightEngine.build(input(calmHistory(), newest: day(-1)), calendar: insightCalendar)
        let revised = InsightEngine.revise(insight, question: "worn", answer: "Nein", at: day(0, hour: 9))
        #expect(revised.action.kind == .observe)
        #expect(revised.hypotheses.first?.id == "H-worn")
    }

    @Test func fewNightsMeansLearning() {
        let nights = (0...3).map { night(-$0, rhr: 56, hrv: 42, sleep: 7) }
        #expect(InsightEngine.build(input(nights), calendar: insightCalendar).insightCase == .learning)
    }

    @Test func recheckComparesTheNextNight() {
        let nights = calmHistory(from: 2) + [night(-1, rhr: 63, hrv: 31, sleep: 6.9), night(0, rhr: 64, hrv: 30, sleep: 7.1)]
        let insight = InsightEngine.build(input(nights), calendar: insightCalendar)
        let tomorrow = day(1, hour: 9)
        #expect(InsightEngine.evaluateRecheck(insight, nights: nights, now: day(0, hour: 20), calendar: insightCalendar) == .notYet)
        #expect(InsightEngine.evaluateRecheck(insight, nights: nights, now: tomorrow, calendar: insightCalendar) == .noData)
        let better = nights + [night(1, rhr: 56, hrv: 41, sleep: 7.5)]
        if case .resolved = InsightEngine.evaluateRecheck(insight, nights: better, now: tomorrow, calendar: insightCalendar) {} else {
            Issue.record("expected resolved")
        }
    }
}

@Suite("Check-in policy")
struct CheckInPolicyTests {
    private func message(_ urgency: CheckInUrgency = .none, markers: [CheckInMarker] = []) -> CheckInMessage {
        CheckInMessage(headline: "h", text: "t", suggestion: "", urgency: urgency, markers: markers)
    }

    @Test func nothingNewMeansNoClaudeCall() {
        #expect(!CheckInPolicy.shouldCallClaude(fingerprint: "a", lastFingerprint: "a", stale: false, hasFacts: true))
        #expect(CheckInPolicy.shouldCallClaude(fingerprint: "b", lastFingerprint: "a", stale: false, hasFacts: true))
        #expect(!CheckInPolicy.shouldCallClaude(fingerprint: "b", lastFingerprint: "a", stale: true, hasFacts: true))
        #expect(!CheckInPolicy.shouldCallClaude(fingerprint: "b", lastFingerprint: nil, stale: false, hasFacts: false))
    }

    @Test func staleDataAreSaidToBeStale() {
        #expect(CheckInPolicy.isStale(newestSample: nil, now: day(0)))
        #expect(CheckInPolicy.isStale(newestSample: day(-1), now: day(0, hour: 12)))
        #expect(!CheckInPolicy.isStale(newestSample: day(0, hour: 6), now: day(0, hour: 12)))
        #expect(CheckInPolicy.staleMessage(newestSample: day(-1), now: day(0, hour: 12)).headline == "Noch nicht abgeglichen")
    }

    @Test func calmRepeatDoesNotNotify() {
        let calm = message()
        #expect(!CheckInPolicy.shouldNotify(calm, previous: calm, freshNight: false, pushesToday: [], now: day(0, hour: 13),
                                            calendar: insightCalendar))
    }

    @Test func newChangeNotifiesWithinLimits() {
        let changed = message(markers: [CheckInMarker(symbol: .above, metric: "resting_heart_rate", text: "x")])
        #expect(CheckInPolicy.shouldNotify(changed, previous: message(), freshNight: false, pushesToday: [], now: day(0, hour: 13),
                                           calendar: insightCalendar))
        // Quiet hours, daily limit and minimum gap.
        #expect(!CheckInPolicy.shouldNotify(changed, previous: message(), freshNight: false, pushesToday: [], now: day(0, hour: 23),
                                            calendar: insightCalendar))
        #expect(!CheckInPolicy.shouldNotify(changed, previous: message(), freshNight: false,
                                            pushesToday: [day(0, hour: 8), day(0, hour: 9)], now: day(0, hour: 13), calendar: insightCalendar))
        #expect(!CheckInPolicy.shouldNotify(changed, previous: message(), freshNight: false, pushesToday: [day(0, hour: 12)],
                                            now: day(0, hour: 13), calendar: insightCalendar))
    }

    @Test func clarifyIgnoresQuietHours() {
        #expect(CheckInPolicy.shouldNotify(message(.clarify), previous: message(), freshNight: false, pushesToday: [day(0, hour: 8), day(0, hour: 9)],
                                           now: day(0, hour: 23), calendar: insightCalendar))
    }

    @Test func fingerprintIgnoresOrder() {
        let a = AnalysisFact(id: "F1", kind: "steps", title: "Schritte", stat: "so_far_today", value: 1000, unit: "", period: "",
                             n: 3, coverage: 1, baseline: nil, source: "", quality: "")
        let b = AnalysisFact(id: "F2", kind: "sleep_duration", title: "Schlaf", stat: "day_value", value: 7, unit: "h", period: "",
                             n: 1, coverage: 1, baseline: nil, source: "", quality: "")
        func context(_ facts: [AnalysisFact]) -> HealthAnalysisContext {
            HealthAnalysisContext(analysisType: "daily", generatedAt: "", period: AnalysisPeriod(start: "", end: "", timezone: ""),
                                  comparisonPeriod: nil, profile: .empty, consentedCategories: [], facts: facts,
                                  correlations: [], events: [], dataGaps: [])
        }
        #expect(CheckInPolicy.fingerprint(context([a, b])) == CheckInPolicy.fingerprint(context([b, a])))
        #expect(CheckInPolicy.fingerprint(context([a])) != CheckInPolicy.fingerprint(context([a, b])))
    }
}
