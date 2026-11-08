import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct SessionListFocusTests {
    @Test(arguments: [QueueOrderMode.static, .grouped], [false, true])
    func unrelatedStateChangeKeepsListedFocusAsMonitorActionTarget(mode: QueueOrderMode, hidden: Bool) throws {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode, AppStorageKeys.autoAdvanceOnBusy)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([
            makeSession("H", state: hidden ? .idle : .working), makeSession("A"), makeSession("B")
        ])
        manager.setSessionHidden(sessionID: "H", isHidden: hidden)
        manager.showsHiddenSessions = true
        manager.updateFocusedSession(terminalSessionID: "H")
        let controller = SessionListController()
        controller.syncMonitorSelection(sessionManager: manager)
        controller.selectListedSession(matching: manager.focusedSessionID, in: manager.listedSessions, syncColor: false)
        let previous = SessionListController.SelectionSource(sessionManager: manager)
        #expect(manager.currentSession?.id == "A")
        #expect(previous.currentSessionID == "H")

        manager.updateSessionState(terminalSessionID: "A", state: .working)
        let current = SessionListController.SelectionSource(sessionManager: manager)
        #expect(manager.currentSession?.id == "B")
        #expect(manager.focusedSessionID == "H")
        #expect(current.currentSessionID == "H")
        controller.syncMonitorSelection(sessionManager: manager)
        controller.syncCurrentSelection(from: previous, to: current, sessions: manager.listedSessions)

        let selected = try #require(controller.selectedSession(in: manager.listedSessions))
        #expect(selected.id == "H")
        #expect(SessionActivationPolicy.explicit.resolve(selected, in: manager)?.id == "H")
        #expect(manager.cyclableSessions.map(\.id) == ["B"])
        controller.toggleHidden(sessionID: selected.id, sessionManager: manager)
        #expect(manager.sessions.first { $0.id == "H" }?.isHidden == !hidden)
        #expect(manager.sessions.first { $0.id == "A" }?.isHidden == false)
        #expect(manager.sessions.first { $0.id == "B" }?.isHidden == false)
    }

    @Test(arguments: [QueueOrderMode.static, .grouped])
    func filteredHiddenFocusUsesTheCurrentFallback(mode: QueueOrderMode) {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode, AppStorageKeys.autoAdvanceOnBusy)
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("H"), makeSession("A"), makeSession("B")])
        manager.setSessionHidden(sessionID: "H", isHidden: true)
        manager.updateFocusedSession(terminalSessionID: "H")
        let controller = SessionListController()
        controller.syncMonitorSelection(sessionManager: manager)
        let previous = SessionListController.SelectionSource(sessionManager: manager)
        #expect(previous.currentSessionID == "A")
        manager.updateSessionState(terminalSessionID: "A", state: .working)
        let current = SessionListController.SelectionSource(sessionManager: manager)
        controller.syncCurrentSelection(from: previous, to: current, sessions: manager.listedSessions)
        #expect(controller.selectedSessionID == "B")
        #expect(current.currentSessionID == "B")
    }

    enum PopoverFocus: CaseIterable {
        case visible
        case revealedHidden
        case filteredHidden
        case untracked
    }

    @Test(arguments: PopoverFocus.allCases)
    func popoverPrefersListedFocusBeforeCurrentReferenceWithoutRetinting(focus: PopoverFocus) {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([
            makeSession("A", state: .working), makeSession("H", state: .working), makeSession("B")
        ])
        manager.testSetLastActiveSessionID("A")
        manager.setSessionHidden(sessionID: "H", isHidden: focus == .revealedHidden || focus == .filteredHidden)
        manager.showsHiddenSessions = focus == .revealedHidden
        manager.updateFocusedSession(terminalSessionID: focus == .untracked ? "untracked" : "H")
        let previousColor = SessionManager.shared.activeColorIndex
        defer { SessionManager.shared.setColorIndex(to: previousColor) }
        SessionManager.shared.setColorIndex(to: 4)
        manager.setColorIndex(to: 3)
        let controller = SessionListController()
        controller.setSelection(toSessionID: "B", syncColor: false)
        controller.syncPopoverSelection(sessionManager: manager)

        let expected = switch focus {
        case .visible, .revealedHidden: "H"
        case .filteredHidden: "B"
        case .untracked: "A"
        }
        #expect(controller.selectedSessionID == expected)
        #expect(controller.selectedSession(in: manager.listedSessions)?.id == expected)
        #expect(SessionManager.shared.activeColorIndex == 4)
        #expect(manager.activeColorIndex == 3)
    }

    @Test(arguments: [false, true])
    func emptyPopoverPreservesColorForNoSessionsAndAllHidden(allHidden: Bool) {
        let manager = TestFixtures.isolatedSessionManager()
        if allHidden {
            manager.testSetSessions([makeSession("H")])
            manager.setSessionHidden(sessionID: "H", isHidden: true)
            manager.updateFocusedSession(terminalSessionID: "H")
        }
        let previousColor = SessionManager.shared.activeColorIndex
        defer { SessionManager.shared.setColorIndex(to: previousColor) }
        SessionManager.shared.setColorIndex(to: 4)
        let controller = SessionListController()
        controller.syncPopoverSelection(sessionManager: manager)
        #expect(controller.selectedSessionID == nil)
        #expect(SessionManager.shared.activeColorIndex == 4)
    }
}
