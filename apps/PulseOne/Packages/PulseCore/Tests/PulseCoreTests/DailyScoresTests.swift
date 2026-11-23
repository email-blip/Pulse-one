import Foundation
import Testing
@testable import PulseCore

@Suite("Day scores")
struct DailyScoresTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))! }

    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }

    func night(_ offset: Int, hours: Double, bed: Int = 23, stages: [SleepStage: Int] = [:]) -> NightSleep {
        let start = calendar.date(bySettingHour: bed, minute: 0, second: 0, of: day(offset + 1))!
        return NightSleep(day: day(offset), asleepSeconds: hours * 3_600, start: start, stages: stages)
    }

    @Test func stageSummaryIsRead() {
        let stages = NightSleep.stages(fromSummary: "tief 85 min · leicht 200 min · REM 70 min · wach 20 min")
        #expect(stages == [.deep: 85, .light: 200, .rem: 70, .awake: 20])
        #expect(NightSleep.stages(fromSummary: nil).isEmpty)
    }

    @Test func sleepScoreFromDurationAndStages() throws {
        let short = DailyScores.sleep(on: today, nights: [night(0, hours: 5)], calendar: calendar)
        #expect(short.score?.value == 45)
        let good = night(0, hours: 8, stages: [.deep: 96, .light: 264, .rem: 120, .awake: 8])
        let score = try #require(DailyScores.sleep(on: today, nights: [good], calendar: calendar).score)
        #expect(score.value >= 95)
        #expect(score.components.map(\.title) == ["Dauer", "Tiefschlaf", "REM-Schlaf", "Ruhe"])
        #expect(score.note != nil)
        #expect(DailyScores.sleep(on: today, nights: [], calendar: calendar) == .noData)
    }

    @Test func irregularBedTimeLowersSleep() throws {
        let usual = (1...7).map { night($0, hours: 8) }
        let regular = try #require(DailyScores.sleep(on: today, nights: usual + [night(0, hours: 8)], calendar: calendar).score)
        let late = try #require(DailyScores.sleep(on: today, nights: usual + [night(0, hours: 8, bed: 2)], calendar: calendar).score)
        #expect(regular.components.last?.title == "Regelmäßigkeit")
        #expect(late.value < regular.value)
        #expect(late.components.last?.detail == "180 min später als üblich")
    }

    @Test func recoveryWorksFromTheFirstDay() throws {
        // Only today: rated against typical values, no "still learning".
        let first = try #require(DailyScores.recovery(on: today, restingHeartRate: [DayValue(day: today, value: 60)], hrv: [],
                                                      nights: [], steps: [], calendar: calendar).score)
        #expect(first.value == 75)
        #expect(first.components.first?.detail == "wie üblich (60 bpm)")
        // Nine own days at 55: the band has moved most of the way toward 55.
        let resting = (0..<10).map { DayValue(day: day($0), value: 55) }
        let blended = try #require(DailyScores.recovery(on: today, restingHeartRate: resting, hrv: [], nights: [], steps: [],
                                                        calendar: calendar).score)
        // Band median 9/14 × 55 + 5/14 × 60 ≈ 56.8; today 55 lies a little below it.
        #expect(blended.value == 85)
        #expect(blended.components.first?.detail == "2 bpm unter deinem bisherigen Mittel (57 bpm)")
        #expect(DailyScores.recovery(on: today, restingHeartRate: [], hrv: [], nights: [], steps: [], calendar: calendar) == .noData)
    }

    @Test func recoveryFollowsRestingPulseAndHRV() throws {
        func values(_ base: Double, today value: Double) -> [DayValue] {
            (1...28).map { DayValue(day: day($0), value: base + Double($0 % 3) - 1) } + [DayValue(day: today, value: value)]
        }
        let usual = try #require(DailyScores.recovery(on: today, restingHeartRate: values(55, today: 55), hrv: values(45, today: 45),
                                                     nights: [], steps: [], calendar: calendar).score)
        let strained = try #require(DailyScores.recovery(on: today, restingHeartRate: values(55, today: 61), hrv: values(45, today: 36),
                                                        nights: [], steps: [], calendar: calendar).score)
        #expect(usual.value == 75)
        #expect(strained.value < 40)
        #expect(strained.components.first?.detail == "6 bpm über deinem Mittel (55 bpm)")
    }

    @Test func activityAgainstGoal() throws {
        let steps = (1...7).map { DayValue(day: day($0), value: 8_000) } + [DayValue(day: today, value: 4_000)]
        let hourly: [Int: Double] = Dictionary(uniqueKeysWithValues: (8..<14).map { ($0, $0 < 11 ? 900.0 : 100.0) })
        let score = try #require(DailyScores.activity(on: today, steps: steps, hourlySteps: hourly, finishedHours: Array(0..<14),
                                                     calendar: calendar).score)
        #expect(score.components.map(\.score) == [50, 70, 100])
        #expect(score.value == 68)
        #expect(score.components[1].detail == "3 Stunden fast ohne Schritte")
    }

    @Test func wordsAreNoTrafficLight() {
        #expect(DayScore.word(for: 90) == "sehr gut")
        #expect(DayScore.word(for: 72) == "gut")
        #expect(DayScore.word(for: 61) == "mittel")
        #expect(DayScore.word(for: 30) == "niedrig")
    }
}
