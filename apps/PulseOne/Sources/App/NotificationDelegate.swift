import Foundation
import UserNotifications

/// Shows the Begleiter's alarm and nudge notifications while the app is open (iOS hides local
/// notifications of the foreground app otherwise) and turns a tap on the fallback alarm into the
/// wake-up flow (`PendingWake`). The training's phase-end notification stays hidden in the foreground:
/// the voice and the screen say it there. "Heute nicht" on a reminder pauses reminders until tomorrow.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        return await MainActor.run { () -> UNNotificationPresentationOptions in
            if id.hasPrefix(TrainingNotifications.prefix) { return [] }
            return id.hasPrefix(AlarmScheduler.notificationPrefix) || id.hasPrefix(NudgeScheduler.prefix)
                ? [.banner, .list, .sound] : []
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        if action == NotificationGate.pauseTodayAction {
            await NotificationGate.pauseToday()
            return
        }
        if id.hasPrefix(TrainingNotifications.prefix) {
            await MainActor.run { TrainingController.shared.reopen() }
            return
        }
        guard id.hasPrefix(AlarmScheduler.notificationPrefix) else { return }
        await MainActor.run { PendingWake.markFromNotificationTap() }
    }
}
