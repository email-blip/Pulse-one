import Foundation

/// How sure we are that a ring delivers a metric (Codex review: expected ≠ verified).
public enum CapabilityLevel: Int, Comparable, Sendable {
    /// Community or vendor claims for this model.
    case expected = 0
    /// The ring offers the service/characteristic needed.
    case discovered = 1
    /// The ring actually returned a plausible value in this app.
    case verified = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .expected: "erwartet"
        case .discovered: "Dienst gefunden"
        case .verified: "nachgewiesen"
        }
    }
}

/// Tracks capability levels per metric. Levels only go up during a session.
public struct CapabilityTracker: Equatable, Sendable {
    public private(set) var levels: [Metric: CapabilityLevel]

    public init(expected: [Metric] = Metric.allCases) {
        levels = Dictionary(uniqueKeysWithValues: expected.map { ($0, .expected) })
    }

    public mutating func raise(_ metric: Metric, to level: CapabilityLevel) {
        levels[metric] = max(levels[metric] ?? .expected, level)
    }

    public func level(of metric: Metric) -> CapabilityLevel? { levels[metric] }
}
