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
    /// day it began. Sleep is the exception: it belongs to the night ending on that day (sleep starting from
    /// 18:00 the evening before), so a night is never split across two days. Only `valid` and `plausible`
    /// samples are used; days without data are absent.
    public static func build(_ samples: [HealthSample], kind: SampleKind, calendar: Calendar,
                             policy: SourcePolicy = SourcePolicy()) -> [DailyValue] {
        let relevant = samples.filter { $0.kind == kind && $0.quality.usableForAnalysis }
        let byDay = Dictionary(grouping: relevant) { dayKey(for: $0, calendar: calendar) }
        return byDay.keys.sorted().compactMap { day in
            value(for: byDay[day] ?? [], day: day, kind: kind, calendar: calendar, policy: policy)
        }
    }

    /// Seconds before midnight from which sleep already counts for the next day (18:00).
    static let sleepDayShift: TimeInterval = 6 * 3_600

    /// The day a sample counts for; see `build`.
    public static func dayKey(for sample: HealthSample, calendar: Calendar) -> Date {
        if sample.kind == .sleepDuration {
            return calendar.startOfDay(for: sample.start.addingTimeInterval(sleepDayShift))
        }
        return calendar.startOfDay(for: sample.start)
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
            return make(intervalTotal(used), used)
        case .derived, .vendorScore:
            // Already computed by the source: take the latest value of one origin, never mix vendors.
            guard let best = policy.choose(kind: kind, among: Set(group.map(\.origin)))?.origin,
                  let latest = group.filter({ $0.origin == best }).max(by: { $0.start < $1.start }) else { return nil }
            return make(latest.value, [latest])
        }
    }

    /// Duration of overlapping spans counted once, but never more than the samples themselves report:
    /// a ring sleep session spans the whole night while its value is only the asleep time, a workout's
    /// value excludes pauses. Samples with the same start are one record seen twice; the larger value counts.
    public static func intervalTotal(_ samples: [HealthSample]) -> Double {
        var byStart: [Date: HealthSample] = [:]
        for s in samples {
            if let other = byStart[s.start], other.value >= s.value { continue }
            byStart[s.start] = s
        }
        let sorted = byStart.values.sorted { $0.start < $1.start }
        var total: Double = 0
        var cluster: (start: Date, end: Date, reported: Double)?
        func close() {
            guard let c = cluster else { return }
            total += min(c.end.timeIntervalSince(c.start), c.reported)
        }
        for s in sorted {
            let end = max(s.end, s.start)
            let reported = max(0, min(s.value, end.timeIntervalSince(s.start)))
            if let c = cluster, s.start <= c.end {
                cluster = (c.start, max(c.end, end), c.reported + reported)
            } else {
                close()
                cluster = (s.start, end, reported)
            }
        }
        close()
        return total
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
