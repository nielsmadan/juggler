import Carbon.HIToolbox
import SwiftUI

@Observable
final class SessionListController {
    var selectedIndex: Int?
    var sessionToRename: Session?

    // Track selection by session ID so reorder doesn't lose it
    private var selectedSessionID: String?

    // NSEvent monitor needed because SwiftUI intercepts Tab before onKeyPress
    private var tabEventMonitor: Any?

    // Shortcuts — refreshed via reloadShortcuts()
    private(set) var shortcutMoveDown: LocalShortcut?
    private(set) var shortcutMoveUp: LocalShortcut?
    private(set) var shortcutBackburner: LocalShortcut?
    private(set) var shortcutReactivateSelected: LocalShortcut?
    private(set) var shortcutReactivateAll: LocalShortcut?
    private(set) var shortcutRename: LocalShortcut?
    private(set) var shortcutCycleModeForward: LocalShortcut?
    private(set) var shortcutCycleModeBackward: LocalShortcut?
    private(set) var shortcutTogglePause: LocalShortcut?
    private(set) var shortcutResetStats: LocalShortcut?
    private(set) var shortcutToggleBeacon: LocalShortcut?
    private(set) var shortcutToggleAutoNext: LocalShortcut?

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
        shortcutTogglePause = LocalShortcut.load(from: AppStorageKeys.localShortcutTogglePause)
            ?? LocalShortcut(keyCode: 1, modifiers: []) // S
        shortcutResetStats = LocalShortcut.load(from: AppStorageKeys.localShortcutResetStats)
            ?? LocalShortcut(keyCode: 1, modifiers: .shift) // ⇧S
        shortcutToggleBeacon = LocalShortcut.load(from: AppStorageKeys.localShortcutToggleBeacon)
            ?? LocalShortcut(keyCode: 11, modifiers: []) // B
        shortcutToggleAutoNext = LocalShortcut.load(from: AppStorageKeys.localShortcutToggleAutoNext)
            ?? LocalShortcut(keyCode: 0, modifiers: []) // A
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

    // MARK: - Tab Event Monitor

    /// Install a local NSEvent monitor for Tab key events (Tab is intercepted by SwiftUI's focus system).
    /// The `extraHandler` closure lets the calling view handle view-specific shortcuts (e.g. togglePause/resetStats).
    func installTabMonitor(
        sessionManager: SessionManager,
        queueOrderMode: Binding<String>,
        extraHandler: ((NSEvent) -> Bool)? = nil
    ) {
        removeTabMonitor()
        tabEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == UInt16(kVK_Tab) else { return event }
            guard !LocalShortcutRecorderField.isAnyRecording else { return event }
            guard event.window?.isKeyWindow == true else { return event }
            guard hasShortcutForKeyCode(UInt16(kVK_Tab)) else { return event }
            var mode = queueOrderMode.wrappedValue
            if handleKeyEvent(event, sessionManager: sessionManager, queueOrderMode: &mode) {
                queueOrderMode.wrappedValue = mode
                return nil
            }
            if let extraHandler, extraHandler(event) {
                return nil
            }
            return event
        }
    }

    func removeTabMonitor() {
        if let monitor = tabEventMonitor {
            NSEvent.removeMonitor(monitor)
            tabEventMonitor = nil
        }
    }

    // MARK: - Key Handling

    /// Whether any configured shortcut uses the given key code (used to decide if NSEvent monitor should intercept)
    func hasShortcutForKeyCode(_ keyCode: UInt16) -> Bool {
        let all: [LocalShortcut?] = [
            shortcutMoveDown, shortcutMoveUp, shortcutBackburner,
            shortcutReactivateSelected, shortcutReactivateAll, shortcutRename,
            shortcutCycleModeForward, shortcutCycleModeBackward,
            shortcutTogglePause, shortcutResetStats,
            shortcutToggleAutoNext,
        ]
        return all.contains { $0?.keyCode == keyCode }
    }

    /// Handle NSEvent for keys intercepted before SwiftUI's focus system (e.g. Tab).
    /// Returns true if handled.
    func handleKeyEvent(_ event: NSEvent, sessionManager: SessionManager, queueOrderMode: inout String) -> Bool {
        if let shortcut = shortcutMoveDown, shortcut.matches(event) {
            moveSelection(by: 1, sessionCount: sessionManager.sessions.count)
            trackSelectedSession(sessions: sessionManager.sessions)
            return true
        } else if let shortcut = shortcutMoveUp, shortcut.matches(event) {
            moveSelection(by: -1, sessionCount: sessionManager.sessions.count)
            trackSelectedSession(sessions: sessionManager.sessions)
            return true
        } else if let shortcut = shortcutBackburner, shortcut.matches(event) {
            backburnerSelected(sessionManager: sessionManager)
            return true
        } else if let shortcut = shortcutReactivateSelected, shortcut.matches(event) {
            reactivateSelected(sessionManager: sessionManager)
            return true
        } else if let shortcut = shortcutReactivateAll, shortcut.matches(event) {
            reactivateAll(sessionManager: sessionManager)
            return true
        } else if let shortcut = shortcutRename, shortcut.matches(event) {
            renameSelected(sessions: sessionManager.sessions)
            return true
        } else if let shortcut = shortcutCycleModeForward, shortcut.matches(event) {
            queueOrderMode = cycleMode(forward: true, currentMode: queueOrderMode)
            return true
        } else if let shortcut = shortcutCycleModeBackward, shortcut.matches(event) {
            queueOrderMode = cycleMode(forward: false, currentMode: queueOrderMode)
            return true
        }
        return false
    }

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
