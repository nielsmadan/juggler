import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct HiddenSessionPresentationTests {
    @Test func showHiddenStartsOffForEachManager() {
        let manager = TestFixtures.isolatedSessionManager()
        #expect(manager.showsHiddenSessions == false)
        manager.showsHiddenSessions = true
        #expect(TestFixtures.isolatedSessionManager().showsHiddenSessions == false)
    }

    @Test(arguments: QueueOrderMode.allCases)
    func projectionPreservesEachModesOrder(mode: QueueOrderMode) {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions(orderedFixtures())
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)

        let expected: [String] = switch mode {
        case .fair, .prio: ["idleA", "hidden", "idleB", "work", "back"]
        case .static: ["idleA", "work", "hidden", "idleB", "back"]
        case .grouped: ["work", "hidden", "idleB", "idleA", "back"]
        }
        #expect(manager.listedSessions.map(\.id) == ["idleA", "work", "idleB", "back"])
        #expect(manager.orderedVisibleSessions().map(\.id) == expected.filter { $0 != "hidden" })
        #expect(manager.listEmptyState == nil)

        manager.showsHiddenSessions = true
        #expect(manager.listedSessions.map(\.id) == ["idleA", "work", "hidden", "idleB", "back"])
        #expect(manager.orderedVisibleSessions().map(\.id) == expected)
        #expect(manager.sessionsBySection().first?.sessions.map(\.id) == ["idleA", "hidden", "idleB"])
    }

    @Test(arguments: QueueOrderMode.allCases)
    func allHiddenAndNoTrackedRowsHaveDistinctEmptyStates(mode: QueueOrderMode) {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        let manager = TestFixtures.isolatedSessionManager()
        #expect(manager.listEmptyState == .noSessions)
        manager.testSetSessions([SessionState.idle, .permission, .working, .compacting, .backburner]
            .enumerated().map { index, state in
                var session = makeSession("row-\(index)", state: state)
                session.disposition.isHidden = true
                return session
            })
        #expect(manager.listEmptyState == .allHidden)
        #expect(manager.listEmptyState?.title == "All Sessions Hidden")
        #expect(manager.listedSessions.isEmpty)
        #expect(manager.orderedVisibleSessions().isEmpty)
        #expect(manager.sessionsBySection().isEmpty)
        #expect(manager.sessionsByWindowGroup().isEmpty)
        manager.showsHiddenSessions = true
        #expect(manager.listEmptyState == nil)
        #expect(manager.orderedVisibleSessions().count == 5)
    }

    @Test(arguments: SessionTitleMode.allCases)
    func disambiguationUsesOnlyListedRows(mode: SessionTitleMode) {
        let manager = TestFixtures.isolatedSessionManager()
        var hidden = makeSession("hidden")
        hidden.customName = "Shared"
        hidden.paneIndex = 0
        hidden.disposition.isHidden = true
        var visible = makeSession("visible")
        visible.customName = "Shared"
        visible.paneIndex = 1
        manager.testSetSessions([hidden, visible])
        #expect(manager.disambiguatedDisplayName(for: visible, titleMode: mode) == "Shared")
        manager.showsHiddenSessions = true
        #expect(manager.disambiguatedDisplayName(for: hidden, titleMode: mode) == "Shared (1)")
        #expect(manager.disambiguatedDisplayName(for: visible, titleMode: mode) == "Shared (2)")
    }

    @Test(arguments: QueueOrderMode.allCases)
    func hidingSelectionSynchronouslySelectsNextRenderedNeighbor(mode: QueueOrderMode) throws {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions(orderedFixtures())
        let before = manager.orderedVisibleSessions()
        let controller = SessionListController()
        controller.syncMonitorSelection(sessionManager: manager)
        controller.setSelection(toSessionID: before[1].id, syncColor: false)
        controller.toggleHidden(sessionID: before[1].id, sessionManager: manager)
        #expect(controller.selectedSessionID == before[2].id)
        #expect(try #require(manager.sessions.first { $0.id == before[1].id }).isHidden)
    }

    @Test func hidingLastSelectionFallsBackToPreviousAndClearsOnlyWhenEmpty() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("a"), makeSession("b")])
        let controller = SessionListController()
        controller.setSelection(toSessionID: "b", syncColor: false)
        controller.toggleHidden(sessionID: "b", sessionManager: manager)
        #expect(controller.selectedSessionID == "a")
        controller.toggleHidden(sessionID: "a", sessionManager: manager)
        #expect(controller.selectedSessionID == nil)
        #expect(manager.listEmptyState == .allHidden)
    }

    @Test func hidingConversationSkipsItsOtherHiddenRows() {
        let manager = TestFixtures.isolatedSessionManager()
        var duplicate = makeSession("duplicate")
        duplicate.agentSessionID = "selected"
        manager.testSetSessions([makeSession("selected"), duplicate, makeSession("next")])
        let controller = SessionListController()
        controller.setSelection(toSessionID: "selected", syncColor: false)
        controller.toggleHidden(sessionID: "selected", sessionManager: manager)
        #expect(controller.selectedSessionID == "next")
        #expect(manager.listedSessions.map(\.id) == ["next"])
    }

    @Test func visibilityToggleRepairsHiddenSelectionAndPreservesValidSelection() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("a"), makeSession("hidden"), makeSession("c")])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        let controller = SessionListController()
        controller.setSelection(toSessionID: "c", syncColor: false)
        controller.toggleHiddenVisibility(sessionManager: manager)
        #expect(controller.selectedSessionID == "c")
        controller.setSelection(toSessionID: "hidden", syncColor: false)
        controller.toggleHiddenVisibility(sessionManager: manager)
        #expect(controller.selectedSessionID == "c")
        #expect(manager.showsHiddenSessions == false)
    }

    @Test func unhidePreservesSelectionAndState() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("hidden", state: .compacting), makeSession("visible")])
        manager.setSessionHidden(sessionID: "hidden", isHidden: true)
        manager.showsHiddenSessions = true
        let controller = SessionListController()
        controller.setSelection(toSessionID: "hidden", syncColor: false)
        controller.toggleHidden(sessionID: "hidden", sessionManager: manager)
        #expect(controller.selectedSessionID == "hidden")
        #expect(manager.sessions.first?.state == .compacting)
        #expect(manager.sessions.first?.isHidden == false)
    }

    @Test func externalVisibilityChangesRepairFromPreviousRenderedOrder() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("a"), makeSession("b"), makeSession("c")])
        let controller = SessionListController()
        controller.setSelection(toSessionID: "b", syncColor: false)
        controller.syncMonitorSelection(sessionManager: manager)
        manager.setSessionHidden(sessionID: "b", isHidden: true)
        controller.syncMonitorSelection(sessionManager: manager)
        #expect(controller.selectedSessionID == "c")
    }

    @Test func focusAndActivationLookupRespectTheProjection() {
        let manager = TestFixtures.isolatedSessionManager()
        var hidden = makeSession("w1t0p0:uuid")
        hidden.disposition.isHidden = true
        manager.testSetSessions([makeSession("visible"), hidden])
        let controller = SessionListController()
        controller.syncMonitorSelection(sessionManager: manager)
        controller.selectListedSession(matching: "uuid", in: manager.listedSessions, syncColor: false)
        #expect(controller.selectedSessionID == "visible")
        controller.setSelection(toSessionID: hidden.id, syncColor: false)
        #expect(controller.selectedSession(in: manager.listedSessions) == nil)
        manager.showsHiddenSessions = true
        controller.selectListedSession(matching: "uuid", in: manager.listedSessions, syncColor: false)
        #expect(controller.selectedSession(in: manager.listedSessions)?.id == hidden.id)
        #expect(SessionActivationPolicy.explicit.resolve(hidden, in: manager)?.id == hidden.id)
    }

    @Test func temporaryAnimationRemovalPreservesListedSelection() {
        let sessions = [makeSession("a"), makeSession("b"), makeSession("c")]
        let controller = SessionListController()
        controller.syncSelection(sessions: sessions)
        controller.setSelection(toSessionID: "b", syncColor: false)
        controller.syncSelection(sessions: sessions, renderedSessions: [sessions[0], sessions[2]])
        #expect(controller.selectedSessionID == "b")
        controller.syncSelection(sessions: [sessions[0], sessions[2]])
        #expect(controller.selectedSessionID == "c")
    }

    @Test(arguments: [false, true])
    func currentSessionChangesCausedByHidingKeepRepairedSelection(showsHidden: Bool) {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("a"), makeSession("b"), makeSession("c")])
        manager.showsHiddenSessions = showsHidden
        let controller = SessionListController()
        controller.setSelection(toSessionID: "a", syncColor: false)
        let previous = SessionListController.SelectionSource(
            currentSessionID: "b",
            listedSessions: manager.listedSessions
        )
        controller.toggleHidden(sessionID: "a", sessionManager: manager)
        let current = SessionListController.SelectionSource(
            currentSessionID: "c",
            listedSessions: manager.listedSessions
        )
        controller.syncCurrentSelection(from: previous, to: current, sessions: manager.listedSessions)
        #expect(controller.selectedSessionID == (showsHidden ? "a" : "b"))
    }

    @Test func currentSessionObserverSelectsOnlyListedTargets() {
        let sessions = [makeSession("a"), makeSession("b")]
        let controller = SessionListController()
        let previous = SessionListController.SelectionSource(currentSessionID: "a", listedSessions: sessions)
        let current = SessionListController.SelectionSource(currentSessionID: "b", listedSessions: sessions)
        controller.syncCurrentSelection(from: previous, to: current, sessions: sessions)
        #expect(controller.selectedSessionID == "b")
        let filtered = SessionListController.SelectionSource(currentSessionID: "hidden", listedSessions: sessions)
        controller.syncCurrentSelection(from: current, to: filtered, sessions: sessions)
        #expect(controller.selectedSessionID == "b")
    }

    private struct OrderedFixture {
        let id: String
        let state: SessionState
        let window: String?
        let startedAt: TimeInterval
    }

    private func orderedFixtures() -> [Session] {
        let rows = [
            OrderedFixture(id: "idleA", state: .idle, window: "Beta", startedAt: 3),
            OrderedFixture(id: "work", state: .working, window: "Alpha", startedAt: 1),
            OrderedFixture(id: "hidden", state: .permission, window: "Alpha", startedAt: 2),
            OrderedFixture(id: "idleB", state: .idle, window: "Beta", startedAt: 0),
            OrderedFixture(id: "back", state: .backburner, window: nil, startedAt: 4)
        ]
        return rows.map { fixture in
            var session = makeSession(fixture.id, state: fixture.state)
            session.terminalWindowName = fixture.window
            session.startedAt = Date(timeIntervalSince1970: fixture.startedAt)
            return session
        }
    }
}
