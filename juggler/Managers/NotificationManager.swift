import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// True while handling a notification click, so the app delegate can
    /// activate the terminal once macOS finishes its notification activation.
    private(set) var isHandlingNotificationClick = false

    /// The terminal bundle ID to activate after notification click.
    private(set) var pendingTerminalBundleID: String?

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                Task { await MainActor.run { logError(.session, "Notification permission error: \(error)") } }
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

        // Only record the session ID once the system confirms delivery, so the
        // "go to last notification" hotkey can't jump to a banner the user never saw.
        UNUserNotificationCenter.current().add(request) { error in
            guard error == nil else { return }
            Task { @MainActor in
                SessionManager.shared.recordLastNotification(sessionID: sessionID)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Notification click activation on macOS
    // ──────────────────────────────────────
    // macOS always brings the posting app to the foreground when a notification
    // banner is clicked. This is system-level behavior with no opt-out API.
    // The activation happens in two phases: once before didReceive, and once
    // after completionHandler(). We work with this by setting a flag here and
    // letting windowDidBecomeKey in AppDelegate detect it. After the system's
    // activation settles, we yield focus and activate the terminal so the user
    // lands in the right place. There will be a brief flash of Juggler — this
    // is a platform limitation, not a bug.
    // See: FB13131879 (NSApp.yield API request), WWDC23 cooperative activation.
    // See also: docs/tech/overview.md "Known Platform Limitations".

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let sessionID = userInfo["sessionID"] as? String {
            Task { @MainActor in
                guard let session = SessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }

                isHandlingNotificationClick = true
                pendingTerminalBundleID = session.terminalType.bundleIdentifier

                SessionManager.shared.beginActivation(targetSessionID: session.id)
                try? await TerminalActivation.activate(session: session, trigger: .notification)
                SessionManager.shared.endActivation()
                isHandlingNotificationClick = false
                pendingTerminalBundleID = nil
            }
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
