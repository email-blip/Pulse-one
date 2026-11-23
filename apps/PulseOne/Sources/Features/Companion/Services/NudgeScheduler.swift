import Foundation
import PulseCore
import UserNotifications

/// Local notifications for the day's nudges (ids "companion.nudge.<id>"). Each refresh replaces all pending
/// nudges, so a re-plan never leaves stale reminders behind. Every nudge passes `NotificationPolicy`: quiet hours,
/// "Heute nicht", nothing for what is already done, no identical push without a new state. Nothing is scheduled
/// in UI tests.
@MainActor
enum NudgeScheduler {
    static let prefix = "companion.nudge."

    static func requestAuthorization() async -> Bool {
        guard !LaunchOptions.current.isUITesting else { return false }
        return await CompanionNotifications.requestAuthorization()
    }

    /// Replaces the pending nudges. Returns false when notifications are not allowed or a nudge could not be
    /// scheduled, so the UI does not promise a reminder that never arrives. Asks for permission once when the
    /// person has not decided yet and there is something to schedule.
    @discardableResult
    static func replace(with nudges: [CompanionNudge], now: Date = Date(), calendar: Calendar = .current) async -> Bool {
        guard !LaunchOptions.current.isUITesting else { return true }
        await CompanionNotifications.removePending(ids: [], prefix: prefix)
        let due = permitted(upcoming(nudges, now: now), now: now, calendar: calendar)
        guard !due.isEmpty else { return true }
        guard await CompanionNotifications.ensureAuthorized() else { return false }
        NotificationGate.registerCategories()
        var allScheduled = true
        for nudge in due {
            do {
                try await CompanionNotifications.add(id: prefix + nudge.id, title: nudge.title, body: nudge.body,
                                                     components: components(for: nudge.time, calendar: calendar),
                                                     category: NotificationGate.nudgeCategory)
                NotificationGate.record(topic: topic(nudge), fingerprint: fingerprint(nudge), at: nudge.time)
            } catch {
                allScheduled = false
            }
        }
        return allScheduled
    }

    /// Nudges still in the future, in time order, without duplicate ids.
    static func upcoming(_ nudges: [CompanionNudge], now: Date) -> [CompanionNudge] {
        var seen = Set<String>()
        return nudges.filter { $0.time > now }.sorted { $0.time < $1.time }.filter { seen.insert($0.id).inserted }
    }

    /// The nudges the rules let through. Movement nudges count as done once a training session was saved today.
    static func permitted(_ nudges: [CompanionNudge], now: Date, calendar: Calendar) -> [CompanionNudge] {
        let rules = NotificationGate.rules
        // Entries for the nudges that are being replaced right now are not "already sent".
        let history = NotificationGate.history.filter { $0.at <= now }
        let trainedToday = (UserDefaults.standard.object(forKey: TrainingController.finishedDayKey) as? Date)
            .map { calendar.isDate($0, inSameDayAs: now) } ?? false
        return nudges.filter { nudge in
            let done = trainedToday && (nudge.kind == .movement || nudge.kind == .sportWindow)
            let candidate = NotificationCandidate(topic: topic(nudge), fireAt: nudge.time, fingerprint: fingerprint(nudge),
                                                  isDone: done)
            return NotificationPolicy.allows(candidate, rules: rules, history: history, calendar: calendar)
        }
    }

    static func topic(_ nudge: CompanionNudge) -> String { "nudge." + nudge.kind.rawValue }
    static func fingerprint(_ nudge: CompanionNudge) -> String { nudge.title + "|" + nudge.body }

    /// One-shot trigger components (year to minute) for a moment.
    static func components(for date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}

/// Stored notification rules and the short history of what was sent (UserDefaults, no health values).
@MainActor
enum NotificationGate {
    nonisolated static let nudgeCategory = "pulse.nudge"
    nonisolated static let pauseTodayAction = "pulse.pauseToday"
    private static let rulesKey = "notifications.rules"
    private static let historyKey = "notifications.history"

    static var rules: NotificationRules {
        get {
            UserDefaults.standard.data(forKey: rulesKey).flatMap { try? JSONDecoder().decode(NotificationRules.self, from: $0) }
                ?? NotificationRules()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: rulesKey) }
        }
    }

    static var history: [SentNotification] {
        UserDefaults.standard.data(forKey: historyKey).flatMap { try? JSONDecoder().decode([SentNotification].self, from: $0) } ?? []
    }

    static func record(topic: String, fingerprint: String, at date: Date) {
        var entries = NotificationPolicy.pruned(history, now: Date())
        entries.removeAll { $0.topic == topic && $0.at == date }
        entries.append(SentNotification(topic: topic, fingerprint: fingerprint, at: date))
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: historyKey) }
    }

    /// "Heute nicht": no reminders until tomorrow; pending nudges are removed right away.
    static func pauseToday(now: Date = Date(), calendar: Calendar = .current) async {
        var current = rules
        current.pausedUntil = NotificationPolicy.endOfToday(now, calendar: calendar)
        rules = current
        await CompanionNotifications.removePending(ids: [], prefix: NudgeScheduler.prefix)
    }

    /// The "Heute nicht" button on reminders. Registered with every other category the app uses (none so far).
    static func registerCategories() {
        let pause = UNNotificationAction(identifier: pauseTodayAction, title: "Heute nicht", options: [])
        let nudge = UNNotificationCategory(identifier: nudgeCategory, actions: [pause], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([nudge])
    }
}
