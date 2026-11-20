import Foundation

/// One calendar day of one kind, built from stored samples. The basis for trends and personal baselines
/// later; it describes values only and draws no conclusions (Review 3.2 §6).
public struct DailyValue: Equatable, Sendable {
    /// Start of the day in the calendar's time zone.
    public let day: Date
    public let kind: SampleKind
    public let aggregation: SampleAggregation
    /// Point: mean. Interval: merged duration. Cumulative: hourly-merged total. Derived: latest value.
    public let value: Double
    public let minimum: Double
    public let maximum: Double
    public let sampleCount: Int
    /// Origins the value was taken from.
    public let origins: [SampleOrigin]
    /// The stored samples behind the value, so a computed number can always be traced back.
    public let sampleIDs: [UUID]
    /// Hours of the day that had usable data (0–24). Low coverage means an incomplete day.
    public let coveredHours: Int
    /// Reservations carried over from `ResolvedTotal` (review R2-2/R3): a display or export must show
    /// them; a Health day total is never presented as Apple's exact figure.
    public let caveats: [TotalCaveat]

    public var isProvisional: Bool { !caveats.isEmpty }
}

public enum DailySeries {
    /// Groups samples by the day their `start` falls on. An interval that crosses midnight counts for the
    /// day it began. Only `valid` and `plausible` samples are used; days without data are absent.
    public static func build(_ samples: [HealthSample], kind: SampleKind, calendar: Calendar,
                             policy: SourcePolicy = SourcePolicy()) -> [DailyValue] {
        let relevant = samples.filter { $0.kind == kind && $0.quality.usableForAnalysis }
        let byDay = Dictionary(grouping: relevant) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted().compactMap { day in
            value(for: byDay[day] ?? [], day: day, kind: kind, calendar: calendar, policy: policy)
        }
    }

    static func value(for group: [HealthSample], day: Date, kind: SampleKind, calendar: Calendar,
                      policy: SourcePolicy) -> DailyValue? {
        func hours(_ s: [HealthSample]) -> Int { Set(s.map { calendar.component(.hour, from: $0.start) }).count }
        func make(_ value: Double, _ used: [HealthSample], caveats: [TotalCaveat] = []) -> DailyValue {
            let values = used.map(\.value)
            return DailyValue(day: day, kind: kind, aggregation: kind.aggregation, value: value,
                              minimum: values.min() ?? 0, maximum: values.max() ?? 0, sampleCount: used.count,
                              origins: Set(used.map(\.origin)).sorted(), sampleIDs: used.map(\.id),
                              coveredHours: hours(used), caveats: caveats)
        }
        switch kind.aggregation {
        case .point:
            let points = DataSourceResolver.resolvePoints(group, policy: policy)
            guard !points.isEmpty else { return nil }
            return make(points.reduce(0) { $0 + $1.value } / Double(points.count), points)
        case .cumulative:
            guard let total = DataSourceResolver.resolveTotal(group, policy: policy) else { return nil }
            let ids = Set(total.sampleIDs)
            return make(total.total, group.filter { ids.contains($0.id) }, caveats: total.caveats)
        case .interval:
            // One origin for the whole day; overlapping spans of that origin are merged, not added.
            guard let best = policy.choose(kind: kind, among: Set(group.map(\.origin)))?.origin else { return nil }
            let used = group.filter { $0.origin == best }
            return make(mergedDuration(used), used)
        case .derived, .vendorScore:
            // Already computed by the source: take the latest value of one origin, never mix vendors.
            guard let best = policy.choose(kind: kind, among: Set(group.map(\.origin)))?.origin,
                  let latest = group.filter({ $0.origin == best }).max(by: { $0.start < $1.start }) else { return nil }
            return make(latest.value, [latest])
        }
    }

    /// Length of the union of all spans, in seconds.
    public static func mergedDuration(_ samples: [HealthSample]) -> Double {
        let spans = samples.map { ($0.start, max($0.end, $0.start)) }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for span in spans {
            if let c = current, span.0 <= c.1 {
                current = (c.0, max(c.1, span.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = span
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }
}
