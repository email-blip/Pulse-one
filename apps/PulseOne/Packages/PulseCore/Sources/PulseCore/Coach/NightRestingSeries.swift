import Foundation

/// Night resting pulse per day for people without a daily resting heart rate (ring only, no Apple Health).
/// Same method as the Begleiter's night summary (lowest rolling 30-minute mean from 18:00 the day before
/// until 12:00, one source per night), so Coach and Begleiter judge the same number.
public enum NightRestingSeries {
    public static func daily(_ samples: [HealthSample], days: Int, now: Date, calendar: Calendar) -> [DayValue] {
        let heart = NightSamples(samples).heartRate
        guard !heart.isEmpty, days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [DayValue] = []
        for offset in stride(from: -(days - 1), through: 0, by: 1) {
            let day = NightMath.day(today, offset: offset, calendar: calendar)
            let start = NightMath.windowStart(for: day, calendar: calendar)
            let end = min(NightMath.historyEnd(for: day, calendar: calendar), now)
            guard end > start else { continue }
            let night = NightMath.oneSource(NightMath.within(heart, from: start, to: end))
            if let level = NightMath.restingLevel(night) {
                result.append(DayValue(day: day, value: level))
            }
        }
        return result
    }

    /// Earliest moment `daily(…, days:)` reads, for fetching samples.
    public static func readStart(days: Int, now: Date, calendar: Calendar) -> Date {
        let first = NightMath.day(calendar.startOfDay(for: now), offset: -(max(days, 1) - 1), calendar: calendar)
        return NightMath.windowStart(for: first, calendar: calendar)
    }
}
