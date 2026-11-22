import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct BackburnerActionTests {
    @Test(arguments: [false, true])
    func backburneringLastEligibleSessionShowsFeedback(goToNext: Bool) async {
        let restore = preserveDefaults(AppStorageKeys.goToNextOnBackburner)
        defer { restore() }
        UserDefaults.standard.set(goToNext, forKey: AppStorageKeys.goToNextOnBackburner)
        let fixture = await Fixture.make([makeSession("last"), makeSession("busy", state: .working)])
        fixture.manager.updateFocusedSession(terminalSessionID: "last")

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.manager.sessions.first { $0.id == "last" }?.state == .backburner)
        #expect(fixture.feedback == ["Backburnered"])
        #expect(await fixture.bridge.recordedActivationCalls().isEmpty)
    }

    @Test func backburneringWithJumpDisabledConfirmsWithoutChangingFocus() async {
        let restore = preserveDefaults(AppStorageKeys.goToNextOnBackburner)
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.goToNextOnBackburner)
        let fixture = await Fixture.make([makeSession("first"), makeSession("second")])
        fixture.manager.updateFocusedSession(terminalSessionID: "first")

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.feedback == ["Backburnered"])
        #expect(fixture.manager.focusedSessionID == "first")
        #expect(fixture.manager.cyclableSessions.map(\.id) == ["second"])
        #expect(await fixture.bridge.recordedActivationCalls().isEmpty)
    }

    @Test func backburneringWithStaleNextSessionStillConfirms() async {
        let restore = preserveDefaults(AppStorageKeys.goToNextOnBackburner, AppStorageKeys.queueOrderMode)
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.goToNextOnBackburner)
        UserDefaults.standard.set("fair", forKey: AppStorageKeys.queueOrderMode)
        let fixture = await Fixture.make(
            [makeSession("first"), makeSession("stale")], behaviors: ["stale": .sessionNotFound]
        )
        fixture.manager.updateFocusedSession(terminalSessionID: "first")

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.feedback == ["Backburnered"])
        #expect(fixture.manager.sessions.map(\.state) == [.backburner])
        #expect(await fixture.bridge.recordedActivationCalls() == ["stale"])
    }

    @Test(arguments: QueueOrderMode.allCases)
    func reactivateAllJumpsToFirstEligibleSessionOnce(mode: QueueOrderMode) async {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode, AppStorageKeys.autoRestartOnIdle)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
        let fixture = await Fixture.make([
            makeSession("hidden", state: .backburner), makeSession("first", state: .backburner),
            makeSession("second", state: .backburner), makeSession("busy", state: .working)
        ])
        fixture.manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        let token = NotificationCenter.default.addObserver(forName: .shouldAutoRestart, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { fixture.automaticRestarts += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await fixture.hotkeys.handleReactivateAll()

        #expect(fixture.manager.sessions.filter { $0.id != "busy" }.allSatisfy { $0.state == .idle })
        #expect(fixture.manager.sessions.first { $0.id == "hidden" }?.isHidden == true)
        #expect(fixture.manager.sessions.first { $0.id == "busy" }?.state == .working)
        let expected = mode == .prio ? "second" : "first"
        #expect(await fixture.bridge.recordedActivationCalls() == [expected])
        #expect(fixture.automaticRestarts == 0)
        #expect(fixture.activationFeedback == [expected])
        #expect(fixture.manager.focusedSessionID == expected)
        #expect(fixture.manager.focusedCommandSession?.id == expected)
    }

    @Test func reactivateAllWithNothingShelvedKeepsFocusAndExplains() async {
        let fixture = await Fixture.make([makeSession("ready")])
        fixture.manager.updateFocusedSession(terminalSessionID: "ready")

        await fixture.hotkeys.handleReactivateAll()

        #expect(fixture.feedback == ["No Backburnered Sessions"])
        #expect(fixture.manager.focusedSessionID == "ready")
        #expect(await fixture.bridge.recordedActivationCalls().isEmpty)
    }

    @Test func reactivateAllWithOnlyHiddenSessionsExplainsWithoutActivating() async {
        let fixture = await Fixture.make([makeSession("hidden", state: .backburner)])
        fixture.manager.setSessionHidden(sessionID: "hidden", isHidden: true)

        await fixture.hotkeys.handleReactivateAll()

        #expect(fixture.manager.sessions[0].state == .idle)
        #expect(fixture.manager.sessions[0].isHidden)
        #expect(fixture.activationFeedback == ["No Sessions to Cycle"])
        #expect(await fixture.bridge.recordedActivationCalls().isEmpty)
    }

    @Test func reactivateAllSkipsStaleSessionAndActivatesNext() async {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        UserDefaults.standard.set("fair", forKey: AppStorageKeys.queueOrderMode)
        let fixture = await Fixture.make(
            [makeSession("stale", state: .backburner), makeSession("hidden", state: .backburner),
             makeSession("live", state: .backburner)],
            behaviors: ["stale": .sessionNotFound]
        )
        fixture.manager.setSessionHidden(sessionID: "hidden", isHidden: true)

        await fixture.hotkeys.handleReactivateAll()

        #expect(await fixture.bridge.recordedActivationCalls() == ["stale", "live"])
        #expect(fixture.activationFeedback == ["live"])
        #expect(fixture.manager.focusedSessionID == "live")
        #expect(fixture.manager.focusedCommandSession?.id == "live")
        #expect(fixture.manager.activeColorIndex == 1)
    }

    @Test func reactivateAllReplacesBusyAnchorWithoutTerminalFocusEvents() async {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy)
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        let fixture = await Fixture.make([
            makeSession("busy", state: .working),
            makeSession("ready", state: .backburner)
        ])
        fixture.manager.updateFocusedSession(terminalSessionID: "busy")
        fixture.manager.testSetLastActiveSessionID("busy")

        await fixture.hotkeys.handleReactivateAll()

        #expect(fixture.manager.focusedSessionID == "ready")
        #expect(fixture.manager.focusedCommandSession?.id == "ready")
        #expect(fixture.manager.lastActiveSessionID == nil)
        #expect(await fixture.bridge.recordedActivationCalls() == ["ready"])
    }

    @Test(arguments: [QueueOrderMode.fair, .prio])
    func sendToBackWarnsWhenOnlyOneSessionIsEligible(mode: QueueOrderMode) async {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        let fixture = await Fixture.make([
            makeSession("only"),
            makeSession("busy", state: .working),
            makeSession("hidden")
        ])
        fixture.manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        fixture.manager.updateFocusedSession(terminalSessionID: "only")

        await fixture.hotkeys.handleSendToBack()

        #expect(fixture.activationFeedback == ["Only 1 Session"])
        #expect(await fixture.bridge.recordedActivationCalls() == ["only"])
    }

    @Test func reactivateAllReportsActivationFailure() async {
        let fixture = await Fixture.make([makeSession("failed", state: .backburner)], behaviors: ["failed": .fails])

        await fixture.hotkeys.handleReactivateAll()

        #expect(fixture.manager.sessions[0].state == .idle)
        #expect(fixture.activationFeedback == ["Activation Failed"])
        #expect(await fixture.bridge.recordedActivationCalls() == ["failed"])
    }

    @Test func backburnerWithoutActiveTerminalExplainsAndChangesNothing() async {
        let fixture = await Fixture.make([makeSession("first"), makeSession("second")])
        fixture.manager.updateFocusedSession(terminalSessionID: "first")
        fixture.manager.isTerminalAppActive = false

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.feedback == ["No Active Session"])
        #expect(fixture.manager.sessions.map(\.state) == [.idle, .idle])
        #expect(await fixture.bridge.recordedActivationCalls().isEmpty)
    }

    @Test func backburnerWithUntrackedFocusExplainsAndChangesNothing() async {
        let fixture = await Fixture.make([makeSession("first"), makeSession("second")])
        fixture.manager.updateFocusedSession(terminalSessionID: "untracked")

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.feedback == ["No Active Session"])
        #expect(fixture.manager.sessions.map(\.state) == [.idle, .idle])
        #expect(await fixture.bridge.recordedActivationCalls().isEmpty)
    }

    @Test func sendToBackWithoutActiveTerminalExplainsAndKeepsOrder() async {
        let fixture = await Fixture.make([makeSession("first"), makeSession("second")])
        fixture.manager.updateFocusedSession(terminalSessionID: "first")
        fixture.manager.isTerminalAppActive = false

        await fixture.hotkeys.handleSendToBack()

        #expect(fixture.feedback == ["No Active Session"])
        #expect(fixture.manager.cyclableSessions.map(\.id) == ["first", "second"])
    }

    @Test func backburnerActsOnFocusNotTheBusyAnchor() async {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy, AppStorageKeys.goToNextOnBackburner)
        defer { restore() }
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.goToNextOnBackburner)
        let fixture = await Fixture.make([makeSession("busy", state: .working), makeSession("idle")])
        fixture.manager.testSetLastActiveSessionID("busy")
        fixture.manager.updateFocusedSession(terminalSessionID: "idle")

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.manager.sessions.first { $0.id == "idle" }?.state == .backburner)
        #expect(fixture.manager.sessions.first { $0.id == "busy" }?.state == .working)
    }

    @Test func backburnerActsOnAFocusedWorkingSession() async {
        let restore = preserveDefaults(AppStorageKeys.autoAdvanceOnBusy, AppStorageKeys.goToNextOnBackburner)
        defer { restore() }
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.goToNextOnBackburner)
        let fixture = await Fixture.make([makeSession("working", state: .working), makeSession("idle")])
        fixture.manager.updateFocusedSession(terminalSessionID: "working")

        await fixture.hotkeys.handleBackburner()

        #expect(fixture.manager.sessions.first { $0.id == "working" }?.state == .backburner)
        #expect(fixture.manager.sessions.first { $0.id == "idle" }?.state == .idle)
    }

    @Test func reactivateAllClearsStoredBackburnersWithoutLiveRows() async {
        let fixture = await Fixture.make([makeSession("ready")])
        fixture.manager.updateFocusedSession(terminalSessionID: "ready")
        let identity = AgentSessionIdentity(agent: "codex", agentSessionID: "offline")
        fixture.manager.dispositionStore.setDisposition(
            .init(isHidden: false, backburner: .init(wasAwaitingUser: true, backburneredAt: Date())),
            for: identity
        )

        await fixture.hotkeys.handleReactivateAll()

        #expect(fixture.feedback == ["No Backburnered Sessions"])
        #expect(fixture.manager.dispositionStore.disposition(for: identity) == .empty)
    }

    private final class Fixture {
        let manager: SessionManager
        let bridge: SessionActivatorMockBridge
        var feedback: [String] = []
        var activationFeedback: [String] = []
        var automaticRestarts = 0
        private let registry: TerminalBridgeRegistry
        lazy var hotkeys: HotkeyManager = {
            let activator = SessionActivator(sessionManager: manager,
                                             registry: registry) { [weak self] title, _, _, _ in
                self?.activationFeedback.append(title)
            }
            return HotkeyManager(sessionManager: manager, activator: activator) { [weak self] in
                self?.feedback.append($0)
            }
        }()

        private init(manager: SessionManager, bridge: SessionActivatorMockBridge, registry: TerminalBridgeRegistry) {
            self.manager = manager
            self.bridge = bridge
            self.registry = registry
        }

        static func make(
            _ sessions: [Session], behaviors: [String: SessionActivatorMockBridge.Behavior] = [:]
        ) async -> Fixture {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions(sessions.map { session in
                var session = session
                session.customName = session.id
                return session
            })
            manager.isTerminalAppActive = true
            let registry = TerminalBridgeRegistry()
            let bridge = SessionActivatorMockBridge(behaviors: behaviors)
            await registry.register(bridge, for: .iterm2)
            return Fixture(manager: manager, bridge: bridge, registry: registry)
        }
    }
}
