import Foundation
import Testing
@testable import PulseCore

// Codex P1-005: consent, budget, provider errors, duplicate hints, source change and training feedback.

private let gateCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private func conditions(enabled: Bool = true, categories: Int = 3, test: Bool = false, calls: Int = 0, budget: String? = nil,
                        fingerprint: String = "b", last: String? = "a", stale: Bool = false, facts: Bool = true) -> CheckInGate.Conditions {
    .init(sendingEnabled: enabled, consentedCategories: categories, testMode: test, claudeCallsToday: calls, maxClaudeCallsPerDay: 4,
          budgetBlocker: budget, fingerprint: fingerprint, lastFingerprint: last, stale: stale, hasFacts: facts)
}

@Suite("Check-in gate")
struct CheckInGateTests {
    @Test func newDataWithConsentCallsClaude() {
        #expect(CheckInGate.route(conditions()) == .claude)
    }

    @Test func missingConsentStaysLocal() {
        #expect(CheckInGate.route(conditions(enabled: false)) == .local(.noConsent))
        // Switched on, but every data category withdrawn: still nothing leaves the phone.
        #expect(CheckInGate.route(conditions(categories: 0)) == .local(.noConsent))
    }

    @Test func budgetLimitStaysLocal() {
        #expect(CheckInGate.route(conditions(budget: "Monatsbudget aufgebraucht")) == .local(.budget))
        #expect(CheckInGate.route(conditions(calls: 4)) == .local(.dailyLimit))
    }

    @Test func nothingNewOrStaleStaysLocal() {
        #expect(CheckInGate.route(conditions(fingerprint: "a", last: "a")) == .local(.nothingNew))
        #expect(CheckInGate.route(conditions(stale: true)) == .local(.stale))
        #expect(CheckInGate.route(conditions(facts: false)) == .local(.noFacts))
        #expect(CheckInGate.route(conditions(test: true)) == .local(.testMode))
    }

    @Test func providerErrorKeepsTheLocalMessage() {
        let local = CheckInMessage(headline: "Ruhepuls erhöht", text: "t", suggestion: "", urgency: .watch, markers: [])
        let merged = CheckInGate.merge(local: local, claude: nil)
        #expect(merged.message == local)
        #expect(!merged.fromClaude)
    }

    @Test func localWarningWinsOverACalmerAnswer() {
        let local = CheckInMessage(headline: "h", text: "t", suggestion: "", urgency: .clarify, markers: [])
        let calm = CheckInMessage(headline: "Alles ruhig", text: "t", suggestion: "", urgency: .none, markers: [])
        let merged = CheckInGate.merge(local: local, claude: calm)
        #expect(merged.fromClaude)
        #expect(merged.message.urgency == .clarify)
    }

    @Test func sameWarningTwiceNotifiesOnce() {
        let warning = CheckInMessage(headline: "h", text: "t", suggestion: "", urgency: .watch,
                                     markers: [CheckInMarker(symbol: .warning, metric: "resting_heart_rate", text: "x")])
        let now = gateCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 13)) ?? .now
        let earlier = gateCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 8)) ?? .now
        #expect(!CheckInPolicy.shouldNotify(warning, previous: warning, freshNight: false, pushesToday: [earlier], now: now,
                                            calendar: gateCalendar))
    }
}

@Suite("Night sources")
struct NightAssemblerTests {
    private func day(_ offset: Int) -> Date {
        let base = gateCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22)) ?? .distantPast
        return gateCalendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    @Test func sourceChangeIsNotMixedIntoTheComparison() {
        // 20 nights of Apple SDNN, then the ring takes over for the last 3 nights.
        let sdnn = (3...22).map { NightValue(day: day(-$0), value: 60, source: "SDNN · Apple Health") }
        let ring = (0...2).map { NightValue(day: day(-$0), value: 30, source: "Ring-HRV") }
        let result = NightAssembler.assemble(restingHeartRate: [], hrv: sdnn + ring, sleepHours: [], calendar: gateCalendar)
        #expect(result.hrvSource == "Ring-HRV")
        #expect(result.droppedForSourceChange == 20)
        #expect(result.nights.compactMap(\.hrv).allSatisfy { $0 == 30 })
        #expect(NightAssembler.originText(result).contains("Quelle gewechselt"))
    }

    @Test func sourceChangeMeansLearningNotAFalseAlarm() {
        let rhr = (1...28).map { NightValue(day: day(-$0), value: 56, source: "Apple Health") }
            + [NightValue(day: day(0), value: 66, source: "Ring")]
        let result = NightAssembler.assemble(restingHeartRate: rhr, hrv: [], sleepHours: [], calendar: gateCalendar)
        let now = gateCalendar.date(byAdding: .hour, value: 8, to: day(0)) ?? .now
        let input = InsightInput(profileID: UUID(), now: now, nights: result.nights, origin: NightAssembler.originText(result),
                                 hrvMethod: "Ring-HRV", newestSample: gateCalendar.date(byAdding: .hour, value: 6, to: day(0)),
                                 lastSync: now)
        #expect(InsightEngine.build(input, calendar: gateCalendar).insightCase == .learning)
    }
}

@Suite("Training review")
struct TrainingReviewTests {
    private func facts(_ family: ActivationFamily, done: Int = 5, rates: [Double], sessions: Int = 0) -> TrainingSessionFacts {
        TrainingSessionFacts(family: family, plannedBlocks: 5, doneBlocks: done, minutes: 10, rpe: 6, heartRates: rates,
                             restingHeartRate: 56, comparableSessions: sessions)
    }

    @Test func highPulseDoesNotConfirmAnEffect() {
        let review = TrainingReviewer.review(facts(.cardio, rates: [150, 160, 165]))
        #expect(review.effectText.contains("noch nicht beurteilbar"))
        #expect(!review.effectText.localizedCaseInsensitiveContains("bestätigt"))
        #expect(!review.responseText.localizedCaseInsensitiveContains("wirkt"))
    }

    @Test func lowPulseNeverJudgesThePerson() {
        let review = TrainingReviewer.review(facts(.mobility, rates: [72, 75, 78]))
        #expect(review.execution == .complete)
        let all = [review.executionText, review.responseText, review.effectText].joined(separator: " ").lowercased()
        for word in ["faul", "zu wenig", "nicht genug", "versagt"] { #expect(!all.contains(word)) }
        #expect(review.responseText.contains("sagt nichts über die Qualität"))
    }

    @Test func executionComesFromBlocksNotFromPulse() {
        #expect(TrainingReviewer.review(facts(.push, done: 3, rates: [])).execution == .partial)
        #expect(TrainingReviewer.review(facts(.push, done: 0, rates: [170])).execution == .notStarted)
        #expect(TrainingReviewer.review(facts(.core, rates: [], sessions: 7)).effectText.contains("über die Wochen"))
    }
}

@Suite("Advertisement summary")
struct AdvertisementSummaryTests {
    @Test func companyIdentifierIsLittleEndian() {
        #expect(AdvertisementSummary.companyIdentifier([0x4C, 0x00, 0x01]) == "004C")
        #expect(AdvertisementSummary.companyIdentifier([0x01]) == nil)
        #expect(AdvertisementSummary.companyIdentifier(nil) == nil)
    }

    @Test func summaryNamesServicesAndManufacturer() {
        let text = AdvertisementSummary.describe(name: "R03_1A2B", serviceUUIDs: ["FEE7", "180D"], manufacturerData: [0x34, 0x12, 0xAA])
        #expect(text == "Werbung R03_1A2B · Dienste: 180D, FEE7 · Hersteller-ID: 1234 · Herstellerdaten: 34 12 AA")
        #expect(AdvertisementSummary.describe(name: "R03", serviceUUIDs: [], manufacturerData: nil).contains("Dienste: keine"))
    }
}
