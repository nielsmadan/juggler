import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func sendNotification(title: String, body: String, sessionID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["sessionID": sessionID]

        if UserDefaults.standard.bool(forKey: AppStorageKeys.playSound) {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let sessionID = userInfo["sessionID"] as? String {
            if let session = SessionManager.shared.sessions.first(where: { $0.id == sessionID }) {
                Task {
                    try? await TerminalActivation.activate(session: session, trigger: .notification)
                }
            }
        }

        completionHandler()
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
