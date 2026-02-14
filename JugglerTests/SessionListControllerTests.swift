@testable import Juggler
import Testing

// MARK: - moveSelection Tests

@Test func moveSelection_fromNil_downGoesToFirst() {
    let controller = SessionListController()
    #expect(controller.selectedIndex == nil)

    controller.moveSelection(by: 1, sessionCount: 3)

    #expect(controller.selectedIndex == 0)
}

@Test func moveSelection_fromNil_upGoesToLast() {
    let controller = SessionListController()

    controller.moveSelection(by: -1, sessionCount: 3)

    #expect(controller.selectedIndex == 2)
}

@Test func moveSelection_wrapsForward() {
    let controller = SessionListController()
    controller.moveSelection(by: 1, sessionCount: 3) // → 0
    controller.moveSelection(by: 1, sessionCount: 3) // → 1
    controller.moveSelection(by: 1, sessionCount: 3) // → 2
    controller.moveSelection(by: 1, sessionCount: 3) // → 0 (wrap)

    #expect(controller.selectedIndex == 0)
}

@Test func moveSelection_wrapsBackward() {
    let controller = SessionListController()
    controller.moveSelection(by: 1, sessionCount: 3) // → 0
    controller.moveSelection(by: -1, sessionCount: 3) // → 2 (wrap)

    #expect(controller.selectedIndex == 2)
}

@Test func moveSelection_emptyCount_noOp() {
    let controller = SessionListController()

    controller.moveSelection(by: 1, sessionCount: 0)

    #expect(controller.selectedIndex == nil)
}

// MARK: - syncSelection Tests

@Test func syncSelection_preservesSelectionByID_acrossReorder() {
    let controller = SessionListController()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]

    // Select "B" (index 1)
    controller.moveSelection(by: 1, sessionCount: 3) // → 0
    controller.moveSelection(by: 1, sessionCount: 3) // → 1
    controller.trackSelectedSession(sessions: sessions)

    #expect(controller.selectedIndex == 1)

    // Reorder: B moves to index 0
    let reordered = [sessions[1], sessions[0], sessions[2]] // B, A, C

    controller.syncSelection(sessions: reordered)

    #expect(controller.selectedIndex == 0) // "B" is now at 0
}

@Test func syncSelection_fallsBackToZero_whenIDLost() {
    let controller = SessionListController()
    let sessions = [makeSession("A"), makeSession("B")]

    // Select "B" (index 1)
    controller.moveSelection(by: 1, sessionCount: 2) // → 0
    controller.moveSelection(by: 1, sessionCount: 2) // → 1
    controller.trackSelectedSession(sessions: sessions)

    // Session B removed
    let reduced = [makeSession("A")]
    controller.syncSelection(sessions: reduced)

    #expect(controller.selectedIndex == 0)
}

@Test func syncSelection_emptySessions_clearsSelection() {
    let controller = SessionListController()
    let sessions = [makeSession("A")]

    controller.moveSelection(by: 1, sessionCount: 1)
    controller.trackSelectedSession(sessions: sessions)
    #expect(controller.selectedIndex == 0)

    controller.syncSelection(sessions: [])

    #expect(controller.selectedIndex == nil)
}

@Test func syncSelection_indexOutOfBounds_resetsToZero() {
    let controller = SessionListController()

    // Simulate stale index by selecting far then shrinking
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    controller.moveSelection(by: 1, sessionCount: 3) // → 0
    controller.moveSelection(by: 1, sessionCount: 3) // → 1
    controller.moveSelection(by: 1, sessionCount: 3) // → 2
    // Don't track by ID — simulate stale index

    let smaller = [makeSession("X")]
    controller.syncSelection(sessions: smaller)

    #expect(controller.selectedIndex == 0)
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
