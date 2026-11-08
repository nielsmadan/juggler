import Foundation
@testable import Juggler
import Testing

private actor AutomaticBridgeLookupGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var lookupCount = 0

    func pauseOnce() async {
        lookupCount += 1
        guard lookupCount == 1 else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    func waitUntilLookupStarts() async {
        guard lookupCount == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class AutomaticRequestRecorder {
    var requests: [SessionAutomaticActivation] = []

    func observe(_ name: Notification.Name) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [self] notification in
            guard let request = notification.userInfo?["request"] as? SessionAutomaticActivation else { return }
            MainActor.assumeIsolated { requests.append(request) }
        }
    }
}

@Suite(.serialized)
@MainActor
struct AutomaticActivationRaceTests {
    private enum Invalidation: CaseIterable {
        case idle
        case backburner
        case stateRoundTrip
        case focus
        case focusRoundTrip
        case anchor
        case anchorRoundTrip
        case hideRoundTrip
        case replacement
    }

    private enum CompletionInvalidation: CaseIterable {
        case reset
        case replacement
        case recreation
        case clearedFocus
        case hiddenRoundTrip
        case newerAnchor
        case newerAnchorThenExpectedFocus
        case newerLifetime
    }

    @Test(arguments: CompletionInvalidation.allCases)
    private func completedBridgeCannotRestoreObsoleteFocus(invalidation: CompletionInvalidation) async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("source"), makeSession("target"), makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let bridge = SessionActivatorMockBridge(behaviors: ["target": .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let request = try emittedAdvance(manager)
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await bridge.waitUntilActivationStarts("target")
        #expect(manager.activationTarget == "target")
        invalidateCompletion(invalidation, manager: manager)
        let sessions = manager.sessions
        let focus = manager.focusedSessionID
        let anchor = manager.lastActiveSessionID
        let expectedActivationTarget = invalidation == .newerLifetime ? "other" : nil
        await bridge.completeActivation("target")
        await automatic.value
        #expect(await bridge.recordedActivationCalls() == ["target"])
        #expect(manager.sessions == sessions)
        #expect(manager.focusedSessionID == focus)
        #expect(manager.lastActiveSessionID == anchor)
        #expect(manager.activationTarget == expectedActivationTarget)
        manager.endActivation()
    }

    @Test func expectedTerminalFocusDuringTheBridgePreservesActivationOwnership() async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("source"), makeSession("target"), makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let bridge = SessionActivatorMockBridge(behaviors: ["target": .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let request = try emittedAdvance(manager)
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await bridge.waitUntilActivationStarts("target")
        manager.isTerminalAppActive = true
        manager.updateFocusedSession(terminalSessionID: "target", focusTerminalType: .iterm2)
        #expect(manager.focusedSessionID == "target")
        #expect(manager.activationTarget == "target")
        await bridge.completeActivation("target")
        await automatic.value
        #expect(await bridge.recordedActivationCalls() == ["target"])
        #expect(manager.focusedSessionID == "target")
        #expect(manager.lastActiveSessionID == nil)
        #expect(manager.activationTarget == nil)
    }

    @Test(arguments: Invalidation.allCases)
    private func queuedAutoNextRejectsInvalidatedAuthorizingContext(invalidation: Invalidation) async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        let blocker = makeSession("blocker", state: .working)
        manager.testSetSessions([blocker, makeSession("source"), makeSession("target"), makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let bridge = SessionActivatorMockBridge(behaviors: [blocker.id: .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let blocking = Task { await activator.activate(session: blocker, trigger: .guiSelect, policy: .explicit) }
        await bridge.waitUntilActivationStarts(blocker.id)
        let request = try emittedAdvance(manager)
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await waitForQueuedRequest(activator)
        invalidate(invalidation, manager: manager)
        #expect(manager.isValidAutomaticActivation(request) == false)
        let focus = manager.focusedSessionID
        let cursor = manager.cyclingState
        let color = manager.activeColorIndex
        await bridge.completeActivation(blocker.id)
        _ = await blocking.value
        await automatic.value
        #expect(await bridge.recordedActivationCalls() == [blocker.id])
        #expect(manager.focusedSessionID == focus)
        #expect(manager.cyclingState == cursor)
        #expect(manager.activeColorIndex == color)
    }

    @Test func validQueuedAutoNextActivatesAndTracksTheSelectedRow() async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        let blocker = makeSession("blocker", state: .working)
        manager.testSetSessions([blocker, makeSession("source"), makeSession("target"), makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let bridge = SessionActivatorMockBridge(behaviors: [blocker.id: .suspends])
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let blocking = Task { await activator.activate(session: blocker, trigger: .guiSelect, policy: .explicit) }
        await bridge.waitUntilActivationStarts(blocker.id)
        let request = try emittedAdvance(manager)
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await waitForQueuedRequest(activator)
        await bridge.completeActivation(blocker.id)
        _ = await blocking.value
        await automatic.value
        #expect(await bridge.recordedActivationCalls() == [blocker.id, "target"])
        #expect(manager.focusedSessionID == "target")
        #expect(manager.activeColorIndex == 1)
    }

    @Test(arguments: Invalidation.allCases)
    private func autoNextRevalidatesSourceAfterBridgeLookup(invalidation: Invalidation) async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("source"), makeSession("target"), makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let gate = AutomaticBridgeLookupGate()
        let registry = TerminalBridgeRegistry(beforeLookup: { await gate.pauseOnce() })
        let bridge = SessionActivatorMockBridge()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let request = try emittedAdvance(manager)
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await gate.waitUntilLookupStarts()
        #expect(manager.focusedSessionID == "source")
        #expect(manager.activationTarget == nil)
        invalidate(invalidation, manager: manager)
        let focus = manager.focusedSessionID
        let cursor = manager.cyclingState
        let color = manager.activeColorIndex
        await gate.release()
        await automatic.value
        #expect(await bridge.recordedActivationCalls().isEmpty)
        #expect(await gate.lookupCount == 1)
        #expect(manager.focusedSessionID == focus)
        #expect(manager.cyclingState == cursor)
        #expect(manager.activeColorIndex == color)
        #expect(manager.activationTarget == nil)
    }

    @Test(arguments: ["hide", "replacement", "state"])
    func autoNextRejectsInvalidatedCandidateWithoutRetrying(invalidation: String) async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("source"), makeSession("target"), makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let gate = AutomaticBridgeLookupGate()
        let registry = TerminalBridgeRegistry(beforeLookup: { await gate.pauseOnce() })
        let bridge = SessionActivatorMockBridge()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let request = try emittedAdvance(manager)
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await gate.waitUntilLookupStarts()
        switch invalidation {
        case "hide":
            manager.setSessionHidden(sessionID: "target", isHidden: true)
            manager.setSessionHidden(sessionID: "target", isHidden: false)
        case "replacement":
            manager.addOrUpdateSession(
                agentSessionID: "replacement", terminalSessionID: "target", projectPath: "/test",
                state: .idle, event: "SessionStart"
            )
        default:
            manager.updateSessionState(terminalSessionID: "target", state: .working)
            manager.updateSessionState(terminalSessionID: "target", state: .idle)
        }
        #expect(manager.isValidAutomaticActivation(request))
        #expect(manager.sessions.first { $0.id == "target" }?.isCycleEligible == true)
        await gate.release()
        await automatic.value
        #expect(await bridge.recordedActivationCalls().isEmpty)
        #expect(await gate.lookupCount == 1)
        #expect(manager.focusedSessionID == "source")
        #expect(manager.cyclingState == .initial)
        #expect(manager.activeColorIndex == 0)
    }

    @Test func autoRestartCannotBeRevivedByHideUnhideDuringLookup() async throws {
        let restore = configureAutomation()
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("source", state: .working), makeSession("other", state: .working)])
        manager.updateFocusedSession(terminalSessionID: "other")
        let recorder = AutomaticRequestRecorder()
        let observer = recorder.observe(.shouldAutoRestart)
        defer { NotificationCenter.default.removeObserver(observer) }
        manager.updateSessionState(terminalSessionID: "source", state: .idle)
        let request = try #require(recorder.requests.first)
        let gate = AutomaticBridgeLookupGate()
        let registry = TerminalBridgeRegistry(beforeLookup: { await gate.pauseOnce() })
        let bridge = SessionActivatorMockBridge()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let automatic = Task { await hotkeys.handleAutomaticActivation(request) }
        await gate.waitUntilLookupStarts()
        manager.setSessionHidden(sessionID: "source", isHidden: true)
        manager.setSessionHidden(sessionID: "source", isHidden: false)
        await gate.release()
        await automatic.value
        #expect(await bridge.recordedActivationCalls().isEmpty)
        #expect(await gate.lookupCount == 1)
        #expect(manager.focusedSessionID == "other")
    }

    @Test func staleCandidateSnapshotTerminatesTheAutomaticRequest() async throws {
        let restore = configureAutomation()
        defer { restore() }
        let manager = TestFixtures.isolatedSessionManager()
        let target = makeSession("target")
        manager.testSetSessions([makeSession("source"), target, makeSession("other")])
        manager.updateFocusedSession(terminalSessionID: "source")
        let request = try emittedAdvance(manager)
        manager.setSessionHidden(sessionID: target.id, isHidden: true)
        manager.setSessionHidden(sessionID: target.id, isHidden: false)
        let bridge = SessionActivatorMockBridge()
        let registry = TerminalBridgeRegistry()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        var selections = 0
        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey, presentation: .failureOnly, automaticRequest: request,
            nextSession: {
                selections += 1
                return selections == 1 ? target : manager.sessions.first { $0.id == "other" }
            }
        )
        guard case .unavailable = outcome else {
            Issue.record("Invalidated candidate should terminate the automatic request")
            return
        }
        #expect(selections == 1)
        #expect(await bridge.recordedActivationCalls().isEmpty)
        #expect(manager.focusedSessionID == "source")
    }

    private func emittedAdvance(_ manager: SessionManager) throws -> SessionAutomaticActivation {
        let recorder = AutomaticRequestRecorder()
        let observer = recorder.observe(.shouldAutoAdvance)
        defer { NotificationCenter.default.removeObserver(observer) }
        manager.updateSessionState(terminalSessionID: "source", state: .working)
        return try #require(recorder.requests.first)
    }

    private func invalidateCompletion(_ invalidation: CompletionInvalidation, manager: SessionManager) {
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        switch invalidation {
        case .reset:
            manager.completeSessionReset()
        case .replacement, .recreation:
            if invalidation == .recreation { manager.removeSession(sessionID: "target") }
            manager.addOrUpdateSession(
                agentSessionID: invalidation == .replacement ? "replacement" : "target",
                terminalSessionID: "target", projectPath: "/test", state: .idle, event: "SessionStart"
            )
            manager.updateFocusedSession(terminalSessionID: "other")
            manager.updateSessionState(terminalSessionID: "other", state: .working)
            #expect(manager.focusedSessionID == "other")
            #expect(manager.lastActiveSessionID == "other")
        case .clearedFocus:
            manager.updateFocusedSession(terminalSessionID: nil)
        case .hiddenRoundTrip:
            manager.setSessionHidden(sessionID: "target", isHidden: true)
            manager.setSessionHidden(sessionID: "target", isHidden: false)
        case .newerAnchor, .newerAnchorThenExpectedFocus:
            manager.updateSessionState(terminalSessionID: "source", state: .idle)
            manager.updateSessionState(terminalSessionID: "source", state: .working)
            #expect(manager.lastActiveSessionID == "source")
            if invalidation == .newerAnchorThenExpectedFocus {
                manager.updateFocusedSession(terminalSessionID: "target")
                #expect(manager.focusedSessionID == "target")
            }
        case .newerLifetime:
            manager.beginActivation(targetSessionID: "other")
            manager.updateFocusedSession(terminalSessionID: "other")
            manager.updateSessionState(terminalSessionID: "other", state: .working)
            #expect(manager.lastActiveSessionID == "other")
        }
    }

    private func invalidate(_ invalidation: Invalidation, manager: SessionManager) {
        switch invalidation {
        case .idle:
            manager.updateSessionState(terminalSessionID: "source", state: .idle)
        case .backburner:
            manager.backburnerSession(terminalSessionID: "source")
        case .stateRoundTrip:
            manager.updateSessionState(terminalSessionID: "source", state: .idle)
            manager.updateSessionState(terminalSessionID: "source", state: .working)
        case .focus:
            manager.updateFocusedSession(terminalSessionID: "other")
        case .focusRoundTrip:
            manager.updateFocusedSession(terminalSessionID: "other")
            manager.updateFocusedSession(terminalSessionID: "source")
        case .anchor:
            manager.testSetLastActiveSessionID("other")
        case .anchorRoundTrip:
            manager.testSetLastActiveSessionID("other")
            manager.testSetLastActiveSessionID(nil)
        case .hideRoundTrip:
            manager.setSessionHidden(sessionID: "source", isHidden: true)
            manager.setSessionHidden(sessionID: "source", isHidden: false)
        case .replacement:
            manager.addOrUpdateSession(
                agentSessionID: "replacement", terminalSessionID: "source", projectPath: "/test",
                state: .working, event: "UserPromptSubmit"
            )
        }
    }

    private func configureAutomation() -> () -> Void {
        let restore = preserveDefaults(
            AppStorageKeys.autoAdvanceOnBusy, AppStorageKeys.autoRestartOnIdle,
            AppStorageKeys.goToNextOnBackburner, "queueOrderMode"
        )
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoRestartOnIdle)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.goToNextOnBackburner)
        UserDefaults.standard.set("static", forKey: "queueOrderMode")
        return restore
    }

    private func waitForQueuedRequest(_ activator: SessionActivator) async {
        for _ in 0 ..< 1000 {
            if activator.queuedActivationCount == 1 { return }
            await Task.yield()
        }
        Issue.record("Automatic activation did not enter the serialized queue")
    }
}
