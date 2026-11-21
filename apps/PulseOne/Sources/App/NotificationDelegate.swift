import Foundation
import UserNotifications

/// Shows the Begleiter's alarm and nudge notifications while the app is open (iOS hides local
/// notifications of the foreground app otherwise) and turns a tap on the fallback alarm into the
/// wake-up flow (`PendingWake`). Other notifications keep the system default.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        return await MainActor.run { () -> UNNotificationPresentationOptions in
            id.hasPrefix(AlarmScheduler.notificationPrefix) || id.hasPrefix(NudgeScheduler.prefix)
                ? [.banner, .list, .sound] : []
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        guard id.hasPrefix(AlarmScheduler.notificationPrefix) else { return }
        await MainActor.run { PendingWake.markFromNotificationTap() }
    }
}
