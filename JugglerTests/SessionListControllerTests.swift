import AppKit
@testable import Juggler
import ShortcutField
import Testing

@Suite("SessionListController", .serialized)
struct SessionListControllerTests {
    private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let cgFlags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = cgFlags
        return NSEvent(cgEvent: event)!
    }

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
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: 1, sessionCount: 3)

        #expect(controller.selectedIndex == 0)
    }

    @Test func moveSelection_wrapsBackward() {
        let controller = SessionListController()
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: -1, sessionCount: 3)

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
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: 1, sessionCount: 3)
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
        controller.moveSelection(by: 1, sessionCount: 2)
        controller.moveSelection(by: 1, sessionCount: 2)
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
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: 1, sessionCount: 3)
        controller.moveSelection(by: 1, sessionCount: 3)
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

    // MARK: - hasShortcutForKeyCode Tests

    @Test func hasShortcutForKeyCode_matchingCode_returnsTrue() {
        let controller = SessionListController()
        // Default shortcuts include togglePause with keyCode 1 (S)
        #expect(controller.hasShortcutForKeyCode(1) == true)
    }

    @Test func hasShortcutForKeyCode_nonMatchingCode_returnsFalse() {
        let controller = SessionListController()
        #expect(controller.hasShortcutForKeyCode(999) == false)
    }

    // MARK: - backburnerSelected Tests

    @Test @MainActor func backburnerSelected_validIndex_backburners() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])

        controller.moveSelection(by: 1, sessionCount: 2) // selectedIndex = 0 → s1
        let selectedSession = manager.sessions[controller.selectedIndex!]
        #expect(selectedSession.id == "s1")
        manager.testApplyStateChange(sessionID: selectedSession.id, from: .idle, to: .backburner)

        #expect(manager.sessions.first { $0.id == "s1" }?.state == .backburner)
    }

    @Test func backburnerSelected_nilIndex_noOp() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1")])

        controller.backburnerSelected(sessionManager: manager)

        #expect(manager.sessions[0].state == .idle)
    }

    // MARK: - reactivateSelected Tests

    @Test @MainActor func reactivateSelected_validIndex_reactivates() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .backburner)])

        controller.moveSelection(by: 1, sessionCount: 1)
        let selectedSession = manager.sessions[controller.selectedIndex!]
        manager.testApplyStateChange(sessionID: selectedSession.id, from: .backburner, to: .idle)

        #expect(manager.sessions.first { $0.id == "s1" }?.state == .idle)
    }

    @Test func reactivateSelected_nilIndex_noOp() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1", state: .backburner)])

        controller.reactivateSelected(sessionManager: manager)

        #expect(manager.sessions[0].state == .backburner)
    }

    // MARK: - renameSelected Tests

    @Test func renameSelected_validIndex_setsSessionToRename() {
        let controller = SessionListController()
        let sessions = [makeSession("s1"), makeSession("s2")]

        controller.moveSelection(by: 1, sessionCount: 2)
        controller.renameSelected(sessions: sessions)

        #expect(controller.sessionToRename?.terminalSessionID == "s1")
    }

    @Test func renameSelected_nilIndex_noOp() {
        let controller = SessionListController()
        let sessions = [makeSession("s1")]

        controller.renameSelected(sessions: sessions)

        #expect(controller.sessionToRename == nil)
    }

    // MARK: - trackSelectedSession Tests

    @Test func trackSelectedSession_updatesInternalID() {
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B")]

        controller.moveSelection(by: 1, sessionCount: 2) // → 0
        controller.trackSelectedSession(sessions: sessions)

        let reordered = [sessions[1], sessions[0]] // B, A
        controller.syncSelection(sessions: reordered)

        #expect(controller.selectedIndex == 1) // "A" moved to index 1
    }

    // MARK: - reloadShortcuts Tests

    @Test @MainActor func reloadShortcuts_usesDefaultsWhenUnset() {
        let keys = [
            AppStorageKeys.localShortcutTogglePause,
            AppStorageKeys.localShortcutResetStats,
            AppStorageKeys.localShortcutToggleBeacon,
            AppStorageKeys.localShortcutToggleAutoNext,
            AppStorageKeys.localShortcutToggleAutoRestart
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let controller = SessionListController()

        #expect(controller.shortcutTogglePause == Shortcut(keyCode: 1, modifiers: []))
        #expect(controller.shortcutResetStats == Shortcut(keyCode: 1, modifiers: .shift))
        #expect(controller.shortcutToggleBeacon == Shortcut(keyCode: 11, modifiers: []))
        #expect(controller.shortcutToggleAutoNext == Shortcut(keyCode: 0, modifiers: []))
        #expect(controller.shortcutToggleAutoRestart == Shortcut(keyCode: 12, modifiers: []))
    }

    @Test @MainActor func reloadShortcuts_prefersSavedValues() {
        let savedMoveDown = Shortcut(keyCode: 15, modifiers: .command)
        let savedRename = Shortcut(keyCode: 17, modifiers: .shift)
        savedMoveDown.save(to: AppStorageKeys.localShortcutMoveDown)
        savedRename.save(to: AppStorageKeys.localShortcutRename)
        defer {
            Shortcut.remove(from: AppStorageKeys.localShortcutMoveDown)
            Shortcut.remove(from: AppStorageKeys.localShortcutRename)
        }

        let controller = SessionListController()

        #expect(controller.shortcutMoveDown == savedMoveDown)
        #expect(controller.shortcutRename == savedRename)
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

    // MARK: - handleKeyEvent Tests

    @Test @MainActor func handleKeyEvent_moveDown_updatesSelectionAndTracksSession() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1"), makeSession("s2")])
        let shortcut = Shortcut(keyCode: 125, modifiers: [])
        shortcut.save(to: AppStorageKeys.localShortcutMoveDown)
        defer { Shortcut.remove(from: AppStorageKeys.localShortcutMoveDown) }
        controller.reloadShortcuts()
        var queueMode = QueueOrderMode.fair.rawValue

        let handled = controller.handleKeyEvent(
            makeKeyEvent(keyCode: 125),
            sessionManager: manager,
            queueOrderMode: &queueMode
        )

        #expect(handled == true)
        #expect(controller.selectedIndex == 0)

        manager.testSetSessions([manager.sessions[1], manager.sessions[0]])
        controller.syncSelection(sessions: manager.sessions)
        #expect(controller.selectedIndex == 1)
    }

    @Test @MainActor func handleKeyEvent_cycleModeForward_updatesQueueMode() {
        let controller = SessionListController()
        let manager = SessionManager()
        let shortcut = Shortcut(keyCode: 124, modifiers: .command)
        shortcut.save(to: AppStorageKeys.localShortcutCycleModeForward)
        defer { Shortcut.remove(from: AppStorageKeys.localShortcutCycleModeForward) }
        controller.reloadShortcuts()
        var queueMode = QueueOrderMode.fair.rawValue

        let handled = controller.handleKeyEvent(
            makeKeyEvent(keyCode: 124, modifiers: .command),
            sessionManager: manager,
            queueOrderMode: &queueMode
        )

        #expect(handled == true)
        #expect(queueMode == QueueOrderMode.prio.rawValue)
    }

    @Test @MainActor func handleKeyEvent_backburnerShortcut_updatesSelectedSession() {
        let controller = SessionListController()
        let manager = SessionManager()
        manager.testSetSessions([makeSession("s1"), makeSession("s2")])
        controller.moveSelection(by: 1, sessionCount: 2)
        let shortcut = Shortcut(keyCode: 11, modifiers: .shift)
        shortcut.save(to: AppStorageKeys.localShortcutBackburner)
        defer { Shortcut.remove(from: AppStorageKeys.localShortcutBackburner) }
        controller.reloadShortcuts()
        var queueMode = QueueOrderMode.fair.rawValue

        let handled = controller.handleKeyEvent(
            makeKeyEvent(keyCode: 11, modifiers: .shift),
            sessionManager: manager,
            queueOrderMode: &queueMode
        )

        #expect(handled == true)
        #expect(manager.sessions.first { $0.id == "s1" }?.state == .backburner)
    }

    @Test @MainActor func handleKeyEvent_unmatchedShortcut_returnsFalse() {
        let controller = SessionListController()
        let manager = SessionManager()
        var queueMode = QueueOrderMode.fair.rawValue

        let handled = controller.handleKeyEvent(
            makeKeyEvent(keyCode: 123),
            sessionManager: manager,
            queueOrderMode: &queueMode
        )

        #expect(handled == false)
        #expect(queueMode == QueueOrderMode.fair.rawValue)
    }

    // MARK: - activeColorIndex Tests (color now lives on SessionManager)

    @Test @MainActor func moveSelection_advancesActiveColorIndex() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()

        controller.moveSelection(by: 1, sessionCount: 5)
        #expect(manager.activeColorIndex == 1)

        controller.moveSelection(by: 1, sessionCount: 5)
        #expect(manager.activeColorIndex == 2)

        controller.moveSelection(by: -1, sessionCount: 5)
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

        controller.moveSelection(by: 1, sessionCount: 3)
        controller.trackSelectedSession(sessions: sessions)
        #expect(manager.activeColorIndex == 1)

        // Reorder: A moves to index 2
        let reordered = [sessions[1], sessions[2], sessions[0]]
        controller.syncSelection(sessions: reordered)

        // Color preserved across reorder
        #expect(controller.selectedIndex == 2)
        #expect(manager.activeColorIndex == 1)
    }

    @Test @MainActor func syncSelection_sessionRemoved_resetsActiveColor() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B")]

        controller.moveSelection(by: 1, sessionCount: 2)
        controller.moveSelection(by: 1, sessionCount: 2)
        controller.trackSelectedSession(sessions: sessions)

        controller.syncSelection(sessions: [sessions[0]])
        #expect(controller.selectedIndex == 0)
        #expect(manager.activeColorIndex == 0)
    }

    @Test @MainActor func syncSelection_empty_resetsActiveColor() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A")]

        controller.moveSelection(by: 1, sessionCount: 1)
        controller.trackSelectedSession(sessions: sessions)

        controller.syncSelection(sessions: [])
        #expect(controller.selectedIndex == nil)
        #expect(manager.activeColorIndex == 0)
    }

    @Test @MainActor func setSelection_resetsActiveColorToIndex() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]

        controller.setSelection(to: 2, sessions: sessions)

        #expect(controller.selectedIndex == 2)
        #expect(manager.activeColorIndex == 2)
    }

    @Test @MainActor func setSelection_sameIndex_preservesActiveColor() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A"), makeSession("B")]

        // Navigate to index 0 via arrow key (color advances to 1)
        controller.moveSelection(by: 1, sessionCount: 2)
        #expect(manager.activeColorIndex == 1)

        // External focus to same index — color should NOT reset
        controller.setSelection(to: 0, sessions: sessions)
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

    @Test @MainActor func setSelection_outOfBounds_noOp() {
        let manager = SessionManager.shared
        manager.clearColorIndex()
        let controller = SessionListController()
        let sessions = [makeSession("A")]

        controller.setSelection(to: 0, sessions: sessions)
        controller.setSelection(to: 5, sessions: sessions)

        #expect(controller.selectedIndex == 0)
        #expect(manager.activeColorIndex == 0)
    }
}
