import Foundation
import UserNotifications

enum NotificationScheduler {
    static let projectKey = "projectID"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func isDenied() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    /// Throws out every pending reminder and builds them again from the projects. Reminders are
    /// the only notifications this app sends, so starting clean can't remove anything else, and
    /// it can't leave behind a time that was deleted.
    static func sync(_ projects: [Project]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        // No original means nothing to line up with yet, so no reminders.
        for project in projects where project.hasTemplate {
            for (index, components) in project.reminders.triggerComponents().enumerated() {
                let content = UNMutableNotificationContent()
                content.title = project.name
                content.body = "Time for today's photo. Same spot, same angle."
                content.sound = .default
                content.threadIdentifier = project.id.uuidString
                content.userInfo = [projectKey: project.id.uuidString]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(project.id.uuidString)-\(index)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }
}
