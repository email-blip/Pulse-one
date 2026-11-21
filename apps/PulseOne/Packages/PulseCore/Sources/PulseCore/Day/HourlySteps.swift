import Foundation

// One rule for "steps per hour today", shared by Coach (snacks) and Begleiter (activity check).
// Each source (deviceID) is summed per hour; per hour the largest source counts, so Apple Health and
// ring steps for the same walk are never added twice. Implausible samples are skipped.
// An hour without any sample is absent: unknown, never 0 steps.

public enum HourlySteps {
    /// Steps per start hour of `day`, only samples that started at or before `until` (nil = whole day).
    public static func perHour(_ samples: [HealthSample], day: Date, until: Date? = nil,
                               calendar: Calendar) -> [Int: Double] {
        var perSource: [String: [Int: Double]] = [:]
        for sample in samples {
            if sample.kind != .steps { continue }
            if sample.quality == .implausible { continue }
            if !calendar.isDate(sample.start, inSameDayAs: day) { continue }
            if let until, sample.start > until { continue }
            let hour: Int = calendar.component(.hour, from: sample.start)
            perSource[sample.deviceID, default: [:]][hour, default: 0] += sample.value
        }
        var result: [Int: Double] = [:]
        for hours in perSource.values {
            for (hour, value) in hours { result[hour] = max(result[hour] ?? 0, value) }
        }
        return result
    }

    /// True when at least half of the finished waking hours have step data (same 50 % rule everywhere).
    public static func hasEnoughCoverage(_ hourly: [Int: Double], finishedHours: [Int]) -> Bool {
        guard !finishedHours.isEmpty else { return false }
        let withData: Int = finishedHours.filter { hourly[$0] != nil }.count
        return withData * 2 >= finishedHours.count
    }
}
