import Foundation

// Queries behind the Verlauf tracks (team 01, M1). Pure functions over `MeasurementPoint`s and
// `SleepSegment`s: the app fetches the window from the store, these decide what is drawn.
// Rules (contract §TimelineContracts): every track uses the same absolute window; up to two days
// span the original points are returned; above that buckets with min/max/mean (marked as aggregated).
// Gaps stay gaps: an empty bucket is left out, nothing is interpolated or invented.

/// One bucket of an aggregated track.
public struct TimelineBucket: Equatable, Sendable {
    public let kind: SampleKind
    public let interval: DateInterval
    public let minimum: Double
    public let maximum: Double
    public let mean: Double
    /// Sum of the values; meaningful for counters such as steps.
    public let sum: Double
    public let count: Int

    /// The value to draw: the sum for counters (steps, energy), the mean otherwise.
    public var representative: Double { kind.aggregation == .cumulative ? sum : mean }

    public init(kind: SampleKind, interval: DateInterval, minimum: Double, maximum: Double, mean: Double, sum: Double, count: Int) {
        self.kind = kind
        self.interval = interval
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
        self.sum = sum
        self.count = count
    }
}

public enum TimelineResolution: Equatable, Sendable {
    case original
    case hourly
    case daily
}

/// What one track shows inside the window, per sample kind (HRV keeps ring HRV and SDNN apart).
public struct TimelineSeries: Equatable, Sendable {
    public let kind: SampleKind
    public let resolution: TimelineResolution
    /// Filled when `resolution == .original`, oldest first.
    public let points: [MeasurementPoint]
    /// Filled when aggregated, oldest first.
    public let buckets: [TimelineBucket]

    public init(kind: SampleKind, resolution: TimelineResolution, points: [MeasurementPoint], buckets: [TimelineBucket]) {
        self.kind = kind
        self.resolution = resolution
        self.points = points
        self.buckets = buckets
    }

    public var isAggregated: Bool { resolution != .original }
    public var isEmpty: Bool { points.isEmpty && buckets.isEmpty }
}

public enum TimelineQuery {
    /// Span up to which hourly buckets are used above the original limit; beyond it daily buckets.
    public static let hourlyLimit: TimeInterval = 8 * 24 * 3600

    public static func resolution(for window: DateInterval) -> TimelineResolution {
        if window.duration <= TimelineRange.originalResolutionLimit { return .original }
        return window.duration <= hourlyLimit ? .hourly : .daily
    }

    /// Points that belong to `track` and touch `window`, oldest first. Only usable quality and only
    /// values measured up to `now` (a device clock running ahead does not draw into the future).
    public static func points(for track: TimelineTrack, in window: DateInterval, from points: [MeasurementPoint],
                              now: Date) -> [MeasurementPoint] {
        let kinds = Set(track.sampleKinds)
        return points
            .filter { kinds.contains($0.kind) && $0.quality.usableForAnalysis && $0.measuredAt <= now
                && $0.measuredUntil >= window.start && $0.measuredAt <= window.end }
            .sorted { ($0.measuredAt, $0.id.uuidString) < ($1.measuredAt, $1.id.uuidString) }
    }

    /// One series per sample kind of the track, original or aggregated depending on the window span.
    public static func series(for track: TimelineTrack, in window: DateInterval, from all: [MeasurementPoint],
                              now: Date, calendar: Calendar) -> [TimelineSeries] {
        let relevant = Self.points(for: track, in: window, from: all, now: now)
        let level = Self.resolution(for: window)
        return track.sampleKinds.compactMap { kind in
            let mine = relevant.filter { $0.kind == kind }
            guard !mine.isEmpty else { return nil }
            if level == .original {
                return TimelineSeries(kind: kind, resolution: .original, points: mine, buckets: [])
            }
            return TimelineSeries(kind: kind, resolution: level, points: [],
                                  buckets: Self.buckets(mine, kind: kind, resolution: level, calendar: calendar))
        }
    }

    /// Calendar buckets (hour or day in the given calendar, so daylight-saving days have 23 or 25 hours).
    /// Empty buckets are not returned.
    public static func buckets(_ points: [MeasurementPoint], kind: SampleKind, resolution: TimelineResolution,
                               calendar: Calendar) -> [TimelineBucket] {
        let component: Calendar.Component = resolution == .daily ? .day : .hour
        let grouped = Dictionary(grouping: points) { point -> Date in
            calendar.dateInterval(of: component, for: point.measuredAt)?.start ?? point.measuredAt
        }
        return grouped.keys.sorted().compactMap { start in
            guard let values = grouped[start]?.map(\.value), !values.isEmpty,
                  let interval = calendar.dateInterval(of: component, for: start) else { return nil }
            let sum = values.reduce(0, +)
            return TimelineBucket(kind: kind, interval: interval, minimum: values.min() ?? 0, maximum: values.max() ?? 0,
                                  mean: sum / Double(values.count), sum: sum, count: values.count)
        }
    }

    /// Nights with at least one segment inside `window`, oldest first.
    public static func nights(in window: DateInterval, from segments: [SleepSegment]) -> [SleepNight] {
        let touching = Set(segments.filter { $0.end >= window.start && $0.start <= window.end }.map(\.sessionID))
        return SleepSegmentSync.nights(segments.filter { touching.contains($0.sessionID) })
    }

    /// The newest usable value of `kind` measured up to `now`, with its own time. Nil if there is none;
    /// how old it is, the caller shows next to it.
    public static func latest(_ kind: SampleKind, in points: [MeasurementPoint], now: Date) -> MeasurementPoint? {
        points
            .filter { $0.kind == kind && $0.quality.usableForAnalysis && $0.measuredAt <= now }
            .max { ($0.measuredAt, $0.id.uuidString) < ($1.measuredAt, $1.id.uuidString) }
    }

    /// Stretches inside `window` longer than `maximumGap` without a point of `kind`. For drawing breaks in
    /// a line instead of connecting across hours without data.
    public static func gaps(in points: [MeasurementPoint], kind: SampleKind, window: DateInterval,
                            maximumGap: TimeInterval) -> [DateInterval] {
        let times = points.filter { $0.kind == kind }.map(\.measuredAt).filter { window.contains($0) }.sorted()
        var result: [DateInterval] = []
        var previous = window.start
        for time in times + [window.end] {
            if time.timeIntervalSince(previous) > maximumGap { result.append(DateInterval(start: previous, end: time)) }
            previous = max(previous, time)
        }
        return result
    }
}
