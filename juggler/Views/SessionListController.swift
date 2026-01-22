import SwiftUI

@Observable
final class SessionListController {
    var selectedIndex: Int?
    var sessionToRename: Session?

    // Track selection by session ID so reorder doesn't lose it
    private var selectedSessionID: String?

    // Shortcuts — refreshed via reloadShortcuts()
    private(set) var shortcutMoveDown: LocalShortcut?
    private(set) var shortcutMoveUp: LocalShortcut?
    private(set) var shortcutBackburner: LocalShortcut?
    private(set) var shortcutReactivateSelected: LocalShortcut?
    private(set) var shortcutReactivateAll: LocalShortcut?
    private(set) var shortcutRename: LocalShortcut?
    private(set) var shortcutCycleModeForward: LocalShortcut?
    private(set) var shortcutCycleModeBackward: LocalShortcut?

    init() {
        reloadShortcuts()
    }

    func reloadShortcuts() {
        shortcutMoveDown = LocalShortcut.load(from: AppStorageKeys.localShortcutMoveDown)
        shortcutMoveUp = LocalShortcut.load(from: AppStorageKeys.localShortcutMoveUp)
        shortcutBackburner = LocalShortcut.load(from: AppStorageKeys.localShortcutBackburner)
        shortcutReactivateSelected = LocalShortcut.load(from: AppStorageKeys.localShortcutReactivateSelected)
        shortcutReactivateAll = LocalShortcut.load(from: AppStorageKeys.localShortcutReactivateAll)
        shortcutRename = LocalShortcut.load(from: AppStorageKeys.localShortcutRename)
        shortcutCycleModeForward = LocalShortcut.load(from: AppStorageKeys.localShortcutCycleModeForward)
        shortcutCycleModeBackward = LocalShortcut.load(from: AppStorageKeys.localShortcutCycleModeBackward)
    }

    // MARK: - Selection

    func moveSelection(by delta: Int, sessionCount: Int) {
        guard sessionCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = (current + delta + sessionCount) % sessionCount
        } else {
            selectedIndex = delta > 0 ? 0 : sessionCount - 1
        }
    }

    /// Sync selection to the current sessions array, preserving selection by ID across reorders.
    func syncSelection(sessions: [Session]) {
        if let id = selectedSessionID,
           let newIndex = sessions.firstIndex(where: { $0.id == id })
        {
            selectedIndex = newIndex
        } else if sessions.isEmpty {
            selectedIndex = nil
        } else if selectedIndex == nil || selectedIndex! >= sessions.count {
            selectedIndex = 0
        }
        selectedSessionID = selectedIndex.flatMap { idx in
            idx < sessions.count ? sessions[idx].id : nil
        }
    }

    /// Call after selectedIndex changes to keep the session ID in sync.
    func trackSelectedSession(sessions: [Session]) {
        selectedSessionID = selectedIndex.flatMap { idx in
            idx < sessions.count ? sessions[idx].id : nil
        }
    }

    // MARK: - Actions

    func backburnerSelected(sessionManager: SessionManager) {
        guard let index = selectedIndex,
              index < sessionManager.sessions.count else { return }
        let session = sessionManager.sessions[index]
        sessionManager.backburnerSession(terminalSessionID: session.id)
    }

    func reactivateSelected(sessionManager: SessionManager) {
        guard let index = selectedIndex,
              index < sessionManager.sessions.count else { return }
        let session = sessionManager.sessions[index]
        sessionManager.reactivateSession(terminalSessionID: session.id)
    }

    func reactivateAll(sessionManager: SessionManager) {
        sessionManager.reactivateAllBackburnered()
    }

    func renameSelected(sessions: [Session]) {
        guard let index = selectedIndex,
              index < sessions.count else { return }
        sessionToRename = sessions[index]
    }

    func cycleMode(forward: Bool, currentMode: String) -> String {
        let modes = QueueOrderMode.allCases
        guard let current = QueueOrderMode(rawValue: currentMode),
              let currentIdx = modes.firstIndex(of: current)
        else { return currentMode }
        let newIdx = forward
            ? (currentIdx + 1) % modes.count
            : (currentIdx - 1 + modes.count) % modes.count
        return modes[newIdx].rawValue
    }

    // MARK: - Key Handling

    /// Handle shared key press. Returns .handled or .ignored.
    func handleKeyPress(_ press: KeyPress, sessionManager: SessionManager, queueOrderMode: inout String) -> KeyPress
        .Result
    {
        if let shortcut = shortcutMoveDown, shortcut.matches(press) {
            moveSelection(by: 1, sessionCount: sessionManager.sessions.count)
            trackSelectedSession(sessions: sessionManager.sessions)
            return .handled
        } else if let shortcut = shortcutMoveUp, shortcut.matches(press) {
            moveSelection(by: -1, sessionCount: sessionManager.sessions.count)
            trackSelectedSession(sessions: sessionManager.sessions)
            return .handled
        } else if let shortcut = shortcutBackburner, shortcut.matches(press) {
            backburnerSelected(sessionManager: sessionManager)
            return .handled
        } else if let shortcut = shortcutReactivateSelected, shortcut.matches(press) {
            reactivateSelected(sessionManager: sessionManager)
            return .handled
        } else if let shortcut = shortcutReactivateAll, shortcut.matches(press) {
            reactivateAll(sessionManager: sessionManager)
            return .handled
        } else if let shortcut = shortcutRename, shortcut.matches(press) {
            renameSelected(sessions: sessionManager.sessions)
            return .handled
        } else if let shortcut = shortcutCycleModeForward, shortcut.matches(press) {
            queueOrderMode = cycleMode(forward: true, currentMode: queueOrderMode)
            return .handled
        } else if let shortcut = shortcutCycleModeBackward, shortcut.matches(press) {
            queueOrderMode = cycleMode(forward: false, currentMode: queueOrderMode)
            return .handled
        }
        return .ignored
    }
}
