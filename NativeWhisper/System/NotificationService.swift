import Foundation
import UserNotifications

protocol Notifying: Sendable {
    func requestAuthorizationIfNeeded() async
    func notify(title: String, body: String)
}

final class NotificationService: Notifying, @unchecked Sendable {
    private let center: UNUserNotificationCenter?

    init(center: UNUserNotificationCenter? = NotificationService.defaultCenter()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async {
        guard let center else {
            return
        }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Notifications are optional for core dictation behavior.
        }
    }

    func notify(title: String, body: String) {
        guard let center else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    private static func defaultCenter() -> UNUserNotificationCenter? {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            return nil
        }
        return .current()
    }
}
