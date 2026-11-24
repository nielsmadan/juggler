import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct CycleBackUndoTests {
    private func makeManager() -> SessionManager {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("A"), makeSession("B"), makeSession("C")])
        manager.isTerminalAppActive = true
        manager.testSetFocusedSessionID("A")
        return manager
    }

    private func forwardToB(_ manager: SessionManager, at t: Date) {
        UserDefaults.standard.set(QueueOrderMode.fair.rawValue, forKey: AppStorageKeys.queueOrderMode)
        #expect(manager.cycleForward(now: t)?.id == "B")
        manager.updateSessionState(terminalSessionID: "A", state: .working, allowsAutomation: false)
    }

    @Test func undoWithinWindowReturnsToTheBusyOrigin() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        let manager = makeManager()
        let t = Date()
        forwardToB(manager, at: t)

        #expect(manager.cycleBackToForwardOrigin(now: t + 2)?.id == "A")
        #expect(manager.focusedSessionID == "A")
        #expect(manager.cycleBackToForwardOrigin(now: t + 2) == nil)
    }

    @Test func undoOutsideTheWindowDoesNothing() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        let manager = makeManager()
        let t = Date()
        forwardToB(manager, at: t)

        #expect(manager.cycleBackToForwardOrigin(now: t + 6) == nil)
        #expect(manager.focusedSessionID == "B")
    }

    @Test func undoIgnoresFocusThatMovedElsewhere() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        let manager = makeManager()
        let t = Date()
        forwardToB(manager, at: t)
        manager.updateFocusedSession(terminalSessionID: "C")

        #expect(manager.cycleBackToForwardOrigin(now: t + 2) == nil)
    }

    @Test func undoSkipsAHiddenOrigin() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        let manager = makeManager()
        let t = Date()
        forwardToB(manager, at: t)
        manager.setSessionHidden(sessionID: "A", isHidden: true)

        #expect(manager.cycleBackToForwardOrigin(now: t + 2) == nil)
    }

    @Test func undoSkipsABackburneredOrigin() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        let manager = makeManager()
        let t = Date()
        forwardToB(manager, at: t)
        manager.backburnerSession(terminalSessionID: "A")

        #expect(manager.cycleBackToForwardOrigin(now: t + 2) == nil)
    }

    @Test func normalBackwardCycleConsumesTheUndo() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode)
        defer { restore() }
        let manager = makeManager()
        let t = Date()
        forwardToB(manager, at: t)

        manager.cycleBackward()

        #expect(manager.cycleBackToForwardOrigin(now: t + 2) == nil)
    }
}
