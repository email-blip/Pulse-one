import Foundation

/// Rules every PULSE ONE push follows: a concrete action, quiet hours, "heute nicht", nothing for what is done,
/// no identical push without a new state.
public struct NotificationRules: Codable, Equatable, Sendable {
    public var quietStartHour: Int
    public var quietEndHour: Int
    /// "Heute nicht": no reminders until this moment.
    public var pausedUntil: Date?

    public init(quietStartHour: Int = 22, quietEndHour: Int = 7, pausedUntil: Date? = nil) {
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
        self.pausedUntil = pausedUntil
    }
}

public struct NotificationCandidate: Equatable, Sendable {
    /// Stable topic, e.g. "nudge.movement"; with the fingerprint it decides "same push again".
    public let topic: String
    public let fireAt: Date
    /// The state the text rests on (e.g. title + body); a new state makes a new push legitimate.
    public let fingerprint: String
    /// The action was already done today: never remind.
    public let isDone: Bool
    /// Alarms and the training's own phase end are asked for by the person and ignore quiet hours.
    public let isRequestedByPerson: Bool

    public init(topic: String, fireAt: Date, fingerprint: String, isDone: Bool = false, isRequestedByPerson: Bool = false) {
        self.topic = topic
        self.fireAt = fireAt
        self.fingerprint = fingerprint
        self.isDone = isDone
        self.isRequestedByPerson = isRequestedByPerson
    }
}

public struct SentNotification: Codable, Equatable, Sendable {
    public let topic: String
    public let fingerprint: String
    public let at: Date

    public init(topic: String, fingerprint: String, at: Date) {
        self.topic = topic
        self.fingerprint = fingerprint
        self.at = at
    }
}

public enum NotificationPolicy {
    /// A push with the same topic and fingerprint within this time is "identical".
    public static let repeatWindow: TimeInterval = 20 * 3600

    public static func allows(_ candidate: NotificationCandidate, rules: NotificationRules, history: [SentNotification],
                              calendar: Calendar) -> Bool {
        if candidate.isDone { return false }
        if candidate.isRequestedByPerson { return true }
        if let paused = rules.pausedUntil, candidate.fireAt < paused { return false }
        if isQuiet(candidate.fireAt, rules: rules, calendar: calendar) { return false }
        return !history.contains { sent in
            sent.topic == candidate.topic && sent.fingerprint == candidate.fingerprint
                && sent.at <= candidate.fireAt && candidate.fireAt.timeIntervalSince(sent.at) < repeatWindow
        }
    }

    /// Quiet hours may wrap midnight (22–7).
    public static func isQuiet(_ date: Date, rules: NotificationRules, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if rules.quietStartHour == rules.quietEndHour { return false }
        if rules.quietStartHour < rules.quietEndHour {
            return hour >= rules.quietStartHour && hour < rules.quietEndHour
        }
        return hour >= rules.quietStartHour || hour < rules.quietEndHour
    }

    /// End of "heute nicht": the start of the next day.
    public static func endOfToday(_ now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 3600)
    }

    /// Keeps the history small: only entries inside the repeat window.
    public static func pruned(_ history: [SentNotification], now: Date) -> [SentNotification] {
        history.filter { now.timeIntervalSince($0.at) < repeatWindow * 2 }
    }
}
