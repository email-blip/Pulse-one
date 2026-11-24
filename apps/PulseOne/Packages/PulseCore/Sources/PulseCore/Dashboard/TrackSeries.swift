import Foundation

// Team 03 (Dashboard / Zeitspuren). Pure logic behind the Verlauf tracks on top of team 01's `TimelineQuery`:
// drawable values (original points or marked buckets), runs and gaps, and what the shared cursor picks.

extension TimelineResolution {
    /// Short German label for the track header ("Mittel je Stunde", "Tagessumme" …); nil for original points.
    public func trackLabel(cumulative: Bool) -> String? {
        switch self {
        case .original: nil
        case .hourly: cumulative ? "Summe je Stunde" : "Mittel je Stunde"
        case .daily: cumulative ? "Tagessumme" : "Tagesmittel"
        }
    }

    var key: String {
        switch self {
        case .original: "o"
        case .hourly: "h"
        case .daily: "d"
        }
    }
}

/// One drawable value of a track: either one original measurement or one aggregated bucket.
public struct TrackValue: Identifiable, Equatable, Sendable {
    public let id: String
    public let start: Date
    public let end: Date
    /// Canonical unit. Mean of the bucket for point values, sum for cumulative values.
    public let value: Double
    public let low: Double
    public let high: Double
    public let count: Int
    public let isAggregated: Bool
    /// Values without a gap between them share a run; lines are never drawn from one run to the next.
    public let run: Int

    public init(id: String, start: Date, end: Date, value: Double, low: Double, high: Double, count: Int,
                isAggregated: Bool, run: Int) {
        self.id = id
        self.start = start
        self.end = end
        self.value = value
        self.low = low
        self.high = high
        self.count = count
        self.isAggregated = isAggregated
        self.run = run
    }

    /// Where the value sits on the time axis (middle of an interval).
    public var at: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }

    public func contains(_ time: Date) -> Bool {
        (isAggregated || end > start) ? (time >= start && time < end) : time == start
    }
}

public enum TrackSeries {
    /// Usual distance between two values of a kind (R03 profile: pulse 5 min, HRV/SpO₂/stress 30 min,
    /// steps 15 min). Used for the gap rule and the cursor tolerance.
    public static func expectedInterval(_ kind: SampleKind) -> TimeInterval {
        switch kind {
        case .heartRate: 5 * 60
        case .ringHRV, .heartRateVariability, .oxygenSaturation, .ringStress, .respiratoryRate: 30 * 60
        case .steps, .activeEnergy, .distance, .basalEnergy: 15 * 60
        case .restingHeartRate, .sleepDuration, .vo2Max, .skinTemperatureDeviation: 86_400
        default: 60 * 60
        }
    }

    /// Two original values further apart than this have a visible gap between them.
    public static func gapThreshold(_ kind: SampleKind) -> TimeInterval { expectedInterval(kind) * 3 }

    /// How far the cursor may sit from an original point and still pick it. Smaller than half the
    /// gap threshold, so a cursor inside a gap never picks the point at its edge.
    public static func cursorTolerance(_ kind: SampleKind) -> TimeInterval { expectedInterval(kind) * 0.6 }

    /// Points (sorted by time) that overlap `window`. Binary search, so a year of pulse values stays fast.
    public static func slice(_ sorted: [MeasurementPoint], in window: DateInterval) -> ArraySlice<MeasurementPoint> {
        var low = 0
        var high = sorted.count
        // First point whose end is not before the window start.
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].measuredUntil < window.start { low = mid + 1 } else { high = mid }
        }
        var end = low
        var upper = sorted.count
        while end < upper {
            let mid = (end + upper) / 2
            if sorted[mid].measuredAt <= window.end { end = mid + 1 } else { upper = mid }
        }
        return sorted[low..<max(low, end)]
    }

    /// Drawable values of one kind in `window`. Never invents a value: empty buckets stay empty and
    /// split the line into runs.
    public static func values(_ points: some Collection<MeasurementPoint>, kind: SampleKind, in window: DateInterval,
                              resolution: TimelineResolution, calendar: Calendar) -> [TrackValue] {
        let inside = points.filter { $0.measuredUntil >= window.start && $0.measuredAt <= window.end }
            .sorted { $0.measuredAt < $1.measuredAt }
        guard !inside.isEmpty else { return [] }
        if resolution == .original {
            var run = 0
            var previousEnd: Date?
            return inside.map { point in
                if let previousEnd, point.measuredAt.timeIntervalSince(previousEnd) > gapThreshold(kind) { run += 1 }
                previousEnd = max(previousEnd ?? point.measuredUntil, point.measuredUntil)
                return TrackValue(id: point.id.uuidString, start: point.measuredAt, end: point.measuredUntil,
                                  value: point.value, low: point.value, high: point.value, count: 1,
                                  isAggregated: false, run: run)
            }
        }
        var result: [TrackValue] = []
        var run = 0
        var previousEnd: Date?
        for bucket in TimelineQuery.buckets(inside, kind: kind, resolution: resolution, calendar: calendar) {
            let start = bucket.interval.start
            if let previousEnd, start > previousEnd { run += 1 }
            previousEnd = bucket.interval.end
            let value = bucket.representative
            let summed = kind.aggregation == .cumulative
            result.append(TrackValue(id: "\(resolution.key)-\(Int(start.timeIntervalSince1970))", start: start,
                                     end: bucket.interval.end, value: value, low: summed ? value : bucket.minimum,
                                     high: summed ? value : bucket.maximum, count: bucket.count,
                                     isAggregated: true, run: run))
        }
        return result
    }

    /// Stretches between runs, drawn as gaps (never as zero).
    public static func gaps(in values: [TrackValue]) -> [DateInterval] {
        var result: [DateInterval] = []
        for (previous, next) in zip(values, values.dropFirst()) where next.run != previous.run && next.start > previous.end {
            result.append(DateInterval(start: previous.end, end: next.start))
        }
        return result
    }

    /// The original point the cursor picks: an interval that contains it, otherwise the nearest point within
    /// the tolerance of the kind. In a gap this is nil.
    public static func pick(at time: Date, in points: some Collection<MeasurementPoint>, kind: SampleKind) -> MeasurementPoint? {
        let covering = points.filter { $0.isInterval && $0.measuredAt <= time && time < $0.measuredUntil }
        if let inside = covering.min(by: { $0.measuredUntil.timeIntervalSince($0.measuredAt) < $1.measuredUntil.timeIntervalSince($1.measuredAt) }) {
            return inside
        }
        return TimelineState.nearest(to: time, in: points.filter { !$0.isInterval }, tolerance: cursorTolerance(kind))
    }

    /// The aggregated bucket under the cursor, if any.
    public static func bucket(at time: Date, in values: [TrackValue]) -> TrackValue? {
        values.first { $0.isAggregated && $0.start <= time && time < $0.end }
    }

    /// Original point before/after `time` (accessible "Vorheriger/Nächster Messpunkt").
    public static func step(from time: Date, in sorted: [MeasurementPoint], forward: Bool) -> MeasurementPoint? {
        forward ? sorted.first { $0.measuredAt > time } : sorted.last { $0.measuredAt < time }
    }

    /// Y range wide enough that small normal swings do not look dramatic (pulse 69–71, SpO₂ 96–97 %).
    public static func yDomain(for values: [TrackValue], kind: SampleKind) -> ClosedRange<Double> {
        let numbers = values.flatMap { [kind.displayNumber($0.low), kind.displayNumber($0.high)] }
        guard let low = numbers.min(), let high = numbers.max() else { return 0...1 }
        if kind.isCumulative { return 0...max(high * 1.1, 1) }
        let minimumSpan: Double = switch kind {
        case .heartRate: 20
        case .restingHeartRate, .heartRateVariability, .ringHRV: 12
        case .oxygenSaturation: 8
        case .ringStress: 30
        default: 1
        }
        let span = max(high - low, minimumSpan)
        let middle = (low + high) / 2
        var lower = min(low, middle - span / 2) - span * 0.1
        var upper = max(high, middle + span / 2) + span * 0.1
        if kind == .oxygenSaturation, upper > 100 {
            lower -= upper - 100
            upper = 100
        }
        return lower...upper
    }
}

/// Decides whether a value is staged as "just arrived". Only values received just now *and* measured just
/// now land with motion; history from a sync is shown in place without pretending it is new.
public enum LiveArrival {
    public static let receivedWindow: TimeInterval = 120
    public static let measuredWindow: TimeInterval = 600

    public static func isFresh(_ point: MeasurementPoint, now: Date) -> Bool {
        let received = now.timeIntervalSince(point.receivedAt)
        let measured = now.timeIntervalSince(point.measuredAt)
        return received >= -60 && received <= receivedWindow && measured >= -60 && measured <= measuredWindow
    }

    /// Fresh points that were not on screen before.
    public static func arrivals(known: Set<UUID>, current: [MeasurementPoint], now: Date) -> [MeasurementPoint] {
        current.filter { !known.contains($0.id) && isFresh($0, now: now) }
    }
}
