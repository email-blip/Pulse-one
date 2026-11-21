import Foundation

// Companion (Begleiter) T1: when did the person wake up?
// Order: confirmed tap > heart rate rise with steps after 04:00 > end of the sleep record > unknown.

public enum WakeDetector {
    /// Local hour before which a heart rate rise is not taken as waking up (night toilet visits etc.).
    public static let earliestHour = 4
    /// Heart rate must be at least this factor above the night resting level …
    public static let riseFactor = 1.12
    /// … for at least this long …
    public static let sustainedRise: TimeInterval = 10 * 60
    /// … with steps within this distance of the start of the rise.
    public static let stepDistance: TimeInterval = 20 * 60

    /// - Parameters:
    ///   - heartRate: heart rate samples of the night window (other kinds are ignored).
    ///   - steps: step samples of the night window.
    ///   - calendar: decides the local 04:00; defaults to the current calendar.
    public static func detect(heartRate: [HealthSample], steps: [HealthSample], sleepEnd: Date?,
                              confirmed: Date?, now: Date, calendar: Calendar = Calendar.current) -> WakeEstimate {
        if let confirmed {
            return WakeEstimate(time: confirmed, method: .confirmed, confidence: 1)
        }
        if let rise = heartRateRise(heartRate: heartRate, steps: steps, now: now, calendar: calendar) {
            return WakeEstimate(time: rise, method: .heartRateAndSteps, confidence: 0.6)
        }
        if let sleepEnd {
            return WakeEstimate(time: sleepEnd, method: .sleepRecordEnd, confidence: 0.4)
        }
        return WakeEstimate(time: nil, method: .unknown, confidence: 0)
    }

    /// First start of a sustained rise above the night level after 04:00 that has steps nearby.
    static func heartRateRise(heartRate: [HealthSample], steps: [HealthSample], now: Date, calendar: Calendar) -> Date? {
        let heart = heartRate
            .filter { $0.kind == .heartRate && $0.quality.usableForAnalysis && $0.start <= now }
            .sorted { $0.start < $1.start }
        guard let resting = NightMath.restingLevel(heart),
              let earliest = calendar.date(bySettingHour: earliestHour, minute: 0, second: 0, of: calendar.startOfDay(for: now))
        else { return nil }
        let threshold = resting * riseFactor
        let walking = steps.filter { $0.kind == .steps && $0.value > 0 && $0.quality.usableForAnalysis }
        var runStart: Date?
        for sample in heart where sample.start >= earliest {
            guard sample.value >= threshold else {
                runStart = nil
                continue
            }
            let begin = runStart ?? sample.start
            runStart = begin
            guard sample.start.timeIntervalSince(begin) >= sustainedRise else { continue }
            let low = begin.addingTimeInterval(-stepDistance)
            let high = begin.addingTimeInterval(stepDistance)
            if walking.contains(where: { $0.end >= low && $0.start <= high }) { return begin }
        }
        return nil
    }
}
