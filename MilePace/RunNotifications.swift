import UIKit
import UserNotifications

/// Delivers the off-route alert to a locked screen, where a runner will not see
/// an in-app banner. A local notification, because it fires and buzzes with the
/// screen off without a server or special entitlement.
@MainActor
enum RunNotifications {
    /// Asks once for permission. Called when a run starts with a route to
    /// follow, so the prompt only appears for a runner who wants the alerts.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func offRoute() {
        notify(
            title: "Off route",
            body: "You have strayed from the route you are following.",
            identifier: "milepace.offroute"
        )
    }

    /// Removes the off-route notice once the runner is back, so a glance at the
    /// Lock Screen later does not still say they are lost.
    static func clearOffRoute() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["milepace.offroute"])
    }

    private static func notify(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
