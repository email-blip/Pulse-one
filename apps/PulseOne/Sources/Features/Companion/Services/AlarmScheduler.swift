import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI
import UserNotifications

/// The companion's wake-up alarm. iOS 26+: a real system alarm through AlarmKit (rings in silent mode and
/// Focus, button "Ich bin wach"). Below iOS 26: one repeating notification per weekday with the wake sound
/// (muted by the silent switch; it can only open the app). See BEGLEITER-IOS-GRENZEN.md §1–2.
@MainActor
final class AlarmScheduler {
    enum SchedulingError: Error {
        case notAuthorized
    }

    /// Sound file in the main bundle (Sources/Features/Companion/Resources), < 30 s Linear PCM.
    nonisolated static let soundName = "begleiter-weckruf.wav"
    nonisolated static let notificationPrefix = "companion.alarm."

    init() {}

    var isAlarmKitAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Asks for alarm permission (AlarmKit) or notification permission (fallback). Never in UI tests.
    func requestAuthorization() async -> Bool {
        guard !LaunchOptions.current.isUITesting else { return false }
        if #available(iOS 26.0, *) {
            return await CompanionAlarmKit.requestAuthorization()
        }
        return await CompanionNotifications.requestAuthorization()
    }

    /// Schedules the alarm and returns the ids to store (pass them to `cancelAll(ids:)` later).
    /// `weekdays` are Calendar weekdays (1 = Sunday … 7 = Saturday); empty = once at the next matching time.
    func schedule(hour: Int, minute: Int, weekdays: [Int]) async throws -> [String] {
        guard !LaunchOptions.current.isUITesting else { return [] }
        let days = AlarmScheduleMath.normalized(weekdays)
        if #available(iOS 26.0, *) {
            guard await CompanionAlarmKit.requestAuthorization() else { throw SchedulingError.notAuthorized }
            let id = try await CompanionAlarmKit.schedule(hour: hour, minute: minute, weekdays: days)
            return [id]
        }
        guard await CompanionNotifications.requestAuthorization() else { throw SchedulingError.notAuthorized }
        return try await CompanionNotifications.scheduleAlarm(hour: hour, minute: minute, weekdays: days)
    }

    /// Cancels the given alarms (AlarmKit UUIDs and notification ids) plus any leftover fallback notifications.
    func cancelAll(ids: [String]) async {
        guard !LaunchOptions.current.isUITesting else { return }
        if #available(iOS 26.0, *) {
            CompanionAlarmKit.cancel(ids: ids)
        }
        await CompanionNotifications.removePending(ids: ids, prefix: Self.notificationPrefix)
    }
}

// MARK: - Pure helpers

/// Weekday and trigger math, free of system frameworks state.
enum AlarmScheduleMath {
    /// Valid, unique, sorted Calendar weekdays (1…7).
    static func normalized(_ weekdays: [Int]) -> [Int] {
        Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
    }

    /// Calendar weekday (1 = Sunday … 7 = Saturday) → `Locale.Weekday`.
    static func localeWeekday(_ weekday: Int) -> Locale.Weekday? {
        switch weekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }

    /// Trigger components for the fallback notification of one weekday (nil weekday = every day / once).
    static func components(hour: Int, minute: Int, weekday: Int?) -> DateComponents {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.weekday = weekday
        return components
    }

    static func notificationID(weekday: Int?) -> String {
        AlarmScheduler.notificationPrefix + (weekday.map(String.init) ?? "once")
    }
}

// MARK: - "Ich bin wach" (alarm button)

/// Key of the wake-up moment written by the alarm button; the app consumes it on the next refresh.
enum PendingWake {
    static let key = "companion.pendingWake"

    /// Stores now as the confirmed wake-up moment.
    static func markNow() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// The stored moment if it is younger than `maxAge`, without removing it.
    static func peek(maxAge: TimeInterval = 7200, now: Date = Date()) -> Date? {
        let seconds = UserDefaults.standard.double(forKey: key)
        guard seconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        guard now.timeIntervalSince(date) <= maxAge, date <= now.addingTimeInterval(60) else { return nil }
        return date
    }

    /// Returns the stored moment (if younger than `maxAge`) and removes it.
    static func consume(maxAge: TimeInterval = 7200, now: Date = Date()) -> Date? {
        let date = peek(maxAge: maxAge, now: now)
        UserDefaults.standard.removeObject(forKey: key)
        return date
    }
}

/// Secondary alarm button "Ich bin wach": opens the app and notes the wake-up moment.
struct CompanionWakeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ich bin wach"
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        PendingWake.markNow()
        return .result()
    }
}

// MARK: - AlarmKit (iOS 26+)

@available(iOS 26.0, *)
struct CompanionAlarmMetadata: AlarmMetadata {}

/// Main actor: works whether or not `AlarmManager` itself is isolated; the configuration is created locally
/// and handed over once (region-based isolation).
@available(iOS 26.0, *)
@MainActor
enum CompanionAlarmKit {
    static func requestAuthorization() async -> Bool {
        let state = AlarmManager.shared.authorizationState
        if state == .authorized { return true }
        if state == .denied { return false }
        let requested = try? await AlarmManager.shared.requestAuthorization()
        return requested == .authorized
    }

    /// One relative alarm (follows the device time zone), weekly on `weekdays` or once when empty.
    static func schedule(hour: Int, minute: Int, weekdays: [Int]) async throws -> String {
        let awake = AlarmButton(text: "Ich bin wach", textColor: Palette.obsidian, systemImageName: "sun.max")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "Guten Morgen", secondaryButton: awake,
                                            secondaryButtonBehavior: .custom)
        } else {
            let stop = AlarmButton(text: "Stopp", textColor: Palette.ink, systemImageName: "stop.fill")
            alert = AlarmPresentation.Alert(title: "Guten Morgen", stopButton: stop, secondaryButton: awake,
                                            secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes<CompanionAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                                 metadata: CompanionAlarmMetadata(),
                                                                 tintColor: Palette.bioCyan)
        let days = weekdays.compactMap(AlarmScheduleMath.localeWeekday)
        let recurrence: Alarm.Schedule.Relative.Recurrence = days.isEmpty ? .never : .weekly(days)
        let time = Alarm.Schedule.Relative.Time(hour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59))
        let schedule = Alarm.Schedule.relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
        let configuration = AlarmManager.AlarmConfiguration<CompanionAlarmMetadata>.alarm(
            schedule: schedule, attributes: attributes, secondaryIntent: CompanionWakeIntent(),
            sound: .named(AlarmScheduler.soundName))
        let id = UUID()
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        return id.uuidString
    }

    static func cancel(ids: [String]) {
        for id in ids.compactMap(UUID.init(uuidString:)) {
            try? AlarmManager.shared.cancel(id: id)
        }
    }
}

// MARK: - Notifications (fallback below iOS 26, shared with nudges)

/// All UserNotifications calls in one nonisolated place; only Sendable values cross in or out.
enum CompanionNotifications {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    static func scheduleAlarm(hour: Int, minute: Int, weekdays: [Int]) async throws -> [String] {
        let center = UNUserNotificationCenter.current()
        let targets: [Int?] = weekdays.isEmpty ? [nil] : weekdays.map { Optional($0) }
        var ids: [String] = []
        for weekday in targets {
            let content = UNMutableNotificationContent()
            content.title = "Guten Morgen"
            content.body = "Dein Morgenbericht ist bereit. Tippe, um den Begleiter zu öffnen."
            content.sound = UNNotificationSound(named: UNNotificationSoundName(AlarmScheduler.soundName))
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: AlarmScheduleMath.components(hour: hour, minute: minute, weekday: weekday),
                repeats: weekday != nil)
            let id = AlarmScheduleMath.notificationID(weekday: weekday)
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            ids.append(id)
        }
        return ids
    }

    static func add(id: String, title: String, body: String, components: DateComponents) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Removes `ids` and every pending request whose id starts with `prefix`.
    static func removePending(ids: [String], prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        let all = Array(Set(ids + pending))
        guard !all.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: all)
    }
}
