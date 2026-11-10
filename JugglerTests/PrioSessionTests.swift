import Foundation
@testable import Juggler
import Testing

@Suite("Prio sessions", .serialized)
@MainActor
struct PrioSessionTests {
    private func withQueue(
        _ mode: QueueOrderMode,
        permissionFirst: Bool = false,
        _ body: () throws -> Void
    ) rethrows {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode, AppStorageKeys.prioritizePermissionSessions)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(permissionFirst, forKey: AppStorageKeys.prioritizePermissionSessions)
        try body()
    }

    private func session(
        _ id: String,
        _ state: SessionState,
        prio: Bool = false,
        idleSince: Double = 0,
        conversation: String? = nil
    ) -> Session {
        var session = makeSession(id, state: state)
        session.disposition.isPrioritized = prio
        session.lastBecameIdle = Date(timeIntervalSince1970: idleSince)
        if let conversation { session.agentSessionID = conversation }
        return session
    }

    private func order(_ manager: SessionManager) -> [String] {
        manager.sessions.map(\.id)
    }

    // MARK: - Arrivals

    @Test func fairPrioSessionFinishingWorkLandsAboveIdleSessions() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("b", .idle), session("p", .working, prio: true)])

            manager.updateSessionState(terminalSessionID: "p", state: .idle)

            #expect(order(manager) == ["p", "a", "b"])
        }
    }

    @Test func prioSessionFinishingWorkLandsBelowEarlierPrioSessions() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p1", .idle, prio: true), session("a", .idle), session("p2", .working, prio: true)
            ])

            manager.updateSessionState(terminalSessionID: "p2", state: .idle)

            #expect(order(manager) == ["p1", "p2", "a"])
        }
    }

    @Test func prioSessionLandsAtTheEndOfAnAllPrioWaitingBand() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p1", .idle, prio: true), session("w", .working), session("p2", .working, prio: true)
            ])

            manager.updateSessionState(terminalSessionID: "p2", state: .idle)

            #expect(order(manager) == ["p1", "p2", "w"])
        }
    }

    @Test func permissionFirstKeepsPrioAtTheTopOfEachBand() {
        withQueue(.fair, permissionFirst: true) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("perm", .permission), session("idle", .idle),
                session("p", .working, prio: true), session("q", .working, prio: true)
            ])

            manager.updateSessionState(terminalSessionID: "p", state: .idle)
            manager.updateSessionState(terminalSessionID: "q", state: .permission)

            #expect(order(manager) == ["q", "perm", "p", "idle"])
        }
    }

    @Test func permissionFirstPrioPermissionLandsAtTheEndOfAnAllPrioPermissionBand() {
        withQueue(.fair, permissionFirst: true) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p1", .permission, prio: true), session("i", .idle), session("q", .working, prio: true)
            ])

            manager.updateSessionState(terminalSessionID: "q", state: .permission)

            #expect(order(manager) == ["p1", "q", "i"])
        }
    }

    @Test func withoutPermissionFirstAPrioPermissionRequestJoinsTheSharedWaitingBand() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("p", .working, prio: true)])

            manager.updateSessionState(terminalSessionID: "p", state: .permission)

            #expect(order(manager) == ["p", "a"])
        }
    }

    @Test func reactivatedPrioSessionReturnsToThePrioGroup() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("p", .idle, prio: true)])

            manager.backburnerSession(terminalSessionID: "p")
            manager.reactivateSession(terminalSessionID: "p")

            #expect(order(manager) == ["p", "a"])
            #expect(manager.sessions[0].isPrioritized)
        }
    }

    @Test func storedFlagPlacesANewSessionInThePrioGroup() {
        withQueue(.fair) {
            let store = SessionDispositionStore()
            let identity = AgentSessionIdentity(agent: "claude-code", agentSessionID: "conversation")
            store.setDisposition(SessionDisposition(isHidden: false, isPrioritized: true), for: identity)
            let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
            manager.testSetSessions([session("a", .idle)])

            manager.addOrUpdateSession(
                agentSessionID: "conversation", terminalSessionID: "new", projectPath: "/test/new", state: .idle
            )

            #expect(order(manager) == ["new", "a"])
            #expect(manager.sessions[0].isPrioritized)
        }
    }

    // MARK: - Other modes

    @Test func prioModeIgnoresTheFlag() {
        withQueue(.prio) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p1", .idle, prio: true), session("a", .idle), session("p2", .working, prio: true)
            ])

            manager.updateSessionState(terminalSessionID: "p2", state: .idle)

            #expect(order(manager) == ["p2", "p1", "a"])
        }
    }

    @Test func prioModeSortIgnoresTheFlag() {
        withQueue(.prio) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("prioOld", .idle, prio: true, idleSince: 10), session("plainNew", .idle, idleSince: 20)
            ])

            manager.reorderForMode(.prio)

            #expect(order(manager) == ["plainNew", "prioOld"])
        }
    }

    @Test(arguments: [QueueOrderMode.static, .grouped])
    func prioritizingInUnorderedModesKeepsTheOrder(mode: QueueOrderMode) {
        withQueue(mode) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("b", .idle)])

            manager.setSessionPrioritized(sessionID: "b", isPrioritized: true)

            #expect(order(manager) == ["a", "b"])
            #expect(manager.sessions[1].isPrioritized)
        }
    }

    // MARK: - Toggling

    @Test func prioritizingAWaitingSessionMovesItToTheEndOfThePrioGroup() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("p", .idle, prio: true), session("a", .idle), session("c", .idle)])

            manager.toggleSessionPrioritized(sessionID: "c")

            #expect(order(manager) == ["p", "c", "a"])
            #expect(manager.sessions[1].isPrioritized)
        }
    }

    @Test func prioritizingKeepsTheOrderThatAFullResortProduces() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p", .idle, prio: true, idleSince: 30),
                session("c", .idle, idleSince: 10)
            ])

            manager.setSessionPrioritized(sessionID: "c", isPrioritized: true)
            let toggled = order(manager)
            manager.reorderForMode(.fair)

            #expect(toggled == ["p", "c"])
            #expect(order(manager) == toggled)
        }
    }

    @Test func prioritizingAnAlreadyPrioSessionKeepsItsPlace() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("p1", .idle, prio: true), session("p2", .idle, prio: true)])

            manager.setSessionPrioritized(sessionID: "p1", isPrioritized: true)

            #expect(order(manager) == ["p1", "p2"])
        }
    }

    @Test func unprioritizingMovesTheSessionBelowTheRemainingPrioGroup() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p1", .idle, prio: true), session("p2", .idle, prio: true), session("a", .idle),
                session("p3", .working, prio: true)
            ])

            manager.toggleSessionPrioritized(sessionID: "p1")
            #expect(order(manager) == ["p2", "p1", "a", "p3"])

            manager.updateSessionState(terminalSessionID: "p3", state: .idle)
            #expect(order(manager) == ["p2", "p3", "p1", "a"])
        }
    }

    @Test func unprioritizingASessionBelowPlainSessionsLeavesIt() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("p", .idle, prio: true)])

            manager.setSessionPrioritized(sessionID: "p", isPrioritized: false)

            #expect(order(manager) == ["a", "p"])
        }
    }

    @Test func prioritizingABusySessionPlacesItWhenItBecomesIdle() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("w", .working)])

            manager.setSessionPrioritized(sessionID: "w", isPrioritized: true)
            #expect(order(manager) == ["a", "w"])

            manager.updateSessionState(terminalSessionID: "w", state: .idle)
            #expect(order(manager) == ["w", "a"])
        }
    }

    @Test func sendingAPrioSessionToBackPutsItBelowPlainSessions() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("p", .idle, prio: true), session("a", .idle), session("q", .working, prio: true)
            ])

            manager.moveSessionToBackOfQueue(sessionID: "p")
            #expect(order(manager) == ["a", "p", "q"])

            manager.updateSessionState(terminalSessionID: "q", state: .idle)
            #expect(order(manager) == ["q", "a", "p"])
        }
    }

    @Test func switchingIntoFairSortsPrioSessionsFirst() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("old", .idle, idleSince: 10),
                session("prioNew", .idle, prio: true, idleSince: 30),
                session("prioOld", .idle, prio: true, idleSince: 20),
                session("busy", .working)
            ])

            manager.reorderForMode(.fair)

            #expect(order(manager) == ["prioOld", "prioNew", "old", "busy"])
        }
    }

    // MARK: - Identity

    @Test func rowsOfOneConversationShareTheFlagAndPersistIt() {
        withQueue(.fair) {
            let store = SessionDispositionStore()
            let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
            manager.testSetSessions([session("a", .idle), session("x", .idle), session("x2", .idle, conversation: "x")])

            manager.setSessionPrioritized(sessionID: "x", isPrioritized: true)

            #expect(order(manager) == ["x", "x2", "a"])
            #expect(manager.sessions.filter(\.isPrioritized).map(\.id) == ["x", "x2"])
            let identity = AgentSessionIdentity(agent: "claude-code", agentSessionID: "x")
            #expect(store.disposition(for: identity).isPrioritized)
        }
    }

    @Test func resumingAPrioConversationInAWaitingRowMovesItIntoThePrioGroup() {
        withQueue(.fair) {
            let store = SessionDispositionStore()
            let identity = AgentSessionIdentity(agent: "claude-code", agentSessionID: "stored")
            store.setDisposition(SessionDisposition(isHidden: false, isPrioritized: true), for: identity)
            let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
            manager.testSetSessions([session("a", .idle), session("pane", .idle)])

            manager.addOrUpdateSession(
                agentSessionID: "stored", terminalSessionID: "pane", projectPath: "/test/pane",
                state: .idle, event: "SessionStart"
            )

            #expect(order(manager) == ["pane", "a"])
            #expect(manager.sessions[0].isPrioritized)
        }
    }

    @Test func replacingAPrioConversationMovesTheRowOutOfThePrioGroup() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([
                session("pane", .idle, prio: true), session("p", .idle, prio: true), session("a", .idle)
            ])

            manager.addOrUpdateSession(
                agentSessionID: "fresh", terminalSessionID: "pane", projectPath: "/test/pane",
                state: .idle, event: "SessionStart"
            )

            #expect(order(manager) == ["p", "pane", "a"])
            #expect(manager.sessions[1].disposition == .empty)
        }
    }

    @Test func prioSetBeforeTheConversationIsKnownWinsOverTheStoredFlag() {
        withQueue(.fair) {
            let store = SessionDispositionStore()
            let identity = AgentSessionIdentity(agent: "claude-code", agentSessionID: "conversation")
            let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
            manager.testSetSessions([session("pane", .idle, conversation: "")])

            manager.setSessionPrioritized(sessionID: "pane", isPrioritized: true)
            manager.addOrUpdateSession(
                agentSessionID: "conversation", terminalSessionID: "pane", projectPath: "/test/pane", state: .idle
            )

            #expect(manager.sessions[0].isPrioritized)
            #expect(store.disposition(for: identity).isPrioritized)
        }
    }

    @Test func explicitUnprioritizeBeforeTheConversationIsKnownWinsOverAStoredFlag() {
        withQueue(.fair) {
            let store = SessionDispositionStore()
            let identity = AgentSessionIdentity(agent: "claude-code", agentSessionID: "conversation")
            store.setDisposition(SessionDisposition(isHidden: false, isPrioritized: true), for: identity)
            let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
            manager.testSetSessions([session("pane", .idle, conversation: "")])

            manager.setSessionPrioritized(sessionID: "pane", isPrioritized: false)
            manager.addOrUpdateSession(
                agentSessionID: "conversation", terminalSessionID: "pane", projectPath: "/test/pane", state: .idle
            )

            #expect(manager.sessions[0].disposition == .empty)
            #expect(store.dispositions.isEmpty)
        }
    }

    // MARK: - Controller

    @Test func controllerTogglesListedSessionsOnlyInFair() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            manager.testSetSessions([session("a", .idle), session("b", .idle)])
            let controller = SessionListController()

            controller.togglePrioritized(sessionID: "b", mode: .prio, sessionManager: manager)
            #expect(order(manager) == ["a", "b"])
            #expect(manager.sessions[1].disposition == .empty)

            controller.togglePrioritized(sessionID: "b", mode: .fair, sessionManager: manager)
            #expect(order(manager) == ["b", "a"])
            #expect(manager.sessions[0].isPrioritized)
        }
    }

    @Test func controllerTogglesHiddenSessionsOnlyWhileTheyAreListed() {
        withQueue(.fair) {
            let manager = TestFixtures.isolatedSessionManager()
            var hidden = session("h", .idle)
            hidden.disposition.isHidden = true
            manager.testSetSessions([session("a", .idle), hidden])
            let controller = SessionListController()

            controller.togglePrioritized(sessionID: "h", mode: .fair, sessionManager: manager)
            #expect(manager.sessions[1].disposition == SessionDisposition(isHidden: true))

            manager.showsHiddenSessions = true
            controller.togglePrioritized(sessionID: "h", mode: .fair, sessionManager: manager)
            #expect(manager.sessions.first { $0.id == "h" }?.isPrioritized == true)
        }
    }
}
