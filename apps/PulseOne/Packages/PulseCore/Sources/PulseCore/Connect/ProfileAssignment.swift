import Foundation

/// One period in which a device belonged to a profile (Review 3.2 §2). `profileID == nil` marks a
/// period as explicitly unresolved. Every entry keeps when and why it was recorded.
public struct DeviceAssignment: Equatable, Codable, Sendable {
    public var profileID: UUID?
    public var from: Date
    /// Exclusive end; nil = still running.
    public var until: Date?
    public var reason: String
    public var recordedAt: Date

    public init(profileID: UUID?, from: Date, until: Date? = nil, reason: String, recordedAt: Date) {
        self.profileID = profileID
        self.from = from
        self.until = until
        self.reason = reason
        self.recordedAt = recordedAt
    }

    public func contains(_ date: Date) -> Bool { from <= date && (until.map { date < $0 } ?? true) }
}

/// Who wore a device when. A time outside every period, or inside an unresolved period, is unresolved.
public struct ProfileTimeline: Equatable, Sendable {
    public let assignments: [DeviceAssignment]

    public init(_ assignments: [DeviceAssignment]) {
        self.assignments = assignments.sorted { $0.from < $1.from }
    }

    /// A source that always belongs to one profile (Apple Health → iPhone owner).
    public static func constant(_ profile: UUID?) -> ProfileTimeline {
        ProfileTimeline([DeviceAssignment(profileID: profile, from: .distantPast, reason: "fest", recordedAt: .distantPast)])
    }

    public func profile(at date: Date) -> UUID? {
        assignments.last { $0.contains(date) }?.profileID
    }
}

public enum AssignmentError: Error, Equatable, Sendable {
    /// The new period would start before the running one; use a correction instead.
    case startsBeforeCurrent
    case emptyPeriod
    case missingReason
}

extension Array where Element == DeviceAssignment {
    /// Hands the device to `profile` from `date` on. The running period ends at `date`; earlier periods
    /// stay untouched, so historic samples keep their profile.
    mutating func handOver(to profile: UUID?, from date: Date, reason: String, now: Date) throws {
        if let open = lastIndex(where: { $0.until == nil }) {
            guard date >= self[open].from else { throw AssignmentError.startsBeforeCurrent }
            self[open].until = date
        }
        append(DeviceAssignment(profileID: profile, from: date, reason: reason, recordedAt: now))
    }

    /// Manual correction of a past period. Overlapping periods are trimmed or split; the correction is
    /// stored with its reason so it stays traceable. Samples in the range must then be re-attributed.
    mutating func correct(to profile: UUID?, from start: Date, until end: Date, reason: String, now: Date) throws {
        guard start < end else { throw AssignmentError.emptyPeriod }
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { throw AssignmentError.missingReason }
        var result: [DeviceAssignment] = []
        for a in self {
            let aEnd = a.until ?? .distantFuture
            if aEnd <= start || a.from >= end { result.append(a); continue }
            if a.from < start { var head = a; head.until = start; result.append(head) }
            if aEnd > end { var tail = a; tail.from = end; result.append(tail) }
        }
        result.append(DeviceAssignment(profileID: profile, from: start, until: end, reason: "Korrektur: \(reason)", recordedAt: now))
        self = result.sorted { $0.from < $1.from }
    }
}
