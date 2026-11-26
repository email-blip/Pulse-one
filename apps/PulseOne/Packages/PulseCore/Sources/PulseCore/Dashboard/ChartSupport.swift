import Foundation

// Team 03 (Dashboard / Zeitspuren). Readability helpers for the Verlauf charts: a few round y-axis values,
// the comparison overlay (yesterday, mean of the last seven days) and the training tile's week.

public enum AxisTicks {
    /// Two or three round values inside `domain` for a discreet y-axis ("60 · 80 · 100").
    public static func values(in domain: ClosedRange<Double>, count: Int = 3) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, span.isFinite, count > 1 else { return [] }
        var step = niceStep(span / Double(count + 1))
        var result = multiples(of: step, in: domain)
        // Too many lines at the chosen step: the next coarser round step.
        while result.count > count {
            step = niceStep(step * 1.01)
            result = multiples(of: step, in: domain)
        }
        return result
    }

    /// 1, 2, 2.5 or 5 times a power of ten, at least `raw`.
    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let power = pow(10, floor(log10(raw)))
        for factor in [1.0, 2.0, 2.5, 5.0, 10.0] where factor * power >= raw * 0.999 {
            return factor * power
        }
        return 10 * power
    }

    private static func multiples(of step: Double, in domain: ClosedRange<Double>) -> [Double] {
        var value = (domain.lowerBound / step).rounded(.up) * step
        var result: [Double] = []
        while value <= domain.upperBound + step * 1e-9, result.count < 20 {
            result.append((value / step).rounded() * step)
            value += step
        }
        return result
    }
}

/// What a value track is compared with: nothing, the day before, or the mean of the seven days before.
public enum TrackComparisonMode: String, CaseIterable, Sendable {
    case off, yesterday, week

    /// Days before the window that feed the comparison.
    public var daysBack: [Int] {
        switch self {
        case .off: []
        case .yesterday: [1]
        case .week: Array(1...7)
        }
    }

    /// A slot is only drawn when at least this many of the days measured something in it.
    public var minimumDays: Int {
        switch self {
        case .off, .yesterday: 1
        case .week: 3
        }
    }
}

public enum TrackComparison {
    /// The comparison only makes sense on a day scale (original points, up to two days).
    public static func isAvailable(for window: DateInterval) -> Bool {
        TimelineQuery.resolution(for: window) == .original
    }

    /// Slot length: the ring's own step for cumulative kinds (so a slot sum compares with a bar), otherwise
    /// about 144 slots across the window and never shorter than the usual distance between two values.
    public static func slot(for kind: SampleKind, window: DateInterval) -> TimeInterval {
        let expected = TrackSeries.expectedInterval(kind)
        if kind.isCumulative { return expected }
        let raw = max(expected, window.duration / 144)
        return (raw / 300).rounded(.up) * 300
    }

    /// The days before `window` laid over it, one value per slot: mean of the days that measured in it (point
    /// kinds use each day's slot mean, cumulative kinds each day's slot sum). Slots without enough days stay
    /// empty and split the line into runs; nothing is filled in.
    public static func profile(_ sorted: [MeasurementPoint], kind: SampleKind, window: DateInterval,
                               mode: TrackComparisonMode, calendar: Calendar) -> [TrackValue] {
        guard mode != .off, window.duration > 0 else { return [] }
        let slot = slot(for: kind, window: window)
        let slotCount = Int((window.duration / slot).rounded(.up))
        guard slotCount > 0 else { return [] }
        // Per slot: one value per day that measured there.
        var perSlot: [[Double]] = Array(repeating: [], count: slotCount)
        for days in mode.daysBack {
            guard let start = calendar.date(byAdding: .day, value: -days, to: window.start),
                  let end = calendar.date(byAdding: .day, value: -days, to: window.end) else { continue }
            let shift = window.start.timeIntervalSince(start)
            var sums = [Double](repeating: 0, count: slotCount)
            var counts = [Int](repeating: 0, count: slotCount)
            for point in TrackSeries.slice(sorted, in: DateInterval(start: start, end: max(start, end)))
            where point.measuredAt >= start && point.measuredAt < end {
                let index = Int(point.measuredAt.addingTimeInterval(shift).timeIntervalSince(window.start) / slot)
                guard index >= 0, index < slotCount else { continue }
                sums[index] += point.value
                counts[index] += 1
            }
            for index in 0..<slotCount where counts[index] > 0 {
                perSlot[index].append(kind.isCumulative ? sums[index] : sums[index] / Double(counts[index]))
            }
        }
        var result: [TrackValue] = []
        var run = 0
        var previous: Int?
        for (index, values) in perSlot.enumerated() where values.count >= mode.minimumDays {
            if let previous, index != previous + 1 { run += 1 }
            previous = index
            let start = window.start.addingTimeInterval(Double(index) * slot)
            let end = min(start.addingTimeInterval(slot), window.end)
            let mean = values.reduce(0, +) / Double(values.count)
            result.append(TrackValue(id: "cmp-\(mode.rawValue)-\(index)", start: start, end: end, value: mean,
                                     low: values.min() ?? mean, high: values.max() ?? mean, count: values.count,
                                     isAggregated: true, run: run))
        }
        return result
    }
}

/// One training session for the dashboard tile (Apple Health workout or a session saved in the app).
public struct TrainingSession: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let title: String

    public init(start: Date, end: Date, title: String) {
        self.start = start
        self.end = end
        self.title = title
    }

    public var minutes: Double { max(end.timeIntervalSince(start), 0) / 60 }
}

/// The training tile's content: today if there was a session, otherwise this week, the last session and
/// minutes per day of the last seven days.
public struct TrainingWeek: Equatable, Sendable {
    public let todayMinutes: Double
    public let todayCount: Int
    public let weekMinutes: Double
    public let weekCount: Int
    public let last: TrainingSession?
    /// Minutes per day, oldest first, the last entry is today.
    public let days: [Double]

    public init(sessions: [TrainingSession], now: Date, calendar: Calendar) {
        let past = sessions.filter { $0.start <= now }.sorted { $0.start < $1.start }
        let today = calendar.startOfDay(for: now)
        let todays = past.filter { calendar.isDate($0.start, inSameDayAs: today) }
        todayMinutes = todays.reduce(0) { $0 + $1.minutes }
        todayCount = todays.count
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: today, duration: 86_400)
        let weeks = past.filter { week.contains($0.start) }
        weekMinutes = weeks.reduce(0) { $0 + $1.minutes }
        weekCount = weeks.count
        last = past.last
        days = (0..<7).reversed().map { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return 0 }
            return past.filter { calendar.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
        }
    }

    /// Value, unit and reference line of the tile; nil without any session in the read days.
    public func reading(now: Date, calendar: Calendar) -> (text: String, unit: String, reference: String, at: Date)? {
        guard let last else { return nil }
        let german = Locale(identifier: "de_DE")
        var weekday = Date.FormatStyle(locale: german, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
        weekday.timeZone = calendar.timeZone
        let clock = Date.FormatStyle(locale: german, calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        if todayCount > 0 {
            let units = todayCount == 1 ? "1 EINHEIT" : "\(todayCount) EINHEITEN"
            return ("\(Int(todayMinutes.rounded()))", "min", "HEUTE · \(units)", last.start)
        }
        let lastText: String
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(last.start, inSameDayAs: yesterday) {
            lastText = "GESTERN \(last.start.formatted(clock))"
        } else {
            lastText = "\(last.start.formatted(weekday).replacingOccurrences(of: ".", with: "").uppercased()) \(last.start.formatted(clock))"
        }
        let units = weekCount == 1 ? "1 EINHEIT" : "\(weekCount) EINHEITEN"
        return ("\(Int(weekMinutes.rounded()))", "min", "WOCHE · \(units) · LETZTE \(lastText)", last.start)
    }
}
