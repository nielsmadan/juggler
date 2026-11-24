import Foundation
@testable import Juggler
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct SessionInteractionSpecifications {}

enum InteractionDirection: CaseIterable { case forward, backward }
enum InteractionOutside: CaseIterable { case otherApp, monitor, untrackedPane }
enum InteractionRemoval: CaseIterable { case hide, backburner }
enum InteractionSource { case hud, global, monitor }
enum InteractionHistory: CaseIterable { case none, unhide, unprioritize, unbackburner }
enum InteractionEmptyAction: CaseIterable { case cycleForward, cycleBackward, hudHide, hudBackburner, globalBackburner }

@MainActor
final class InteractionFixture {
    private let manager: SessionManager
    private let monitor = SessionListController()
    private let registry: TerminalBridgeRegistry
    private let activationGate: InteractionActivationGate?
    private let effects = InteractionEffects()
    private let restoreDefaults: () -> Void
    private var observers: [NSObjectProtocol] = []
    private var requests: [SessionAutomaticActivation] = []
    private var terminalFrontmost = false
    private var registeredBridge = false
    private let mode: QueueOrderMode

    private lazy var activator = SessionActivator(
        sessionManager: manager, registry: registry,
        presentBeacon: { [effects] title, _, _, _ in effects.beacons.append(title) }
    )
    private lazy var hotkeys = HotkeyManager(
        sessionManager: manager, activator: activator,
        showBeacon: { [effects] in effects.beacons.append($0) }
    )

    init(
        _ names: [String], autoAdvance: Bool = false, autoReactivate: Bool = false,
        backburnerAdvances: Bool = true, prioMode: Bool = false, pauseActivation: Bool = false
    ) throws {
        let gate = pauseActivation ? InteractionActivationGate() : nil
        activationGate = gate
        registry = TerminalBridgeRegistry(beforeLookup: { await gate?.pause() })
        restoreDefaults = try preservePersistentDefaults(
            AppStorageKeys.queueOrderMode, AppStorageKeys.autoAdvanceOnBusy,
            AppStorageKeys.autoRestartOnIdle, AppStorageKeys.goToNextOnBackburner,
            AppStorageKeys.prioritizePermissionSessions
        )
        mode = prioMode ? .prio : .fair
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(autoAdvance, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(autoReactivate, forKey: AppStorageKeys.autoRestartOnIdle)
        UserDefaults.standard.set(backburnerAdvances, forKey: AppStorageKeys.goToNextOnBackburner)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.prioritizePermissionSessions)
        manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions(names.map { makeSession($0) })
        manager.frontmostTerminalTypeProvider = { [weak self] in self?.terminalFrontmost == true ? .iterm2 : nil }
        observers = [Notification.Name.shouldAutoAdvance, .shouldAutoRestart].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let request = note.userInfo?["request"] as? SessionAutomaticActivation else { return }
                MainActor.assumeIsolated {
                    guard let self, self.manager.sessions.contains(where: {
                        $0.automationToken == request.sourceToken
                    }) else { return }
                    self.requests.append(request)
                }
            }
        }
    }

    var queue: [String] { manager.cyclableSessions.map(\.id) }
    var activations: [String] { effects.activations }
    var beacons: [String] { effects.beacons }
    var selectedMonitorSession: String? { monitor.selectedSessionID }
    var focusedSession: String? { manager.focusedTrackedSession?.id }
    var pendingAutomationCount: Int { requests.count }

    func close() {
        activationGate?.release()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        restoreDefaults()
    }

    func focus(_ name: String) {
        terminalFrontmost = true
        manager.isTerminalAppActive = true
        manager.updateFocusedSession(terminalSessionID: name, focusTerminalType: .iterm2)
    }

    func leave(_ outside: InteractionOutside) {
        terminalFrontmost = outside == .untrackedPane
        manager.isTerminalAppActive = terminalFrontmost
        if outside == .untrackedPane {
            manager.updateFocusedSession(terminalSessionID: "untracked", focusTerminalType: .iterm2)
        }
    }

    func cycle(_ direction: InteractionDirection) async throws {
        await registerBridge()
        let wasTerminalFrontmost = terminalFrontmost
        let outcome = await activator.activateFirstAvailable(trigger: .hotkey, presentation: .cycle) {
            switch direction {
            case .forward: self.manager.cycleForward(wasTerminalFrontmost: wasTerminalFrontmost)
            case .backward: self.manager.cycleBackward(wasTerminalFrontmost: wasTerminalFrontmost)
            }
        }
        try checkActivation(outcome)
    }

    func remove(_ name: String, using removal: InteractionRemoval, from source: InteractionSource) async throws {
        await registerBridge()
        switch source {
        case .monitor:
            monitor.selectedSessionID = name
            switch removal {
            case .hide: monitor.toggleHidden(sessionID: name, sessionManager: manager)
            case .backburner: monitor.backburnerSelected(sessionManager: manager)
            }
        case .hud:
            let menu = try makeMenu(name)
            let action: SessionRowAction = switch removal {
            case .hide: .hide
            case .backburner:
                try #require(
                    SessionMenuController.actions.first { $0.rawValue == "backburner" },
                    "The Session Menu needs an executable Backburner action"
                )
            }
            try await performMenuAction(action, on: menu)
        case .global:
            try #require(removal == .backburner, "Only Backburner has a global removal shortcut")
            try #require(manager.focusedCommandSession?.id == name)
            await hotkeys.handleBackburner()
        }
        await deliverPendingAutomation()
    }

    func priority(_ name: String, _ value: Bool) {
        manager.setSessionPrioritized(sessionID: name, isPrioritized: value)
    }

    func setPriority(_ name: String, _ value: Bool, from source: InteractionSource) async throws {
        try #require(isPrioritized(name) != value)
        switch source {
        case .monitor:
            try #require(focusedSession == nil, "Open the monitor before changing priority")
            monitor.togglePrioritized(sessionID: name, mode: mode, sessionManager: manager)
        case .hud:
            try await performMenuAction(.prio, on: makeMenu(name))
        case .global:
            Issue.record("There is no global priority shortcut")
        }
        await deliverPendingAutomation()
    }

    func unhide(_ name: String) throws {
        try #require(isHidden(name))
        manager.showsHiddenSessions = true
        monitor.toggleHidden(sessionID: name, sessionManager: manager)
    }

    func selectMonitorRow(_ name: String) {
        monitor.selectListedSession(matching: name, in: manager.listedSessions, syncColor: false)
    }

    func restore(_ name: String) throws {
        try #require(state(name) == .backburner)
        monitor.selectedSessionID = name
        monitor.reactivateSelected(sessionManager: manager)
    }

    func isPrioritized(_ name: String) -> Bool {
        manager.sessions.first { $0.id == name }?.isPrioritized == true
    }

    func isHidden(_ name: String) -> Bool {
        manager.sessions.first { $0.id == name }?.isHidden == true
    }

    func state(_ name: String) -> SessionState? {
        manager.sessions.first { $0.id == name }?.state
    }

    func setBusy(_ name: String, compacting: Bool = false) {
        manager.updateSessionState(
            terminalSessionID: name, state: compacting ? .compacting : .working,
            allowsAutomation: false
        )
    }

    func startWork(_ name: String) throws { try receiveEvent("UserPromptSubmit", for: name) }

    func startCompaction(_ name: String) throws { try receiveEvent("PreCompact", for: name) }

    func startBackgroundTool(_ name: String) throws { try receiveEvent("PreToolUse", for: name) }

    func finishWork(_ name: String) throws { try receiveEvent("Stop", for: name) }

    func addWaitingSession(_ name: String) throws {
        try #require(manager.sessions.allSatisfy { $0.id != name })
        try receiveEvent("SessionStart", for: name)
    }

    private func receiveEvent(_ event: String, for name: String) throws {
        guard case let .updateState(state) = HookEventMapper.map(event: event) else {
            Issue.record("Expected a state-changing hook: \(event)")
            return
        }
        try #require(manager.addOrUpdateSession(
            agentSessionID: name, terminalSessionID: name, projectPath: "/test/\(name)",
            state: state, event: event, source: .live
        ))
    }

    func sendToBack(_ name: String) async throws {
        await registerBridge()
        try #require(manager.focusedCommandSession?.id == name)
        await hotkeys.handleSendToBack()
    }

    func deliverPendingAutomation() async {
        await registerBridge()
        let pending = requests
        requests.removeAll()
        for request in pending {
            await hotkeys.handleAutomaticActivation(request)
        }
    }

    func performEmptyAction(_ action: InteractionEmptyAction) async throws {
        switch action {
        case .cycleForward, .cycleBackward:
            setBusy("A")
            try await cycle(action == .cycleForward ? .forward : .backward)
        case .hudHide: try await remove("A", using: .hide, from: .hud)
        case .hudBackburner: try await remove("A", using: .backburner, from: .hud)
        case .globalBackburner: try await remove("A", using: .backburner, from: .global)
        }
    }

    func waitForActivationLookup() async -> Bool {
        guard let activationGate else { return false }
        return await activationGate.waitUntilEntered()
    }

    func finishActivationLookup() { activationGate?.finishEntry() }

    func releaseActivationLookup() { activationGate?.release() }

    func establishEquivalentState(_ history: InteractionHistory) async throws {
        leave(.monitor)
        switch history {
        case .none: break
        case .unhide:
            try await remove("B", using: .hide, from: .monitor)
            try #require(isHidden("B"))
            try #require(queue == ["A", "C"])
            try unhide("B")
            #expect(isHidden("B") == false)
        case .unprioritize:
            priority("A", true)
            try #require(isPrioritized("A"))
            priority("A", false)
            #expect(isPrioritized("A") == false)
        case .unbackburner:
            try await remove("C", using: .backburner, from: .monitor)
            try #require(state("C") == .backburner)
            try #require(queue == ["A", "B"])
            try restore("C")
            #expect(state("C") == .idle)
        }
    }

    private lazy var hud = SessionMenuManager(
        sessionManager: manager, queueOrderMode: { [mode] in mode }, activator: activator,
        showBeacon: { [effects] in effects.beacons.append($0) }, presentationHandler: { _ in }
    )

    private func performMenuAction(_ action: SessionRowAction, on menu: SessionMenuController) async throws {
        try #require(SessionMenuController.actions.contains(action))
        try #require(menu.isAvailable(action))
        menu.perform(action)
        await menu.pendingActivation?.value
    }

    private func makeMenu(_ name: String) throws -> SessionMenuController {
        try #require(manager.focusedTrackedSession?.id == name)
        hud.toggleForFocusedSession()
        let menu = try #require(hud.controller)
        try #require(menu.target.id == name)
        return menu
    }

    private func registerBridge() async {
        guard !registeredBridge else { return }
        await registry.register(
            InteractionTerminal(effects: effects, focus: { [weak self] in self?.focus($0) }),
            for: .iterm2
        )
        registeredBridge = true
    }

    private func checkActivation(_ outcome: SessionActivationOutcome) throws {
        if case let .failed(error) = outcome { throw error }
    }
}

@MainActor
private final class InteractionActivationGate {
    private let entered = AsyncStream<Void>.makeStream()
    private let released = AsyncStream<Void>.makeStream()

    func pause() async {
        entered.continuation.yield(())
        entered.continuation.finish()
        var iterator = released.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func waitUntilEntered() async -> Bool {
        var iterator = entered.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }

    func finishEntry() { entered.continuation.finish() }

    func release() { released.continuation.finish() }
}

@MainActor
private final class InteractionEffects {
    var activations: [String] = []
    var beacons: [String] = []
}

@MainActor
private final class InteractionTerminal: TerminalBridge {
    let effects: InteractionEffects
    let focus: (String) -> Void

    init(effects: InteractionEffects, focus: @escaping (String) -> Void) {
        self.effects = effects
        self.focus = focus
    }

    func start() async throws {}
    func stop() async {}
    func activate(sessionID: String) async throws {
        await MainActor.run {
            effects.activations.append(sessionID)
            focus(sessionID)
        }
    }

    func highlight(sessionID _: String, tabConfig _: HighlightConfig?, paneConfig _: HighlightConfig?) async throws {}
    func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? { nil }
}
