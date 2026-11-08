import Foundation
@testable import Juggler
import Testing

@MainActor
private final class AutomaticEventRecorder {
    var names: [Notification.Name] = []
    var sessionIDs: [String] = []
}

@Suite(.serialized)
@MainActor
struct HiddenSessionEligibilityTests {
    @Test(arguments: [SessionState.idle, .permission, .working, .compacting, .backburner])
    func eligibilityCombinesStateAndVisibility(state: SessionState) {
        var session = makeSession("row", state: state)
        #expect(session.isCycleEligible == state.isIncludedInCycle)
        session.disposition.isHidden = true
        #expect(session.isCycleEligible == false)
    }

    @Test(arguments: [true, false])
    func cyclingMovesAwayFromHiddenFocus(forward: Bool) {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("before"), makeSession("hidden"), makeSession("after")])
        manager.updateFocusedSession(terminalSessionID: "hidden")
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        #expect(manager.focusedSessionID == "hidden")
        #expect(manager.cyclableSessions.map(\.id) == ["before", "after"])
        #expect(manager.currentSession?.isCycleEligible == true)
        let target = forward ? manager.cycleForward() : manager.cycleBackward()
        #expect(target?.id == (forward ? "after" : "before"))
    }

    @Test(arguments: [true, false])
    func hiddenFocusIsNotReturnedWhenTerminalIsBackgrounded(forward: Bool) {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden"), makeSession("visible")])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.updateFocusedSession(terminalSessionID: "hidden")
        let target = forward
            ? manager.cycleForward(wasTerminalFrontmost: false)
            : manager.cycleBackward(wasTerminalFrontmost: false)
        #expect(target?.id == "visible")
    }

    @Test func hiddenFocusDoesNotChangeCyclingCursorOrClaimOnlySession() {
        let engine = DefaultCyclingEngine()
        var hidden = makeSession("hidden")
        hidden.disposition.isHidden = true
        let state = CyclingState(currentIndex: 1)
        #expect(engine.syncStateToFocus(
            sessions: [hidden, makeSession("a"), makeSession("b")], focusedSessionID: hidden.id, state: state
        ) == state)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([hidden, makeSession("visible")])
        manager.testSetFocusedSessionID(hidden.id)
        #expect(manager.isFocusedOnOnlyCyclableSession == false)
    }

    @Test func hiddenBusyAnchorDoesNotSupplyCurrentSessionOrReference() {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy)
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden", state: .working), makeSession("visible")])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.testSetLastActiveSessionID("hidden")
        manager.testSetFocusedSessionID("hidden")
        manager.isTerminalAppActive = true
        manager.frontmostTerminalTypeProvider = { .iterm2 }
        #expect(manager.currentSession?.id == "visible")
        #expect(manager.currentCyclableSession?.id == "visible")
        #expect(manager.currentReferenceSessionID == nil)
        #expect(manager.focusedTrackedSession?.id == "hidden")
        #expect(manager.currentCommandSession == nil)
    }

    @Test func allHiddenHasNoCycleOrCurrentTargets() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("a"), makeSession("b", state: .permission)])
        manager.setSessionHidden(sessionID: "a", isHidden: true)
        manager.setSessionHidden(sessionID: "b", isHidden: true)
        #expect(manager.cyclableSessions.isEmpty)
        #expect(manager.currentSession == nil)
        #expect(manager.currentCyclableSession == nil)
        #expect(manager.cycleForward() == nil)
        #expect(manager.cycleBackward() == nil)
    }

    @Test func hiddenFocusTakesPrecedenceOverAnOlderVisibleBusyAnchor() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([
            makeSession("old", state: .working), makeSession("before"),
            makeSession("hidden"), makeSession("after")
        ])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.testSetLastActiveSessionID("old")
        manager.updateFocusedSession(terminalSessionID: "hidden")
        manager.isTerminalAppActive = true
        #expect(manager.currentReferenceSessionID == nil)
        #expect(manager.cycleForward()?.id == "after")
        #expect(manager.lastActiveSessionID == nil)
    }

    @Test func hiddenGlobalCommandsPreserveEveryRowAndFocus() async {
        let restore = preserveDefaults(AppStorageKeys.goToNextOnBackburner, "queueOrderMode")
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.goToNextOnBackburner)
        UserDefaults.standard.set("fair", forKey: "queueOrderMode")
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden"), makeSession("visible")])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.updateFocusedSession(terminalSessionID: "hidden")
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        let before = manager.sessions
        await hotkeys.handleBackburner()
        await hotkeys.handleSendToBack()
        #expect(manager.sessions == before)
        #expect(manager.focusedSessionID == "hidden")
        #expect(await bridge.recordedActivationCalls().isEmpty)
        #expect(manager.sendToBackOfQueue(sessionID: "hidden") == nil)
        #expect(manager.moveSessionToBackOfQueue(sessionID: "hidden") == false)
        #expect(manager.sendToBackOfQueue(sessionID: "visible")?.id == "visible")
    }

    @Test func hiddenWorkingTimeContinuesThroughHideAndUnhide() {
        let manager = TestFixtures.isolatedSessionManager()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var session = makeSession("busy", state: .working)
        session.lastBecameWorking = start
        manager.testSetSessions([session])
        manager.setSessionHidden(sessionID: "busy", isHidden: true)
        #expect(manager.sessions[0].state == .working)
        #expect(manager.sessions[0].lastBecameWorking == start)
        manager.setSessionHidden(sessionID: "busy", isHidden: false)
        manager.setSessionHidden(sessionID: "busy", isHidden: true)
        manager.updateSessionState(terminalSessionID: "busy", state: .idle, now: start.addingTimeInterval(60))
        #expect(manager.sessions[0].busyTimeToday == 60)
        #expect(manager.sessions[0].lastBecameWorking == nil)
    }

    @Test func backburnerGoToNextUsesEligibleRowsBeyondTheBusyAnchor() async {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy, AppStorageKeys.goToNextOnBackburner)
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.goToNextOnBackburner)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden"), makeSession("busy", state: .working), makeSession("ready")])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.updateFocusedSession(terminalSessionID: "busy")
        manager.testSetLastActiveSessionID("busy")
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge()
        await registry.register(bridge, for: .iterm2)
        let activator = SessionActivator(sessionManager: manager, registry: registry, presentBeacon: { _, _, _, _ in })
        let hotkeys = HotkeyManager(sessionManager: manager, activator: activator, showBeacon: { _ in })
        await hotkeys.handleBackburner()
        #expect(manager.sessions.first { $0.id == "busy" }?.state == .backburner)
        #expect(manager.currentCyclableSession?.id == "ready")
        #expect(await bridge.recordedActivationCalls() == ["ready"])
    }

    @Test func hiddenTransitionsDoNotPostAutomationOrDisruptVisibleAnimation() {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy, AppStorageKeys.autoRestartOnIdle)
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden"), makeSession("visible", state: .working)])
        manager.updateFocusedSession(terminalSessionID: "hidden")
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.animationController.animateTransition(sessionID: "visible", from: .idle, to: .working)
        let recorder = AutomaticEventRecorder()
        let tokens = [Notification.Name.shouldAutoAdvance, .shouldAutoRestart].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                let name = notification.name
                MainActor.assumeIsolated { recorder.names.append(name) }
            }
        }
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        manager.updateSessionState(terminalSessionID: "hidden", state: .working)
        manager.updateSessionState(terminalSessionID: "hidden", state: .idle)
        #expect(recorder.names.isEmpty)
        #expect(manager.lastActiveSessionID == nil)
        #expect(manager.animationController.downAnimation?.sessionID == "visible")
        #expect(manager.animationController.upAnimation == nil)
    }

    @Test func autoRestartCountsOnlyVisibleEligibleRows() {
        let restore = preserveDefaults(AppStorageKeys.autoRestartOnIdle)
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden"), makeSession("visible", state: .working)])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        let recorder = AutomaticEventRecorder()
        let token = NotificationCenter.default.addObserver(forName: .shouldAutoRestart, object: nil, queue: nil) {
            if let id = $0.userInfo?["sessionID"] as? String {
                MainActor.assumeIsolated { recorder.sessionIDs.append(id) }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        manager.updateSessionState(terminalSessionID: "visible", state: .idle)
        #expect(recorder.sessionIDs == ["visible"])
    }

    @Test func hiddenAntigravityKeepsAwaitingUserBackburnerWakeSemantics() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.addOrUpdateSession(
            agentSessionID: "conversation", terminalSessionID: "row", agent: "antigravity",
            projectPath: "/test", state: .idle, event: "Stop"
        )
        manager.setSessionHidden(sessionID: "row", isHidden: true)
        manager.backburnerSession(terminalSessionID: "row")
        #expect(manager.sessions[0].wasAwaitingUserBeforeBackburner)
        manager.addOrUpdateSession(
            agentSessionID: "conversation", terminalSessionID: "row", agent: "antigravity",
            projectPath: "/test", state: .working, event: "PreInvocation"
        )
        #expect(manager.sessions[0].state == .working)
        #expect(manager.sessions[0].isHidden)
    }

    @Test(arguments: [true, false])
    func persistedHiddenIdentityCannotKeepAnUnfocusedBusyAnchor(focusedDuringHydration: Bool) {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy, "queueOrderMode")
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set("static", forKey: "queueOrderMode")
        let store = SessionDispositionStore()
        store.setDisposition(
            .init(isHidden: true, backburner: nil),
            for: AgentSessionIdentity(agent: "claude-code", agentSessionID: "stable")
        )
        let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
        var transient = makeSession("transient")
        transient.agentSessionID = ""
        manager.testSetSessions([transient, makeSession("visible"), makeSession("next")])
        manager.updateFocusedSession(terminalSessionID: transient.id)
        manager.updateSessionState(terminalSessionID: transient.id, state: .working)
        #expect(manager.lastActiveSessionID == transient.id)
        if !focusedDuringHydration { manager.updateFocusedSession(terminalSessionID: "visible") }
        manager.addOrUpdateSession(
            agentSessionID: "stable", terminalSessionID: transient.id, projectPath: "/test",
            state: .working, event: "PreToolUse"
        )
        #expect(manager.sessions[0].isHidden)
        #expect(manager.lastActiveSessionID == (focusedDuringHydration ? transient.id : nil))
        manager.updateFocusedSession(terminalSessionID: "visible")
        #expect(manager.lastActiveSessionID == nil)
        #expect(manager.cycleForward()?.id == "next")
    }

    @Test func focusedRowHydratedHiddenRemainsTheCycleOrigin() {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy, "queueOrderMode")
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set("static", forKey: "queueOrderMode")
        let store = SessionDispositionStore()
        store.setDisposition(
            .init(isHidden: true, backburner: nil),
            for: AgentSessionIdentity(agent: "claude-code", agentSessionID: "stable")
        )
        let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
        var transient = makeSession("transient")
        transient.agentSessionID = ""
        manager.testSetSessions([makeSession("before"), transient, makeSession("after")])
        manager.updateFocusedSession(terminalSessionID: transient.id)
        manager.updateSessionState(terminalSessionID: transient.id, state: .working)
        manager.addOrUpdateSession(
            agentSessionID: "stable", terminalSessionID: transient.id, projectPath: "/test",
            state: .working, event: "PreToolUse"
        )
        #expect(manager.focusedSessionID == transient.id)
        #expect(manager.lastActiveSessionID == transient.id)
        #expect(manager.cycleForward()?.id == "after")
    }
}
