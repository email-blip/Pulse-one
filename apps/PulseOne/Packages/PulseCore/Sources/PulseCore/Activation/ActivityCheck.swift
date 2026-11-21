import Foundation

// Begleiter "Aktivierung": how much movement today had so far, from hourly steps, and when to check.
// An hour without any step sample is unknown, never 0 steps: no reminder is built on missing data.

public enum ActivityCheck {
    /// Steps per hour below this count make a finished waking hour "quiet" (same rule as the Coach).
    public static let quietStepsPerHour: Double = 250

    /// Steps per start hour of `day` (shared rule `HourlySteps`: per source, largest source per hour).
    /// Hours without a sample are absent (unknown).
    public static func hourlySteps(_ samples: [HealthSample], day: Date, calendar: Calendar) -> [Int: Double] {
        HourlySteps.perHour(samples, day: day, calendar: calendar)
    }

    /// `.unknown` without data or when fewer than half of the finished waking hours have data;
    /// `.quiet(hours:)` for ≥ 2 consecutive quiet hours with data back from the last finished hour
    /// (an hour without data ends the streak); `.active` otherwise.
    public static func status(hourlySteps: [Int: Double]?, now: Date, wakeHours: ClosedRange<Int>,
                              calendar: Calendar) -> ActivityStatus {
        guard let hourlySteps, !hourlySteps.isEmpty else { return .unknown }
        let currentHour: Int = calendar.component(.hour, from: now)
        let finished: [Int] = wakeHours.filter { $0 < currentHour }
        if finished.isEmpty { return .unknown }
        if !HourlySteps.hasEnoughCoverage(hourlySteps, finishedHours: finished) { return .unknown }
        var quiet: Int = 0
        for hour in finished.sorted(by: >) {
            guard let steps = hourlySteps[hour] else { break }
            if steps >= quietStepsPerHour { break }
            quiet += 1
        }
        return quiet >= 2 ? .quiet(hours: quiet) : .active
    }

    /// Quiet for ≥ 2 hours and no session finished in the last 60 minutes.
    public static func shouldSuggestSnack(_ status: ActivityStatus, doneToday: [ActivationResult], now: Date) -> Bool {
        guard case .quiet(let hours) = status, hours >= 2 else { return false }
        for result in doneToday {
            let since: TimeInterval = now.timeIntervalSince(result.finishedAt)
            if since < 3_600 { return false }
        }
        return true
    }

    /// Calm German hint for a quiet day, nil otherwise.
    public static func hint(_ status: ActivityStatus) -> String? {
        guard case .quiet(let hours) = status, hours >= 2 else { return nil }
        return "Seit \(hours) Stunden wenig Bewegung. Zeit für einen kurzen Bewegungs-Snack? Das bringt den Kreislauf in Schwung."
    }

    /// Up to two activity checkpoints for today (aimed at about 10:30 and 15:30), shifted later in 30-minute steps
    /// until they are: inside 9:00–20:00, at least 1 h after waking, not within 2 h after an enabled midday or evening
    /// session, at least 90 min apart, and in the future. Sorted ascending.
    public static func checkpointTimes(wake: Date, settings: ActivationSettings, now: Date,
                                       calendar: Calendar) -> [Date] {
        guard let dayStart = minuteOfDayDate(0, base: now, calendar: calendar) else { return [] }
        let windowStart: Int = 9 * 60
        let windowEnd: Int = 20 * 60
        let wakeMinute: Int = minutesBetween(dayStart, wake)
        let nowMinute: Int = minutesBetween(dayStart, now)
        var sessions: [Int] = []
        if settings.middayEnabled { sessions.append(settings.middayHour * 60 + settings.middayMinute) }
        if settings.eveningEnabled { sessions.append(settings.eveningHour * 60 + settings.eveningMinute) }

        var chosen: [Int] = []
        for aim in [10 * 60 + 30, 15 * 60 + 30] {
            var candidate: Int = max(aim, windowStart)
            while candidate <= windowEnd {
                if isValidCheckpoint(candidate, wakeMinute: wakeMinute, nowMinute: nowMinute, sessions: sessions,
                                     chosen: chosen) {
                    chosen.append(candidate)
                    break
                }
                candidate += 30
            }
        }
        var dates: [Date] = []
        for minute in chosen.sorted() {
            if let date = minuteOfDayDate(minute, base: now, calendar: calendar) { dates.append(date) }
        }
        return dates
    }

    // MARK: - Internals

    static func isValidCheckpoint(_ minute: Int, wakeMinute: Int, nowMinute: Int, sessions: [Int],
                                  chosen: [Int]) -> Bool {
        if minute < wakeMinute + 60 { return false }
        if minute <= nowMinute { return false }
        for session in sessions where minute >= session && minute <= session + 120 { return false }
        for other in chosen where abs(other - minute) < 90 { return false }
        return true
    }

    static func minutesBetween(_ start: Date, _ end: Date) -> Int {
        let seconds: Double = end.timeIntervalSince(start)
        return Int((seconds / 60.0).rounded(.down))
    }

    /// The date at `minute` minutes after the start of the day of `base`.
    static func minuteOfDayDate(_ minute: Int, base: Date, calendar: Calendar) -> Date? {
        let start: Date = calendar.startOfDay(for: base)
        let hour: Int = minute / 60
        let rest: Int = minute % 60
        return calendar.date(bySettingHour: hour, minute: rest, second: 0, of: start)
    }
}
