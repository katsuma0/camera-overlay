import Foundation
import UserNotifications

enum NotificationScheduler {
    static let projectKey = "projectID"

    /// Calls back on the main queue with whether reminders are allowed.
    static func requestAuthorization(then completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
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

        for project in projects {
            for (index, components) in project.reminders.triggerComponents().enumerated() {
                let content = UNMutableNotificationContent()
                content.title = project.name
                // A project without an original still reminds, since tapping opens the camera ready to take it.
                content.body = project.hasTemplate
                    ? "Time for today's photo. Same spot, same angle."
                    : "Time to take the original photo for this spot."
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
