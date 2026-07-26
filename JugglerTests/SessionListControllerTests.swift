import AppKit
@testable import Juggler
import Testing

@Suite("SessionListController", .serialized)
struct SessionListControllerTests {
    // MARK: - moveSelection Tests

    // Selection is id-based and moves within the *visible* (rendered) order passed
    // in — not the raw `sessions` array index — so navigation follows what's on
    // screen even when the backing array drifts out of section order.

    @Test func moveSelection_fromNil_downGoesToFirst() {
        let controller = SessionListController()
        let visible = [makeSession("A"), makeSession("B"), makeSession("C")]
        #expect(controller.selectedSessionID == nil)

        controller.moveSelection(by: 1, in: visible)

        #expect(controller.selectedSessionID == "A")
    }

    @Test func moveSelection_fromNil_upGoesToLast() {
        let controller = SessionListController()
        let visible = [makeSession("A"), makeSession("B"), makeSession("C")]

        controller.moveSelection(by: -1, in: visible)

        #expect(controller.selectedSessionID == "C")
    }

    @Test func moveSelection_wrapsForward() {
        let controller = SessionListController()
        let visible = [makeSession("A"), makeSession("B"), makeSession("C")]
        controller.moveSelection(by: 1, in: visible)
        controller.moveSelection(by: 1, in: visible)
        controller.moveSelection(by: 1, in: visible)
        controller.moveSelection(by: 1, in: visible)

        #expect(controller.selectedSessionID == "A")
    }

    @Test func moveSelection_wrapsBackward() {
        let controller = SessionListController()
        let visible = [makeSession("A"), makeSession("B"), makeSession("C")]
        controller.moveSelection(by: 1, in: visible)
        controller.moveSelection(by: -1, in: visible)

        #expect(controller.selectedSessionID == "C")
    }

    @Test func moveSelection_emptyVisible_noOp() {
        let controller = SessionListController()

        controller.moveSelection(by: 1, in: [])

        #expect(controller.selectedSessionID == nil)
    }

    /// The core regression, end-to-end: the raw `sessions` array is deliberately
    /// NOT section-grouped (idle, working, idle), but driving `moveSelection` with
    /// `orderedVisibleSessions()` walks the *rendered* (grouped) order — so it never
    /// skips the trailing idle row the way raw-index navigation did.
    @Test @MainActor func moveSelection_followsVisibleOrder_notRawArrayOrder() {
        let key = "queueOrderMode"
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(QueueOrderMode.fair.rawValue, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let controller = SessionListController()
        let manager = SessionManager()
        // Ungrouped raw order: idle, working, idle. Raw-index nav would visit
        // idleA → work1 → idleB (skipping idleB visually); visible order is
        // idleA → idleB → work1.
        manager.testSetSessions([
            makeSession("idleA", state: .idle),
            makeSession("work1", state: .working),
            makeSession("idleB", state: .idle)
        ])

        var seen: [String] = []
        for _ in 0 ..< 3 {
            controller.moveSelection(by: 1, in: manager.orderedVisibleSessions())
            seen.append(controller.selectedSessionID ?? "nil")
        }

        #expect(seen == ["idleA", "idleB", "work1"])
        #expect(seen != manager.sessions.map(\.terminalSessionID)) // not raw order
    }

    /// When the selected session is temporarily absent from the visible list (e.g.
    /// mid section-animation), moving holds the selection instead of jumping to
    /// first/last.
    @Test func moveSelection_holdsWhenSelectionNotInVisible() {
        let controller = SessionListController()
        controller.moveSelection(by: 1, in: [makeSession("A"), makeSession("B")]) // A
        #expect(controller.selectedSessionID == "A")

        // "A" no longer in the visible list — selection must not jump.
        controller.moveSelection(by: 1, in: [makeSession("B"), makeSession("C")])
        #expect(controller.selectedSessionID == "A")
    }

    // MARK: - syncSelection Tests

    @Test func syncSelection_keepsSelection_acrossReorder() {
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]

        controller.moveSelection(by: 1, in: sessions) // A
        controller.moveSelection(by: 1, in: sessions) // B
        #expect(controller.selectedSessionID == "B")

        // Reorder — id-based selection is inherently stable.
        let reordered = [sessions[1], sessions[0], sessions[2]] // B, A, C
        controller.syncSelection(sessions: reordered)

        #expect(controller.selectedSessionID == "B")
    }

    @Test func syncSelection_fallsBackToFirst_whenSelectionLost() {
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B")]

        controller.moveSelection(by: 1, in: sessions) // A
        controller.moveSelection(by: 1, in: sessions) // B

        // Session B removed.
        let reduced = [makeSession("A")]
        controller.syncSelection(sessions: reduced)

        #expect(controller.selectedSessionID == "A")
    }

    @Test func syncSelection_emptySessions_clearsSelection() {
        let controller = SessionListController()
        let sessions = [makeSession("A")]

        controller.moveSelection(by: 1, in: sessions)
        #expect(controller.selectedSessionID == "A")

        controller.syncSelection(sessions: [])

        #expect(controller.selectedSessionID == nil)
    }

    // MARK: - cycleMode Tests

    @Test func cycleMode_forward_fairToPrio() {
        let controller = SessionListController()

        let result = controller.cycleMode(forward: true, currentMode: "fair")

        #expect(result == "prio")
    }

    @Test func cycleMode_forward_staticToGrouped() {
        let controller = SessionListController()

        let result = controller.cycleMode(forward: true, currentMode: "static")

        #expect(result == "grouped")
    }

    @Test func cycleMode_forward_wrapsGroupedToFair() {
        let controller = SessionListController()

        let result = controller.cycleMode(forward: true, currentMode: "grouped")

        #expect(result == "fair")
    }

    @Test func cycleMode_backward_fairToGrouped() {
        let controller = SessionListController()

        let result = controller.cycleMode(forward: false, currentMode: "fair")

        #expect(result == "grouped")
    }

    @Test func cycleMode_invalidMode_returnsUnchanged() {
        let controller = SessionListController()

        let result = controller.cycleMode(forward: true, currentMode: "nonexistent")

        #expect(result == "nonexistent")
    }

    // MARK: - backburnerSelected Tests

    @Test @MainActor func backburnerSelected_validSelection_backburners() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])

        controller.moveSelection(by: 1, in: manager.sessions) // s1
        #expect(controller.selectedSessionID == "s1")
        controller.backburnerSelected(sessionManager: manager)

        #expect(manager.sessions.first { $0.id == "s1" }?.state == .backburner)
    }

    @Test func backburnerSelected_noSelection_noOp() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1")])

        controller.backburnerSelected(sessionManager: manager)

        #expect(manager.sessions[0].state == .idle)
    }

    // MARK: - sendToBackSelected Tests

    @Test @MainActor func sendToBackSelected_middleSelection_movesAndSelectsNext() {
        let controller = SessionListController()
        let manager = SessionManager()
        UserDefaults.standard.set(QueueOrderMode.fair.rawValue, forKey: "queueOrderMode")
        defer { UserDefaults.standard.removeObject(forKey: "queueOrderMode") }
        manager.testSetSessions([
            makeSession("s1", state: .idle),
            makeSession("s2", state: .idle),
            makeSession("s3", state: .idle)
        ])

        controller.setSelection(toSessionID: "s2")
        controller.sendToBackSelected(sessionManager: manager)

        #expect(manager.sessions.map(\.id) == ["s1", "s3", "s2"])
        #expect(controller.selectedSessionID == "s3")
    }

    @Test @MainActor func sendToBackSelected_lastSelection_wrapsSelectionToTop() {
        let controller = SessionListController()
        let manager = SessionManager()
        UserDefaults.standard.set(QueueOrderMode.fair.rawValue, forKey: "queueOrderMode")
        defer { UserDefaults.standard.removeObject(forKey: "queueOrderMode") }
        manager.testSetSessions([
            makeSession("s1", state: .idle),
            makeSession("s2", state: .idle),
            makeSession("s3", state: .idle)
        ])

        controller.setSelection(toSessionID: "s3")
        controller.sendToBackSelected(sessionManager: manager)

        #expect(manager.sessions.map(\.id) == ["s1", "s2", "s3"])
        #expect(controller.selectedSessionID == "s1")
    }

    @Test @MainActor func sendToBackSelected_noSelection_noOp() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])

        controller.sendToBackSelected(sessionManager: manager)

        #expect(manager.sessions.map(\.id) == ["s1", "s2"])
    }

    // MARK: - reactivateSelected Tests

    @Test @MainActor func reactivateSelected_validSelection_reactivates() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .backburner)])

        controller.moveSelection(by: 1, in: manager.sessions) // s1
        controller.reactivateSelected(sessionManager: manager)

        #expect(manager.sessions.first { $0.id == "s1" }?.state == .idle)
    }

    @Test func reactivateSelected_noSelection_noOp() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .backburner)])

        controller.reactivateSelected(sessionManager: manager)

        #expect(manager.sessions[0].state == .backburner)
    }

    // MARK: - renameSelected Tests

    @Test func renameSelected_validSelection_setsSessionToRename() {
        let controller = SessionListController()
        let sessions = [makeSession("s1"), makeSession("s2")]

        controller.moveSelection(by: 1, in: sessions) // s1
        controller.renameSelected(sessions: sessions)

        #expect(controller.sessionToRename?.terminalSessionID == "s1")
    }

    @Test func renameSelected_noSelection_noOp() {
        let controller = SessionListController()
        let sessions = [makeSession("s1")]

        controller.renameSelected(sessions: sessions)

        #expect(controller.sessionToRename == nil)
    }

    // MARK: - reactivateAll Tests

    @Test @MainActor func reactivateAll_reactivatesBackburneredSessions() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([
            makeSession("s1", state: .backburner),
            makeSession("s2", state: .backburner)
        ])

        controller.reactivateAll(sessionManager: manager)

        #expect(manager.sessions.allSatisfy { $0.state == .idle })
    }

    // MARK: - activeColorIndex Tests (color is an independent cycling counter)

    @Test @MainActor func moveSelection_advancesActiveColorIndex() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let visible = (1 ... 5).map { makeSession("s\($0)") }

        controller.moveSelection(by: 1, in: visible)
        #expect(manager.activeColorIndex == 1)

        controller.moveSelection(by: 1, in: visible)
        #expect(manager.activeColorIndex == 2)

        controller.moveSelection(by: -1, in: visible)
        #expect(manager.activeColorIndex == 1)
    }

    @Test @MainActor func activeColorIndex_wrapsAtPaletteBoundary() {
        let manager = SessionManager()

        for _ in 0 ..< 6 {
            manager.advanceColorIndex(by: 1)
        }
        // 6 steps from 0: (0+6) % 5 = 1
        #expect(manager.activeColorIndex == 1)
    }

    @Test @MainActor func activeColorIndex_wrapsBackwardFromZero() {
        let manager = SessionManager()

        manager.advanceColorIndex(by: -1)
        #expect(manager.activeColorIndex == 4)
    }

    @Test @MainActor func setColorIndex_setsValue() {
        let manager = SessionManager()

        manager.setColorIndex(to: 3)
        #expect(manager.activeColorIndex == 3)
    }

    @Test @MainActor func setColorIndex_clampsToRange() {
        let manager = SessionManager()

        manager.setColorIndex(to: 7)
        #expect(manager.activeColorIndex == 2) // 7 % 5
    }

    @Test @MainActor func syncSelection_reorder_preservesActiveColor() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]

        controller.moveSelection(by: 1, in: sessions) // A, color → 1
        #expect(manager.activeColorIndex == 1)

        // Reorder: A moves to the end. Selection stays "A" (by id); color preserved.
        let reordered = [sessions[1], sessions[2], sessions[0]]
        controller.syncSelection(sessions: reordered)

        #expect(controller.selectedSessionID == "A")
        #expect(manager.activeColorIndex == 1)
    }

    @Test @MainActor func syncSelection_sessionRemoved_fallsBackToFirst() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B")]

        controller.moveSelection(by: 1, in: sessions) // A
        controller.moveSelection(by: 1, in: sessions) // B

        controller.syncSelection(sessions: [sessions[0]]) // B removed
        #expect(controller.selectedSessionID == "A")
    }

    @Test @MainActor func syncSelection_empty_resetsActiveColor() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A")]

        controller.moveSelection(by: 1, in: sessions)

        controller.syncSelection(sessions: [])
        #expect(controller.selectedSessionID == nil)
        #expect(manager.activeColorIndex == 0)
    }

    @Test @MainActor func setSelection_setsColorToSessionRowIndex() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        manager.testSetSessions(sessions)
        let controller = SessionListController()

        controller.setSelection(toSessionID: sessions[2].id)

        #expect(controller.selectedSessionID == sessions[2].id)
        #expect(manager.activeColorIndex == 2)
    }

    @Test @MainActor func setSelection_unknownSession_setsIDAndLeavesColorUnchanged() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        manager.testSetSessions([makeSession("A")])
        manager.setColorIndex(to: 3)
        let controller = SessionListController()

        // An id not present in any session still becomes the selection; the color
        // sync is a no-op for an unknown id (so the counter is left untouched).
        controller.setSelection(toSessionID: "does-not-exist")

        #expect(controller.selectedSessionID == "does-not-exist")
        #expect(manager.activeColorIndex == 3)
    }

    @Test @MainActor func setSelection_sameSession_preservesActiveColor() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let sessions = [makeSession("A"), makeSession("B")]
        manager.testSetSessions(sessions)
        let controller = SessionListController()

        // Navigate to "A" via arrow key (color advances to 1).
        controller.moveSelection(by: 1, in: sessions)
        #expect(controller.selectedSessionID == "A")
        #expect(manager.activeColorIndex == 1)

        // External focus to the same session — color should NOT change.
        controller.setSelection(toSessionID: "A")
        #expect(manager.activeColorIndex == 1)
    }

    @Test @MainActor func syncColorIndex_toKnownSession_setsToItsRowIndex() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        manager.testSetSessions(sessions)

        manager.syncColorIndex(toSessionID: sessions[2].id)
        #expect(manager.activeColorIndex == 2)

        manager.syncColorIndex(toSessionID: sessions[0].id)
        #expect(manager.activeColorIndex == 0)
    }

    @Test @MainActor func syncColorIndex_unknownSession_isNoOp() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let sessions = [makeSession("A")]
        manager.testSetSessions(sessions)
        manager.setColorIndex(to: 3)

        manager.syncColorIndex(toSessionID: "does-not-exist")

        #expect(manager.activeColorIndex == 3)
    }
}
