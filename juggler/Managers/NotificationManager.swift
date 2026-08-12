import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    struct ClickHandoff: Equatable {
        fileprivate let id = UUID()
        let terminalBundleID: String
    }

    static let shared = NotificationManager()

    private var clickHandoff: ClickHandoff?

    /// True while handling a notification click, so the app delegate can
    /// activate the terminal once macOS finishes its notification activation.
    var isHandlingNotificationClick: Bool {
        clickHandoff != nil
    }

    /// The terminal bundle ID to activate after notification click.
    var pendingTerminalBundleID: String? {
        clickHandoff?.terminalBundleID
    }

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func beginClickHandoff(terminalBundleID: String) -> ClickHandoff {
        let handoff = ClickHandoff(terminalBundleID: terminalBundleID)
        clickHandoff = handoff
        return handoff
    }

    func endClickHandoff(_ handoff: ClickHandoff) {
        guard clickHandoff == handoff else { return }
        clickHandoff = nil
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

    /// System-level notification with no associated session. The click handler in
    /// userNotificationCenter(_:didReceive:withCompletionHandler:) only acts when
    /// userInfo carries a sessionID, so these banners are inert on click.
    func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

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

    // macOS force-foregrounds the posting app on banner click with no opt-out (FB13131879), so the flag
    // set here lets windowDidBecomeKey hand focus back. See docs/tech/overview.md "Known Platform Limitations".

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let sessionID = userInfo["sessionID"] as? String {
            Task { @MainActor in
                guard let session = SessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }

                let handoff = beginClickHandoff(terminalBundleID: session.terminalType.bundleIdentifier)
                defer { endClickHandoff(handoff) }

                _ = await SessionActivator.shared.activate(session: session, trigger: .notification)
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
