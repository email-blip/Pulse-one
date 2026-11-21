import Foundation
import PulseCore

/// Local notifications for the day's nudges (ids "companion.nudge.<id>"). Each refresh replaces all pending
/// nudges, so a re-plan never leaves stale reminders behind. Nothing is scheduled in UI tests.
@MainActor
enum NudgeScheduler {
    static let prefix = "companion.nudge."

    static func requestAuthorization() async -> Bool {
        guard !LaunchOptions.current.isUITesting else { return false }
        return await CompanionNotifications.requestAuthorization()
    }

    static func replace(with nudges: [CompanionNudge], now: Date = Date(), calendar: Calendar = .current) async {
        guard !LaunchOptions.current.isUITesting else { return }
        await CompanionNotifications.removePending(ids: [], prefix: prefix)
        for nudge in upcoming(nudges, now: now) {
            try? await CompanionNotifications.add(id: prefix + nudge.id, title: nudge.title, body: nudge.body,
                                                  components: components(for: nudge.time, calendar: calendar))
        }
    }

    /// Nudges still in the future, in time order, without duplicate ids.
    static func upcoming(_ nudges: [CompanionNudge], now: Date) -> [CompanionNudge] {
        var seen = Set<String>()
        return nudges.filter { $0.time > now }.sorted { $0.time < $1.time }.filter { seen.insert($0.id).inserted }
    }

    /// One-shot trigger components (year to minute) for a moment.
    static func components(for date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}
