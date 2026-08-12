import Foundation
@testable import Juggler
import Testing

private enum SessionActivatorMockError: Error {
    case failed
}

private actor SessionActivatorMockBridge: TerminalBridge {
    enum Behavior: Sendable {
        case succeeds
        case sessionNotFound
        case fails
        case suspends
    }

    private let behaviors: [String: Behavior]
    private var activationCalls: [String] = []
    private var startedActivations: Set<String> = []
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var activationContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(behaviors: [String: Behavior] = [:]) {
        self.behaviors = behaviors
    }

    func start() async throws {}
    func stop() async {}

    func activate(sessionID: String) async throws {
        activationCalls.append(sessionID)
        startedActivations.insert(sessionID)
        startWaiters.removeValue(forKey: sessionID)?.forEach { $0.resume() }

        switch behaviors[sessionID] ?? .succeeds {
        case .succeeds:
            return
        case .sessionNotFound:
            throw TerminalBridgeError.commandFailed("Session not found")
        case .fails:
            throw SessionActivatorMockError.failed
        case .suspends:
            await withCheckedContinuation { continuation in
                activationContinuations[sessionID] = continuation
            }
        }
    }

    func highlight(sessionID _: String, tabConfig _: HighlightConfig?, paneConfig _: HighlightConfig?) async throws {}

    func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? {
        nil
    }

    func recordedActivationCalls() -> [String] {
        activationCalls
    }

    func waitUntilActivationStarts(_ sessionID: String) async {
        guard !startedActivations.contains(sessionID) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[sessionID, default: []].append(continuation)
        }
    }

    func completeActivation(_ sessionID: String) {
        activationContinuations.removeValue(forKey: sessionID)?.resume()
    }
}

private struct PresentedActivationBeacon: Equatable {
    let title: String
    let subtitle: String?
    let force: Bool
}

@Suite(.serialized)
@MainActor
struct SessionActivatorTests {
    @Test func activate_success_returnsActivatedAndClearsGuard() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge()
        await registry.register(bridge, for: .iterm2)
        let session = makeSession("s1")
        manager.testSetSessions([session])
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { _, _, _ in }
        )

        let outcome = await activator.activate(session: session, trigger: .guiSelect)

        guard case let .activated(activated) = outcome else {
            Issue.record("Expected activation to succeed")
            return
        }
        #expect(activated.id == "s1")
        #expect(manager.activationTarget == nil)
        #expect(await bridge.recordedActivationCalls() == ["s1"])
    }

    @Test func activate_failure_clearsGuardAndForcesFailureBeacon() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["s1": .fails])
        await registry.register(bridge, for: .iterm2)
        let session = makeSession("s1")
        manager.testSetSessions([session])
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let outcome = await activator.activate(session: session, trigger: .guiSelect)

        guard case .failed = outcome else {
            Issue.record("Expected activation to fail")
            return
        }
        #expect(manager.activationTarget == nil)
        #expect(beacons == [.init(title: "Activation Failed", subtitle: nil, force: true)])
    }

    @Test func activateFirstAvailable_skipsStaleSessionAndPresentsSuccessfulTarget() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["stale": .sessionNotFound])
        await registry.register(bridge, for: .iterm2)
        let stale = makeSession("stale")
        let live = makeSession("live")
        manager.testSetSessions([stale, live])
        var candidates = [stale, live]
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .cycle,
            nextSession: { candidates.isEmpty ? nil : candidates.removeFirst() }
        )

        guard case let .activated(activated) = outcome else {
            Issue.record("Expected a live session to activate")
            return
        }
        let rawTitleMode = UserDefaults.standard.string(forKey: AppStorageKeys.sessionTitleMode) ?? ""
        let titleMode = SessionTitleMode(rawValue: rawTitleMode) ?? .default
        let expectedTitle = manager.disambiguatedDisplayName(for: live, titleMode: titleMode)
        #expect(activated.id == "live")
        #expect(manager.sessions.map(\.id) == ["live"])
        #expect(await bridge.recordedActivationCalls() == ["stale", "live"])
        #expect(beacons == [.init(title: expectedTitle, subtitle: nil, force: false)])
    }

    @Test func activate_staleNotificationTarget_presentsNoNotification() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["stale": .sessionNotFound])
        await registry.register(bridge, for: .iterm2)
        let session = makeSession("stale")
        manager.testSetSessions([session])
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let outcome = await activator.activate(
            session: session,
            trigger: .hotkey,
            presentation: .notificationJump
        )

        guard case .unavailable = outcome else {
            Issue.record("Expected the stale target to be unavailable")
            return
        }
        #expect(beacons == [.init(title: "No Notification", subtitle: nil, force: false)])
    }

    @Test func activate_guardSuppressesIntermediateFocusWhileBridgeIsSuspended() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["s1": .suspends])
        await registry.register(bridge, for: .iterm2)
        let initial = makeSession("initial")
        let target = makeSession("s1")
        let intermediate = makeSession("intermediate")
        manager.testSetSessions([initial, target, intermediate])
        manager.updateFocusedSession(terminalSessionID: initial.id)
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { _, _, _ in }
        )

        let task = Task {
            await activator.activate(session: target, trigger: .guiSelect)
        }
        await bridge.waitUntilActivationStarts(target.id)

        #expect(manager.activationTarget == target.id)

        manager.updateFocusedSession(terminalSessionID: intermediate.id)

        #expect(manager.focusedSessionID == initial.id)
        #expect(manager.activationTarget == target.id)

        await bridge.completeActivation(target.id)
        _ = await task.value

        #expect(manager.activationTarget == nil)
    }

    @Test func activate_serializesOverlappingRequestsAndPresentsInRequestOrder() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["s1": .suspends, "s2": .suspends])
        await registry.register(bridge, for: .iterm2)
        let firstSession = makeSession("s1")
        let secondSession = makeSession("s2")
        manager.testSetSessions([firstSession, secondSession])
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let firstTask = Task {
            await activator.activate(session: firstSession, trigger: .hotkey, presentation: .cycle)
        }
        await bridge.waitUntilActivationStarts(firstSession.id)

        let secondTask = Task {
            await activator.activate(session: secondSession, trigger: .hotkey, presentation: .cycle)
        }
        await Task.yield()

        #expect(await bridge.recordedActivationCalls() == [firstSession.id])

        await bridge.completeActivation(firstSession.id)
        await bridge.waitUntilActivationStarts(secondSession.id)

        #expect(manager.activationTarget == secondSession.id)
        #expect(beacons.count == 1)

        await bridge.completeActivation(secondSession.id)
        _ = await firstTask.value
        _ = await secondTask.value

        #expect(await bridge.recordedActivationCalls() == [firstSession.id, secondSession.id])
        #expect(beacons.count == 2)
        #expect(manager.activationTarget == nil)
    }

    @Test func activateFirstAvailable_allStale_presentsAllAtWork() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(
            behaviors: ["stale-1": .sessionNotFound, "stale-2": .sessionNotFound]
        )
        await registry.register(bridge, for: .iterm2)
        let first = makeSession("stale-1")
        let second = makeSession("stale-2")
        manager.testSetSessions([first, second])
        var candidates = [first, second]
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .cycle,
            nextSession: { candidates.isEmpty ? nil : candidates.removeFirst() }
        )

        guard case .unavailable = outcome else {
            Issue.record("Expected all stale candidates to be unavailable")
            return
        }
        #expect(await bridge.recordedActivationCalls() == [first.id, second.id])
        #expect(beacons == [.init(title: "All At Work", subtitle: nil, force: false)])
    }

    @Test func activateFirstAvailable_failureOnlyExhaustion_presentsNothing() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["stale": .sessionNotFound])
        await registry.register(bridge, for: .iterm2)
        let session = makeSession("stale")
        manager.testSetSessions([session])
        var candidates = [session]
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .failureOnly,
            nextSession: { candidates.isEmpty ? nil : candidates.removeFirst() }
        )

        guard case .unavailable = outcome else {
            Issue.record("Expected the stale candidate to be unavailable")
            return
        }
        #expect(beacons.isEmpty)
    }

    @Test func activateFirstAvailable_genericFailureStopsRetry() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = SessionActivatorMockBridge(behaviors: ["failed": .fails])
        await registry.register(bridge, for: .iterm2)
        let failed = makeSession("failed")
        let untried = makeSession("untried")
        manager.testSetSessions([failed, untried])
        var candidates = [failed, untried]
        var beacons: [PresentedActivationBeacon] = []
        let activator = SessionActivator(
            sessionManager: manager,
            registry: registry,
            presentBeacon: { beacons.append(.init(title: $0, subtitle: $1, force: $2)) }
        )

        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .failureOnly,
            nextSession: { candidates.isEmpty ? nil : candidates.removeFirst() }
        )

        guard case .failed = outcome else {
            Issue.record("Expected activation to fail")
            return
        }
        #expect(await bridge.recordedActivationCalls() == [failed.id])
        #expect(candidates.map(\.id) == [untried.id])
        #expect(beacons == [.init(title: "Activation Failed", subtitle: nil, force: true)])
    }
}
