import Foundation
import PulseCore

/// One of TODAY's three scores.
struct ScoreEntry: Identifiable, Equatable {
    let kind: ScoreKind
    let result: ScoreResult
    var id: ScoreKind { kind }
}

/// Builds the three day scores (sleep, recovery, activity) from stored samples. Same sources as Coach and
/// TODAY: one HRV method only (ring before Apple SDNN), resting pulse from the source or the ring's night.
@MainActor
struct ScoreModel {
    let reader: SampleReader
    let profileID: UUID?
    let now: Date
    var calendar: Calendar = .current

    /// Days read so every score of the last 30 days has its 28-day window.
    static let readDays = 62

    struct Inputs {
        let nights: [NightSleep]
        let resting: [DayValue]
        let hrv: [DayValue]
        let steps: [DayValue]
        let hourlyToday: [Int: Double]?
    }

    /// Nights with sleep data in the read window: gates the lab tools and Claude reports.
    func nightsWithData() -> Int {
        reader.daily(.sleepDuration, days: Self.readDays, profileID: profileID, calendar: calendar, now: now).count
    }

    func inputs() -> Inputs {
        func days(_ kind: SampleKind) -> [DailyValue] {
            reader.daily(kind, days: Self.readDays, profileID: profileID, calendar: calendar, now: now)
        }
        func plain(_ values: [DailyValue]) -> [DayValue] { values.map { DayValue(day: $0.day, value: $0.value) } }

        let sleepSamples = reader.samples([.sleepDuration], since: calendar.date(byAdding: .day, value: -Self.readDays, to: now) ?? now,
                                          profileID: profileID)
        let byNight = Dictionary(grouping: sleepSamples) { DailySeries.dayKey(for: $0, calendar: calendar) }
        let nights: [NightSleep] = days(.sleepDuration).compactMap { value in
            let samples = byNight[value.day] ?? []
            guard let start = samples.map(\.start).min() else { return nil }
            var stages: [SleepStage: Int] = [:]
            for sample in samples where sample.source == .colmiRing {
                stages.merge(NightSleep.stages(fromSummary: sample.rawDataReference)) { $0 + $1 }
            }
            return NightSleep(day: value.day, asleepSeconds: value.value, start: start, stages: stages)
        }

        let ringHRV = plain(days(.ringHRV))
        let hrv = ringHRV.isEmpty ? plain(days(.heartRateVariability)) : ringHRV
        let dailyResting = plain(days(.restingHeartRate))
        let resting = dailyResting.isEmpty
            ? NightRestingSeries.daily(reader.samples([.heartRate], since: NightRestingSeries.readStart(days: Self.readDays, now: now, calendar: calendar),
                                                      profileID: profileID),
                                       days: Self.readDays, now: now, calendar: calendar)
            : dailyResting

        let todaySteps = reader.samples([.steps], since: calendar.startOfDay(for: now), profileID: profileID)
        let hourly = HourlySteps.perHour(todaySteps, day: now, until: now, calendar: calendar)
        return Inputs(nights: nights, resting: resting, hrv: hrv, steps: plain(days(.steps)),
                      hourlyToday: hourly.isEmpty ? nil : hourly)
    }

    func result(_ kind: ScoreKind, on day: Date, inputs: Inputs) -> ScoreResult {
        switch kind {
        case .sleep:
            return DailyScores.sleep(on: day, nights: inputs.nights, calendar: calendar)
        case .recovery:
            return DailyScores.recovery(on: day, restingHeartRate: inputs.resting, hrv: inputs.hrv, nights: inputs.nights,
                                        steps: inputs.steps, calendar: calendar)
        case .activity:
            let isToday = calendar.isDate(day, inSameDayAs: now)
            let finished = isToday ? Array(0..<calendar.component(.hour, from: now)) : Array(0..<24)
            return DailyScores.activity(on: day, steps: inputs.steps, hourlySteps: isToday ? inputs.hourlyToday : nil,
                                        finishedHours: finished, calendar: calendar)
        }
    }

    /// Today's three scores, in display order.
    func today() -> [ScoreEntry] {
        let inputs = inputs()
        return ScoreKind.allCases.map { ScoreEntry(kind: $0, result: result($0, on: now, inputs: inputs)) }
    }

    /// The score of each of the last `days` days (oldest first); days without a number are left out.
    func history(_ kind: ScoreKind, days: Int = 30) -> [DayScore] {
        let inputs = inputs()
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).flatMap { result(kind, on: $0, inputs: inputs).score }
        }
    }
}
