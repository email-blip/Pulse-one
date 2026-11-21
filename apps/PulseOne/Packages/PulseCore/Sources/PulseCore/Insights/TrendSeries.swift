import Foundation

/// Periods of the HEALTH chart.
public enum TrendRange: String, CaseIterable, Sendable, Identifiable {
    case day, week, month, quarter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        case .quarter: "3 Monate"
        }
    }

    /// Start of the visible period; it always ends now.
    public func start(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let days = switch self {
        case .day: 0
        case .week: 6
        case .month: 29
        case .quarter: 89
        }
        return calendar.date(byAdding: .day, value: -days, to: today) ?? today
    }
}

/// One point of a chart: an hour (day view) or a day (other views).
public struct TrendPoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let value: Double
    public let minimum: Double
    public let maximum: Double
    public let sampleCount: Int
    public var id: Date { date }
}

public enum TrendSeries {
    /// Chart points of one kind. Day view: hourly points for single readings (mean) and counters (sum of one
    /// source per hour); interval and derived kinds have no hourly meaning and show their day value.
    /// Missing hours or days stay missing: nothing is interpolated.
    public static func points(_ samples: [HealthSample], kind: SampleKind, range: TrendRange, now: Date,
                              calendar: Calendar, policy: SourcePolicy = SourcePolicy()) -> [TrendPoint] {
        let start = range.start(now: now, calendar: calendar)
        let relevant = samples.filter { $0.kind == kind && $0.start >= start && $0.start <= now && $0.quality.usableForAnalysis }
        if range == .day, kind.aggregation == .point || kind.aggregation == .cumulative {
            return hourly(relevant, kind: kind, calendar: calendar, policy: policy)
        }
        return DailySeries.build(relevant, kind: kind, calendar: calendar, policy: policy).map {
            TrendPoint(date: $0.day, value: $0.value, minimum: $0.minimum, maximum: $0.maximum, sampleCount: $0.sampleCount)
        }
    }

    static func hourly(_ samples: [HealthSample], kind: SampleKind, calendar: Calendar, policy: SourcePolicy) -> [TrendPoint] {
        let byHour = Dictionary(grouping: samples) { calendar.dateInterval(of: .hour, for: $0.start)?.start ?? $0.start }
        return byHour.keys.sorted().compactMap { hour in
            let group = byHour[hour] ?? []
            switch kind.aggregation {
            case .point:
                let points = DataSourceResolver.resolvePoints(group, policy: policy)
                guard !points.isEmpty else { return nil }
                let values = points.map(\.value)
                return TrendPoint(date: hour, value: values.reduce(0, +) / Double(values.count),
                                  minimum: values.min() ?? 0, maximum: values.max() ?? 0, sampleCount: values.count)
            default:
                guard let total = DataSourceResolver.resolveTotal(group, policy: policy) else { return nil }
                return TrendPoint(date: hour, value: total.total, minimum: total.total, maximum: total.total,
                                  sampleCount: total.sampleIDs.count)
            }
        }
    }

    /// Plain statistics of the visible points (for the line under the chart).
    public static func summary(_ points: [TrendPoint]) -> (median: Double, minimum: Double, maximum: Double)? {
        let values = points.map(\.value).sorted()
        guard let low = values.first, let high = values.last else { return nil }
        return (PersonalBaseline.percentile(values, 0.5), low, high)
    }
}
