import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct HiddenActivationTests {
    @Test(arguments: [true, false])
    func queuedCycleRevalidatesHiddenOrReplacedConversation(hide: Bool) async throws {
        let manager = TestFixtures.isolatedSessionManager()
        let first = makeSession("first")
        let requested = makeSession("target")
        manager.testSetSessions([first, requested])
        let bridge = SessionActivatorMockBridge(behaviors: [first.id: .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let blocking = Task { await activator.activate(session: first, trigger: .guiSelect, policy: .explicit) }
        await bridge.waitUntilActivationStarts(first.id)
        let queued = Task { await activator.activate(session: requested, trigger: .hotkey, policy: .cycleEligible) }
        await waitForQueuedRequest(activator)
        if hide {
            manager.setSessionHidden(sessionID: requested.id, isHidden: true)
        } else {
            manager.addOrUpdateSession(
                agentSessionID: "replacement", terminalSessionID: requested.id,
                projectPath: "/test", state: .idle, event: "SessionStart"
            )
        }
        await bridge.completeActivation(first.id)
        _ = await blocking.value
        guard case .unavailable = await queued.value else {
            Issue.record("Queued cycle should be invalidated")
            return
        }
        #expect(await bridge.recordedActivationCalls() == [first.id])
        #expect(manager.activationTarget == nil)
        #expect(manager.sessions.count == 2)
    }

    @Test func explicitActivationCanReachHiddenSession() async {
        let manager = TestFixtures.isolatedSessionManager()
        let requested = makeSession("target")
        manager.testSetSessions([requested])
        manager.setSessionHidden(sessionID: requested.id, isHidden: true)
        let bridge = SessionActivatorMockBridge()
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let outcome = await activator.activate(session: requested, trigger: .guiSelect, policy: .explicit)
        guard case let .activated(session) = outcome else {
            Issue.record("Explicit hidden activation should succeed")
            return
        }
        #expect(session.isHidden)
        #expect(await bridge.recordedActivationCalls() == [requested.id])
    }

    @Test func repeatedIneligibleCandidateDoesNotLoop() async {
        let manager = TestFixtures.isolatedSessionManager()
        let requested = makeSession("target")
        manager.testSetSessions([requested])
        manager.setSessionHidden(sessionID: requested.id, isHidden: true)
        let activator = SessionActivator(
            sessionManager: manager, registry: TerminalBridgeRegistry(), presentBeacon: { _, _, _, _ in }
        )
        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey, presentation: .failureOnly, nextSession: { requested }
        )
        guard case .unavailable = outcome else {
            Issue.record("An ineligible candidate should be unavailable")
            return
        }
        #expect(manager.sessions.map(\.id) == [requested.id])
    }

    @Test func bridgeLookupRevalidatesEligibilityBeforeCallingBridge() async {
        let manager = TestFixtures.isolatedSessionManager()
        let requested = makeSession("target")
        manager.testSetSessions([requested])
        let bridge = SessionActivatorMockBridge()
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        do {
            try await TerminalActivation.activate(
                session: requested, trigger: .hotkey, sessionManager: manager, registry: registry,
                revalidate: { session in
                    manager.setSessionHidden(sessionID: session.id, isHidden: true)
                    guard let current = SessionActivationPolicy.cycleEligible.resolve(session, in: manager) else {
                        throw SessionActivationError.invalidated
                    }
                    return current
                }
            )
            Issue.record("Expected late eligibility validation to reject activation")
        } catch {
            #expect(error is SessionActivationError)
        }
        #expect(await bridge.recordedActivationCalls().isEmpty)
    }

    @Test(arguments: [true, false])
    func queuedNotificationCannotActivateAfterHideAndUnhide(lastNotificationShortcut: Bool) async throws {
        let manager = TestFixtures.isolatedSessionManager()
        let first = makeSession("first")
        let requested = makeSession("target")
        manager.testSetSessions([first, requested])
        let target = try #require(manager.makeNotificationTarget(sessionID: requested.id))
        let bridge = SessionActivatorMockBridge(behaviors: [first.id: .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let notifications = NotificationManager(sessionManager: manager, activator: activator, sendRequest: { _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        manager.recordLastNotification(target)
        let blocking = Task { await activator.activate(session: first, trigger: .guiSelect, policy: .explicit) }
        await bridge.waitUntilActivationStarts(first.id)
        let queued = Task {
            if lastNotificationShortcut { await hotkeys.handleGoToLastNotification() } else {
                await notifications.activateNotification(target)
            }
        }
        await waitForQueuedRequest(activator)
        manager.setSessionHidden(sessionID: requested.id, isHidden: true)
        manager.setSessionHidden(sessionID: requested.id, isHidden: false)
        await bridge.completeActivation(first.id)
        _ = await blocking.value
        await queued.value
        #expect(await bridge.recordedActivationCalls() == [first.id])
        #expect(manager.lastNotificationTarget == nil)
        #expect(notifications.pendingClickHandoff == nil)
    }

    @Test(arguments: [true, false])
    func queuedAutomationCannotEscapeSourceInvalidation(restart: Bool) async throws {
        let manager = TestFixtures.isolatedSessionManager()
        let blocker = makeSession("blocker")
        let source = makeSession("source", state: restart ? .idle : .working)
        manager.testSetSessions([blocker, source, makeSession("next")])
        manager.updateFocusedSession(terminalSessionID: source.id)
        let request = try #require(manager.makeAutomaticActivation(restart ? .restart : .advance, sessionID: source.id))
        let bridge = SessionActivatorMockBridge(behaviors: [blocker.id: .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let blocking = Task { await activator.activate(session: blocker, trigger: .guiSelect, policy: .explicit) }
        await bridge.waitUntilActivationStarts(blocker.id)
        let automatic = Task {
            await hotkeys.handleAutomaticActivation(request)
        }
        await waitForQueuedRequest(activator)
        manager.setSessionHidden(sessionID: source.id, isHidden: true)
        manager.setSessionHidden(sessionID: source.id, isHidden: false)
        await bridge.completeActivation(blocker.id)
        _ = await blocking.value
        await automatic.value
        #expect(await bridge.recordedActivationCalls() == [blocker.id])
        #expect(manager.focusedSessionID == source.id)
    }

    private func waitForQueuedRequest(_ activator: SessionActivator) async {
        for _ in 0 ..< 1000 {
            if activator.queuedActivationCount == 1 { return }
            await Task.yield()
        }
        Issue.record("Activation did not enter the serialized queue")
    }
}
