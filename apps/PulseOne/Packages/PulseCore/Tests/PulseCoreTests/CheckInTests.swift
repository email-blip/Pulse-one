import Foundation
import Testing
@testable import PulseCore

// Aktiver Begleiter: automatic check-ins in the morning, at midday and in the evening.

private let checkInCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
    checkInCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
}

private func fact(_ kind: SampleKind, value: Double, median: Double, p25: Double, p75: Double, stat: String = "day_value") -> AnalysisFact {
    AnalysisFact(id: "F\(kind.rawValue)", kind: kind.rawValue, title: kind.rawValue, stat: stat, value: value, unit: "u",
                 period: "today", n: 1, coverage: 1,
                 baseline: FactBaseline(median: median, p25: p25, p75: p75, windowDays: 28, n: 28),
                 source: "ring", quality: "ok")
}

private func context(_ facts: [AnalysisFact]) -> HealthAnalysisContext {
    HealthAnalysisContext(analysisType: "daily", generatedAt: "2026-11-22T07:00:00+01:00",
                          period: AnalysisPeriod(start: "2026-11-22", end: "2026-11-22", timezone: "Europe/Berlin"),
                          comparisonPeriod: nil, profile: .empty, consentedCategories: [], facts: facts,
                          correlations: [], events: [], dataGaps: [])
}

@Suite("Check-in schedule")
struct CheckInScheduleTests {
    let schedule = CheckInSchedule.standard

    @Test func nothingIsDueBeforeTheMorning() {
        #expect(schedule.dueSlot(now: at(3, 30), wake: nil, lastRuns: [:], calendar: checkInCalendar) == nil)
        #expect(schedule.dueSlot(now: at(7, 0), wake: nil, lastRuns: [:], calendar: checkInCalendar) == nil)
    }

    @Test func wakeUpStartsTheMorningEarly() {
        #expect(schedule.dueSlot(now: at(6, 40), wake: at(6, 35), lastRuns: [:], calendar: checkInCalendar) == .morning)
        // A wake-up before 04:00 does not count.
        #expect(schedule.dueSlot(now: at(3, 40), wake: at(3, 30), lastRuns: [:], calendar: checkInCalendar) == nil)
    }

    @Test func eachSlotRunsOncePerDay() {
        let ranThisMorning: [CheckInSlot: Date] = [.morning: at(8, 5)]
        #expect(schedule.dueSlot(now: at(9, 0), wake: nil, lastRuns: ranThisMorning, calendar: checkInCalendar) == nil)
        let ranYesterday: [CheckInSlot: Date] = [.morning: at(8, 5, day: 21)]
        #expect(schedule.dueSlot(now: at(9, 0), wake: nil, lastRuns: ranYesterday, calendar: checkInCalendar) == .morning)
    }

    @Test func aMissedSlotIsSkipped() {
        // At 15:00 the morning was missed: the midday check is due, the morning is not repeated.
        #expect(schedule.dueSlot(now: at(15, 0), wake: nil, lastRuns: [:], calendar: checkInCalendar) == .midday)
        #expect(schedule.dueSlot(now: at(21, 0), wake: nil, lastRuns: [:], calendar: checkInCalendar) == .evening)
    }

    @Test func nextStartWalksThroughTheDayAndIntoTomorrow() {
        #expect(schedule.nextStart(after: at(9, 0), calendar: checkInCalendar) == at(12, 30))
        #expect(schedule.nextStart(after: at(13, 0), calendar: checkInCalendar) == at(20, 30))
        #expect(schedule.nextStart(after: at(22, 0), calendar: checkInCalendar) == at(8, 0, day: 23))
    }
}

@Suite("Check-in reading and texts")
struct CheckInMessageTests {
    @Test func onlyClearDeviationsCount() {
        let facts = [
            fact(.restingHeartRate, value: 61, median: 56, p25: 55, p75: 57),
            fact(.sleepDuration, value: 7.1, median: 7.0, p25: 6.6, p75: 7.4),
            fact(.steps, value: 900, median: 8000, p25: 6000, p75: 10000, stat: "so_far_today"),
        ]
        let deviations = CheckInReader.deviations(in: context(facts))
        #expect(deviations.map(\.kind) == [SampleKind.restingHeartRate.rawValue])
        #expect(deviations.first?.direction == .above)
    }

    @Test func twoStrainSignalsRaiseAWarning() {
        let facts = [
            fact(.restingHeartRate, value: 64, median: 56, p25: 55, p75: 57),
            fact(.ringHRV, value: 22, median: 40, p25: 36, p75: 44),
        ]
        let message = LocalCheckIn.compose(slot: .morning, context: context(facts), name: "Nox")
        #expect(message.urgency == .watch)
        #expect(message.markers.first?.symbol == .warning)
        #expect(message.markers.contains { $0.symbol == .below })
    }

    @Test func calmDayGivesAShortCalmText() {
        let message = LocalCheckIn.compose(slot: .evening, context: context([fact(.restingHeartRate, value: 56, median: 56, p25: 55, p75: 57)]),
                                           name: "Nox")
        #expect(message.urgency == .none)
        #expect(message.markers.isEmpty)
        #expect(!message.suggestion.isEmpty)
    }

    @Test func noValuesSaysSoHonestly() {
        let message = LocalCheckIn.compose(slot: .midday, context: context([]), name: "Nox")
        #expect(message.headline == "Noch keine Werte")
    }

    @Test func numbersUseGermanCommas() {
        #expect(LocalCheckIn.number(6.54) == "6,5")
        #expect(LocalCheckIn.number(61.4) == "61")
    }
}

@Suite("Check-in validation")
struct CheckInValidatorTests {
    @Test func decodesClaudesAnswerAndKeepsAtMostFourMarkers() throws {
        let markers = (0..<6).map { "{\"symbol\":\"insight\",\"metric\":\"\",\"text\":\"Satz \($0)\",\"evidence\":[\"F1\"]}" }
        let json = "{\"headline\":\"Solide Nacht\",\"text\":\"Ruhepuls 54, vier unter normal.\",\"suggestion\":\"\",\"urgency\":\"none\","
            + "\"markers\":[\(markers.joined(separator: ","))]}"
        let message = try CheckInValidator.validate(json: json, mode: .clinical)
        #expect(message.headline == "Solide Nacht")
        #expect(message.markers.count == 4)
        #expect(message.notificationBody == "Ruhepuls 54, vier unter normal.")
    }

    @Test func rejectsUnreadableAnswers() {
        #expect(throws: CheckInValidator.Failure.unreadable) {
            try CheckInValidator.validate(json: "kein json", mode: .clinical)
        }
    }

    @Test func schemaRequiresAllFields() {
        let required = CheckInPrompts.schemaV1["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(required) == ["headline", "text", "suggestion", "urgency", "markers"])
    }
}
