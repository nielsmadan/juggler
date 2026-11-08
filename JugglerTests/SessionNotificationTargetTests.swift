import Foundation
@testable import Juggler
import Testing
import UserNotifications

@MainActor
private final class NotificationDeliveryRecorder {
    var requests: [UNNotificationRequest] = []
    var completions: [@MainActor (Bool) -> Void] = []

    func send(_ request: UNNotificationRequest, completion: @escaping @MainActor (Bool) -> Void) {
        requests.append(request)
        completions.append(completion)
    }
}

@Suite(.serialized)
@MainActor
struct SessionNotificationTargetTests {
    @Test func targetRoundTripsExactIdentityTokenAndSequence() throws {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        #expect(target.identity == manager.sessions[0].agentSessionIdentity)
        #expect(SessionNotificationTarget(userInfo: target.userInfo) == target)
        #expect(SessionNotificationTarget(userInfo: ["sessionID": "row"]) == nil)
        #expect(SessionNotificationTarget(userInfo: ["sessionTarget": "invalid"]) == nil)
    }

    @Test func hidingInvalidatesRecordedAndPendingTargetsPermanently() throws {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.recordLastNotification(target)
        #expect(manager.lastNotifiedSessionID == "row")
        manager.setSessionHidden(sessionID: "row", isHidden: true)
        #expect(manager.makeNotificationTarget(sessionID: "row") == nil)
        #expect(manager.lastNotificationTarget == nil)
        manager.recordLastNotification(target)
        #expect(manager.lastNotificationTarget == nil)
        manager.setSessionHidden(sessionID: "row", isHidden: false)
        manager.recordLastNotification(target)
        #expect(manager.session(for: target) == nil)
        #expect(manager.lastNotificationTarget == nil)
        let fresh = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.recordLastNotification(fresh)
        #expect(manager.lastNotificationTarget == fresh)
    }

    @Test func identityReplacementAndRowRecreationInvalidateTargets() throws {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("row")])
        let original = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.addOrUpdateSession(
            agentSessionID: "replacement", terminalSessionID: "row", projectPath: "/test",
            state: .idle, event: "SessionStart"
        )
        #expect(manager.session(for: original) == nil)
        let replacement = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.removeSession(sessionID: "row")
        manager.addOrUpdateSession(
            agentSessionID: "replacement", terminalSessionID: "row", projectPath: "/test",
            state: .idle, event: "SessionStart"
        )
        #expect(manager.session(for: replacement) == nil)
        let fresh = try #require(manager.makeNotificationTarget(sessionID: "row"))
        #expect(manager.session(for: fresh)?.agentSessionID == "replacement")
    }

    @Test func duplicateConversationRowsInvalidateTogether() throws {
        let manager = TestFixtures.isolatedSessionManager()
        let first = makeSession("first")
        var second = makeSession("second")
        second.agentSessionID = first.agentSessionID
        manager.testSetSessions([first, second])
        let firstTarget = try #require(manager.makeNotificationTarget(sessionID: first.id))
        let secondTarget = try #require(manager.makeNotificationTarget(sessionID: second.id))
        manager.setSessionHidden(sessionID: first.id, isHidden: true)
        manager.setSessionHidden(sessionID: second.id, isHidden: false)
        #expect(manager.session(for: firstTarget) == nil)
        #expect(manager.session(for: secondTarget) == nil)
        #expect(manager.sessions.allSatisfy { !$0.isHidden })
    }

    @Test func transientTargetsAreInvalidatedWhenStableIdentityArrives() throws {
        let manager = TestFixtures.isolatedSessionManager()
        var row = makeSession("row")
        row.agentSessionID = ""
        manager.testSetSessions([row])
        let target = try #require(manager.makeNotificationTarget(sessionID: row.id))
        #expect(target.identity == nil)
        manager.addOrUpdateSession(
            agentSessionID: "stable", terminalSessionID: row.id, projectPath: "/test", state: .idle, event: "Stop"
        )
        #expect(manager.session(for: target) == nil)
        #expect(manager.makeNotificationTarget(sessionID: row.id)?.identity?.agentSessionID == "stable")
    }

    @Test func deliveryCompletionsKeepNewestSequenceAndDoNotResurrectInvalidatedTargets() throws {
        let (manager, notifications, delivery) = makeNotificationManager()
        manager.testSetSessions([makeSession("first"), makeSession("second")])
        let first = try #require(manager.makeNotificationTarget(sessionID: "first"))
        let second = try #require(manager.makeNotificationTarget(sessionID: "second"))
        #expect(second.sequence > first.sequence)
        notifications.sendNotification(title: "Idle", body: "first", target: first)
        notifications.sendNotification(title: "Idle", body: "second", target: second)
        #expect(manager.lastNotificationTarget == nil)
        delivery.completions[1](true)
        delivery.completions[0](true)
        #expect(manager.lastNotificationTarget == second)
        manager.setSessionHidden(sessionID: "second", isHidden: true)
        delivery.completions[0](true)
        #expect(manager.lastNotificationTarget == nil)
        manager.setSessionHidden(sessionID: "second", isHidden: false)
        delivery.completions[1](true)
        #expect(manager.lastNotificationTarget == nil)
    }

    @Test(arguments: [true, false])
    func deliveryCompletionRejectsHideOrPaneReplacement(hide: Bool) throws {
        let (manager, notifications, delivery) = makeNotificationManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        notifications.sendNotification(title: "Idle", body: "row", target: target)
        #expect(delivery.requests.count == 1)
        if hide {
            manager.setSessionHidden(sessionID: "row", isHidden: true)
            manager.setSessionHidden(sessionID: "row", isHidden: false)
        } else {
            manager.addOrUpdateSession(
                agentSessionID: "replacement", terminalSessionID: "row", projectPath: "/test",
                state: .idle, event: "SessionStart"
            )
        }
        delivery.completions[0](true)
        #expect(manager.lastNotificationTarget == nil)
        notifications.sendNotification(title: "Idle", body: "stale", target: target)
        #expect(delivery.requests.count == 1)
    }

    @Test func failedDeliveryDoesNotRecordLastNotification() throws {
        let (manager, notifications, delivery) = makeNotificationManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        notifications.sendNotification(title: "Idle", body: "row", target: target)
        delivery.completions[0](false)
        #expect(manager.lastNotificationTarget == nil)
    }

    @Test func ordinaryStateTransitionsKeepNotificationTargetsValid() throws {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        let originalAutomationToken = manager.sessions[0].automationToken
        manager.updateSessionState(terminalSessionID: "row", state: .working)
        manager.updateSessionState(terminalSessionID: "row", state: .idle)
        #expect(manager.sessions[0].automationToken != originalAutomationToken)
        #expect(manager.session(for: target)?.id == "row")
        manager.recordLastNotification(target)
        #expect(manager.lastNotificationTarget == target)
    }

    @Test func delayedFocusHandoffIsInvalidatedByHideEvenAfterClickCompletion() throws {
        let (manager, notifications, _) = makeNotificationManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        let handoff = notifications.beginClickHandoff(
            terminalBundleID: TerminalType.iterm2.bundleIdentifier, target: target
        )
        #expect(notifications.pendingClickHandoff == handoff)
        notifications.endClickHandoff(handoff)
        #expect(notifications.terminalBundleID(for: handoff) == TerminalType.iterm2.bundleIdentifier)
        manager.setSessionHidden(sessionID: "row", isHidden: true)
        manager.setSessionHidden(sessionID: "row", isHidden: false)
        #expect(notifications.terminalBundleID(for: handoff) == nil)
    }

    @Test(arguments: [true, false])
    func oldBannerAndLastNotificationCannotActivateHiddenOrReusedRow(hide: Bool) async throws {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("row")])
        let bridge = SessionActivatorMockBridge()
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let notifications = NotificationManager(sessionManager: manager, activator: activator, sendRequest: { _, _ in })
        var messages: [String] = []
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { messages.append($0) })
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.recordLastNotification(target)
        if hide {
            manager.setSessionHidden(sessionID: "row", isHidden: true)
            await notifications.activateNotification(target)
            await hotkeys.handleGoToLastNotification()
            manager.setSessionHidden(sessionID: "row", isHidden: false)
        } else {
            manager.addOrUpdateSession(
                agentSessionID: "replacement", terminalSessionID: "row", projectPath: "/test",
                state: .idle, event: "SessionStart"
            )
        }
        await notifications.activateNotification(target)
        await hotkeys.handleGoToLastNotification()
        #expect(await bridge.recordedActivationCalls().isEmpty)
        #expect(messages == (hide ? ["No Notification", "No Notification"] : ["No Notification"]))
        let fresh = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.recordLastNotification(fresh)
        await notifications.activateNotification(fresh)
        await hotkeys.handleGoToLastNotification()
        #expect(await bridge.recordedActivationCalls() == ["row", "row"])
    }

    @Test func hiddenTargetsCannotDispatchThroughDefaultSender() throws {
        let (manager, notifications, delivery) = makeNotificationManager()
        manager.testSetSessions([makeSession("row")])
        let target = try #require(manager.makeNotificationTarget(sessionID: "row"))
        manager.setSessionHidden(sessionID: "row", isHidden: true)
        notifications.sendNotification(title: "Idle", body: "row", target: target)
        #expect(delivery.requests.isEmpty)
    }

    @Test(arguments: [true, false])
    func hookServerSuppressesHiddenNotificationsAtBothBoundaries(injected: Bool) async {
        let restore = preserveDefaults(AppStorageKeys.notifyOnIdle, AppStorageKeys.notifyOnPermission)
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.notifyOnIdle)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.notifyOnPermission)
        let (manager, notifications, delivery) = makeNotificationManager()
        let recorder = NotificationDeliveryRecorder()
        let sink: (@MainActor @Sendable (String, SessionNotificationTarget) -> Void)? = if injected {
            { title, target in
                let content = UNMutableNotificationContent()
                content.title = title
                content.userInfo = target.userInfo
                recorder.requests.append(UNNotificationRequest(identifier: "test", content: content, trigger: nil))
            }
        } else {
            nil
        }
        let server = HookServer(sessionManager: manager, notificationSink: sink, notificationManager: notifications)
        await server.handleStatusForTesting(TestFixtures.statusJSON(
            event: "UserPromptSubmit", phase: "working", terminalSessionID: "row"
        ))
        manager.setSessionHidden(sessionID: "row", isHidden: true)
        await server.handleStatusForTesting(TestFixtures.statusJSON(
            event: "Stop", phase: "idle", terminalSessionID: "row"
        ))
        await server.handleStatusForTesting(TestFixtures.statusJSON(
            event: "PermissionRequest", phase: "permission", terminalSessionID: "row"
        ))
        #expect(recorder.requests.isEmpty)
        #expect(delivery.requests.isEmpty)
        manager.setSessionHidden(sessionID: "row", isHidden: false)
        await server.handleStatusForTesting(TestFixtures.statusJSON(
            event: "Stop", phase: "idle", terminalSessionID: "row"
        ))
        let requests = injected ? recorder.requests : delivery.requests
        #expect(requests.map(\.content.title) == ["Session Idle"])
        await server.stop()
    }

    private func makeNotificationManager() -> (SessionManager, NotificationManager, NotificationDeliveryRecorder) {
        let manager = TestFixtures.isolatedSessionManager()
        let delivery = NotificationDeliveryRecorder()
        let activator = SessionActivator(
            sessionManager: manager, registry: TerminalBridgeRegistry(), presentBeacon: { _, _, _, _ in }
        )
        let notifications = NotificationManager(
            sessionManager: manager,
            activator: activator,
            sendRequest: delivery.send
        )
        return (manager, notifications, delivery)
    }
}
