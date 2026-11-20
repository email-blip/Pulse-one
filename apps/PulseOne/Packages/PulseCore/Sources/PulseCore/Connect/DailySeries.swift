import Foundation

/// One calendar day of one kind, built from stored samples. The basis for trends and personal baselines
/// later (Directive 3.1 "Intelligence"); it describes values only and draws no conclusions.
public struct DailyValue: Equatable, Sendable {
    /// Start of the day in the calendar's time zone.
    public let day: Date
    public let kind: SampleKind
    /// Total for cumulative kinds, mean for point kinds.
    public let value: Double
    public let minimum: Double
    public let maximum: Double
    public let sampleCount: Int
    /// The origins the value was taken from. One for cumulative kinds; point kinds may switch per minute.
    public let origins: [SampleOrigin]
}

public enum DailySeries {
    /// Groups samples by the day their `start` falls on. A sleep interval that crosses midnight counts
    /// for the day it began. Implausible samples and other kinds are ignored; days without data are absent.
    public static func build(_ samples: [HealthSample], kind: SampleKind, calendar: Calendar,
                             priority: [DataSourceKind] = DataSourceResolver.defaultPriority,
                             devicePriority: [String] = []) -> [DailyValue] {
        let relevant = samples.filter { $0.kind == kind }
        let byDay = Dictionary(grouping: relevant) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted().compactMap { day -> DailyValue? in
            let group = byDay[day] ?? []
            if kind.isCumulative {
                guard let total = DataSourceResolver.resolveTotal(group, priority: priority,
                                                                  devicePriority: devicePriority) else { return nil }
                let values = group.filter { $0.origin == total.origin && $0.quality == .plausible }.map(\.value)
                return DailyValue(day: day, kind: kind, value: total.total, minimum: values.min() ?? 0,
                                  maximum: values.max() ?? 0, sampleCount: total.sampleCount, origins: [total.origin])
            }
            let points = DataSourceResolver.resolvePoints(group, priority: priority, devicePriority: devicePriority)
            let values = points.map(\.value)
            guard let low = values.min(), let high = values.max() else { return nil }
            return DailyValue(day: day, kind: kind, value: values.reduce(0, +) / Double(values.count), minimum: low,
                              maximum: high, sampleCount: values.count, origins: Set(points.map(\.origin)).sorted())
        }
    }
}
