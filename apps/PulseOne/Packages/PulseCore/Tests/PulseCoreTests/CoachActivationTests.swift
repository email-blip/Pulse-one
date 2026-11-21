import Foundation
import Testing
@testable import PulseCore

// Verzahnung Coach ↔ Begleiter activation: shared hourly steps, unknown hours, activation load, snacks.

private let caCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}()

private func caDate(_ hour: Int, _ minute: Int = 0, day: Int = 21) -> Date {
    caCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
}

private func caSteps(_ value: Double, hour: Int, device: String, source: DataSourceKind,
                     quality: SampleQuality = .valid) -> HealthSample {
    let start = caDate(hour, 10)
    return HealthSample(profileID: nil, kind: .steps, value: value, unit: .count, start: start,
                        end: start.addingTimeInterval(600), timeZoneIdentifier: "UTC", source: source,
                        deviceID: device, originalSampleID: UUID().uuidString, importedAt: caDate(12), quality: quality,
                        method: .deviceHistory)
}

private func caResult(_ slot: ActivationSlot, finishedAt: Date, feedback: ActivationFeedback? = .right) -> ActivationResult {
    let plan = ActivationPlan(slot: slot, dayStamp: "20261121", format: .circuit, readiness: .full, warmUp: [],
                              blocks: [], circuitRounds: 1, estimatedSeconds: 600, reason: "", summary: "")
    return ActivationResult(plan: plan, results: [], feedback: feedback, finishedAt: finishedAt)
}

@Suite("Coach and Begleiter – shared steps and activation")
struct CoachActivationTests {
    @Test func healthAndRingStepsAreNotAddedTwice() {
        let samples = [caSteps(600, hour: 8, device: "iphone", source: .appleHealth),
                       caSteps(500, hour: 8, device: "ring", source: .colmiRing),
                       caSteps(100, hour: 9, device: "ring", source: .colmiRing),
                       caSteps(9_999, hour: 9, device: "ring", source: .colmiRing, quality: .implausible)]
        let hourly = HourlySteps.perHour(samples, day: caDate(12), calendar: caCalendar)
        #expect(hourly == [8: 600, 9: 100])
        #expect(ActivityCheck.hourlySteps(samples, day: caDate(12), calendar: caCalendar) == hourly)
        #expect(HourlySteps.perHour(samples, day: caDate(12), until: caDate(8, 30), calendar: caCalendar) == [8: 600])
    }

    @Test func missingHoursAreUnknownNotInactive() {
        // 7–11 finished, data only for 7, 8, 9 (60 %): 10 and 11 are unknown, not quiet.
        let steps: [Int: Double] = [7: 1_000, 8: 100, 9: 1_000]
        #expect(DailyPlanner.inactiveHours(hourlySteps: steps, now: caDate(12), wakeHours: 7...21,
                                           calendar: caCalendar) == [8])
        // Under half of the finished hours with data: nothing is called inactive.
        let sparse: [Int: Double] = [7: 0, 8: 0]
        #expect(DailyPlanner.inactiveHours(hourlySteps: sparse, now: caDate(12), wakeHours: 7...21,
                                           calendar: caCalendar).isEmpty)
    }

    @Test func activationLoadFollowsFeedback() {
        #expect(ActivationLoad.load(minutes: 10, feedback: .right) == 30)
        #expect(ActivationLoad.load(minutes: 10, feedback: nil) == 30)
        #expect(ActivationLoad.load(minutes: 10, feedback: .tooHard) == 40)
        #expect(ActivationLoad.load(minutes: 10, feedback: .tooEasy) == 20)
    }

    @Test func activationCountsTowardsTheWeeklyLoad() {
        let review = EveningReview(day: caDate(0), completed: true, minutes: 30, rpe: 5)
        let extras = [DayValue(day: caDate(0), value: 30), DayValue(day: caDate(0, day: 20), value: 20),
                      DayValue(day: caDate(0, day: 10), value: 45)]
        let summary = TrainingLoad.summary([review], extraLoads: extras, endingOn: caDate(12), calendar: caCalendar)
        #expect(summary.weekLoad == 200)
        // Day 10 lies in the second week back: a week with only activation still counts as history.
        #expect(summary.fourWeekMean == 45)
        #expect(TrainingLoad.summary([review], endingOn: caDate(12), calendar: caCalendar).weekLoad == 150)
    }

    @Test func activationSessionsReplaceSnacks() {
        let prefs = CoachPreferences()
        var steps: [Int: Double] = [:]
        for hour in 7...11 { steps[hour] = 1_000 }
        steps[9] = 40
        steps[10] = 0
        let open = DailyPlanner.snacks(preferences: prefs, hourlySteps: steps, now: caDate(12), dayIndex: 0,
                                       calendar: caCalendar)
        #expect(open.count == 2)
        #expect(open.first?.reason?.contains("10 und 11 Uhr") == true)

        // A snack session finished at 11:05 answers the quiet hour 10 and replaces one snack.
        let done = [caResult(.snack, finishedAt: caDate(11, 5))]
        let after = DailyPlanner.snacks(preferences: prefs, hourlySteps: steps, activationDone: done, now: caDate(12),
                                        dayIndex: 0, calendar: caCalendar)
        #expect(after.count == 1)
        #expect(after.first?.reason?.contains("9 und 10 Uhr") == true)

        // The morning activation is not a snack.
        let morning = [caResult(.morning, finishedAt: caDate(7, 20))]
        #expect(DailyPlanner.snacks(preferences: prefs, hourlySteps: steps, activationDone: morning, now: caDate(12),
                                    dayIndex: 0, calendar: caCalendar).count == 2)
    }

    @Test func morningActivationFillsTheCoachActivationBlock() {
        let morning = caResult(.morning, finishedAt: caDate(7, 20))
        let plan = DailyPlanner.plan(now: caDate(12), program: nil, preferences: CoachPreferences(), signals: [],
                                     subjective: nil, feedback: .unchanged, hourlySteps: nil, revisions: [],
                                     activationDone: [morning], calendar: caCalendar)
        let block = plan.blocks.first { $0.kind == .activation }
        #expect(block?.detail.contains("Morgen-Aktivierung") == true)
        #expect(block?.exercises.isEmpty == true)
        #expect(block?.minutes == 10)

        // A session from yesterday does not count for today.
        let old = caResult(.morning, finishedAt: caDate(7, 20, day: 20))
        let today = DailyPlanner.plan(now: caDate(12), program: nil, preferences: CoachPreferences(), signals: [],
                                      subjective: nil, feedback: .unchanged, hourlySteps: nil, revisions: [],
                                      activationDone: [old], calendar: caCalendar)
        #expect(today.blocks.first { $0.kind == .activation }?.exercises.isEmpty == false)
    }
}
