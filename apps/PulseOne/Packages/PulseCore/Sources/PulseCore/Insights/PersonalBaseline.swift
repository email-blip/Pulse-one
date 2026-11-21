import Foundation

/// Where a value lies relative to the personal band. Described in words, never as a traffic light.
public enum BandPosition: String, Equatable, Sendable {
    case below, within, above

    public var description: String {
        switch self {
        case .below: "unter deinem üblichen Bereich"
        case .within: "im üblichen Bereich"
        case .above: "über deinem üblichen Bereich"
        }
    }
}

/// The personal usual range of one kind: the middle half (25th to 75th percentile) of the person's
/// own daily values in a window before a reference day. Describes the person's past, predicts nothing.
public struct PersonalBaseline: Equatable, Sendable {
    public let kind: SampleKind
    public let median: Double
    /// 25th percentile.
    public let lower: Double
    /// 75th percentile.
    public let upper: Double
    /// Days with data that went into the band.
    public let dayCount: Int
    public let windowDays: Int

    /// Days with data needed before a band is shown.
    public static let minimumDays = 7
    public static let defaultWindowDays = 28

    public func position(of value: Double) -> BandPosition {
        if value < lower { return .below }
        if value > upper { return .above }
        return .within
    }

    /// Builds the band from daily values strictly before `day` (the reference day itself is what gets compared).
    public static func status(for days: [DailyValue], kind: SampleKind, before day: Date, calendar: Calendar,
                              windowDays: Int = defaultWindowDays) -> BaselineStatus {
        let end = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else {
            return .forming(daysAvailable: 0, daysNeeded: minimumDays)
        }
        let values = days
            .filter { $0.kind == kind && $0.day >= start && $0.day < end }
            .map(\.value)
            .sorted()
        guard values.count >= minimumDays else {
            return .forming(daysAvailable: values.count, daysNeeded: minimumDays - values.count)
        }
        return .ready(PersonalBaseline(kind: kind, median: percentile(values, 0.5), lower: percentile(values, 0.25),
                                       upper: percentile(values, 0.75), dayCount: values.count, windowDays: windowDays))
    }

    /// Linear interpolation between closest ranks; `sorted` must be ascending and non-empty.
    public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let rank = p * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down))
        let high = min(low + 1, sorted.count - 1)
        let fraction = rank - Double(low)
        return sorted[low] + (sorted[high] - sorted[low]) * fraction
    }
}

public enum BaselineStatus: Equatable, Sendable {
    /// Not enough days yet; `daysNeeded` more days with data are required.
    case forming(daysAvailable: Int, daysNeeded: Int)
    case ready(PersonalBaseline)

    public var baseline: PersonalBaseline? {
        if case .ready(let baseline) = self { return baseline }
        return nil
    }

    /// Short German text for cards.
    public var summary: String {
        switch self {
        case .forming(_, let needed):
            needed == 1 ? "Noch 1 Tag bis zu deinem persönlichen Bereich" : "Noch \(needed) Tage bis zu deinem persönlichen Bereich"
        case .ready(let baseline):
            "Üblicher Bereich aus \(baseline.dayCount) Tagen"
        }
    }
}
