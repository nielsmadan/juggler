import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    typealias RequestSender = @MainActor (UNNotificationRequest, @escaping @MainActor (Bool) -> Void) -> Void

    struct ClickHandoff: Equatable {
        fileprivate let id = UUID()
        let terminalBundleID: String
        let target: SessionNotificationTarget?
    }

    static let shared = NotificationManager()

    private var clickHandoff: ClickHandoff?
    private let sessionManager: SessionManager
    private let sendRequest: RequestSender
    private let activator: SessionActivator

    /// True while handling a notification click, so the app delegate can
    /// activate the terminal once macOS finishes its notification activation.
    var isHandlingNotificationClick: Bool {
        pendingTerminalBundleID != nil
    }

    /// The terminal bundle ID to activate after notification click.
    var pendingTerminalBundleID: String? {
        clickHandoff.flatMap { terminalBundleID(for: $0) }
    }

    var pendingClickHandoff: ClickHandoff? {
        pendingTerminalBundleID == nil ? nil : clickHandoff
    }

    func terminalBundleID(for handoff: ClickHandoff) -> String? {
        if let target = handoff.target, sessionManager.session(for: target) == nil { return nil }
        return handoff.terminalBundleID
    }

    override private init() {
        sessionManager = .shared
        activator = .shared
        sendRequest = Self.deliver
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    init(sessionManager: SessionManager, activator: SessionActivator, sendRequest: @escaping RequestSender) {
        self.sessionManager = sessionManager
        self.activator = activator
        self.sendRequest = sendRequest
        super.init()
    }

    private static func deliver(_ request: UNNotificationRequest, completion: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().add(request) { error in
            let delivered = error == nil
            Task { @MainActor in completion(delivered) }
        }
    }

    func beginClickHandoff(
        terminalBundleID: String,
        target: SessionNotificationTarget? = nil
    ) -> ClickHandoff {
        let handoff = ClickHandoff(terminalBundleID: terminalBundleID, target: target)
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

    func sendNotification(title: String, body: String, target: SessionNotificationTarget) {
        guard sessionManager.session(for: target) != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = target.userInfo

        if UserDefaults.standard.bool(forKey: AppStorageKeys.playSound) {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        sendRequest(request) { [weak self] delivered in
            guard delivered, let self, sessionManager.session(for: target) != nil else { return }
            sessionManager.recordLastNotification(target)
        }
    }

    func activateNotification(_ target: SessionNotificationTarget) async {
        guard let session = sessionManager.session(for: target) else { return }
        let handoff = beginClickHandoff(terminalBundleID: session.terminalType.bundleIdentifier, target: target)
        defer { endClickHandoff(handoff) }
        _ = await activator.activate(session: session, trigger: .notification, policy: .notification(target))
    }

    /// System-level notification with no associated session target.
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

        if let target = SessionNotificationTarget(userInfo: userInfo) {
            Task { @MainActor in
                await activateNotification(target)
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
