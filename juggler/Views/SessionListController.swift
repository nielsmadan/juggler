import Carbon.HIToolbox
import ShortcutField
import SwiftUI

@Observable
final class SessionListController {
    var selectedIndex: Int?
    var sessionToRename: Session?

    // Track selection by session ID so reorder doesn't lose it
    private var selectedSessionID: String?

    // NSEvent monitor needed because SwiftUI intercepts Tab before onKeyPress
    private var tabEventMonitor: Any?

    private(set) var shortcutMoveDown: Shortcut?
    private(set) var shortcutMoveUp: Shortcut?
    private(set) var shortcutBackburner: Shortcut?
    private(set) var shortcutReactivateSelected: Shortcut?
    private(set) var shortcutReactivateAll: Shortcut?
    private(set) var shortcutRename: Shortcut?
    private(set) var shortcutCycleModeForward: Shortcut?
    private(set) var shortcutCycleModeBackward: Shortcut?
    private(set) var shortcutTogglePause: Shortcut?
    private(set) var shortcutResetStats: Shortcut?
    private(set) var shortcutToggleBeacon: Shortcut?
    private(set) var shortcutToggleAutoNext: Shortcut?
    private(set) var shortcutToggleAutoRestart: Shortcut?

    init() {
        reloadShortcuts()
    }

    func reloadShortcuts() {
        shortcutMoveDown = Shortcut.load(from: AppStorageKeys.localShortcutMoveDown)
        shortcutMoveUp = Shortcut.load(from: AppStorageKeys.localShortcutMoveUp)
        shortcutBackburner = Shortcut.load(from: AppStorageKeys.localShortcutBackburner)
        shortcutReactivateSelected = Shortcut.load(from: AppStorageKeys.localShortcutReactivateSelected)
        shortcutReactivateAll = Shortcut.load(from: AppStorageKeys.localShortcutReactivateAll)
        shortcutRename = Shortcut.load(from: AppStorageKeys.localShortcutRename)
        shortcutCycleModeForward = Shortcut.load(from: AppStorageKeys.localShortcutCycleModeForward)
        shortcutCycleModeBackward = Shortcut.load(from: AppStorageKeys.localShortcutCycleModeBackward)
        shortcutTogglePause = Shortcut.load(from: AppStorageKeys.localShortcutTogglePause)
            ?? Shortcut(keyCode: 1, modifiers: []) // S
        shortcutResetStats = Shortcut.load(from: AppStorageKeys.localShortcutResetStats)
            ?? Shortcut(keyCode: 1, modifiers: .shift) // ⇧S
        shortcutToggleBeacon = Shortcut.load(from: AppStorageKeys.localShortcutToggleBeacon)
            ?? Shortcut(keyCode: 11, modifiers: []) // B
        shortcutToggleAutoNext = Shortcut.load(from: AppStorageKeys.localShortcutToggleAutoNext)
            ?? Shortcut(keyCode: 0, modifiers: []) // A
        shortcutToggleAutoRestart = Shortcut.load(from: AppStorageKeys.localShortcutToggleAutoRestart)
            ?? Shortcut(keyCode: 12, modifiers: []) // Q
    }

    // MARK: - Selection

    func moveSelection(by delta: Int, sessionCount: Int) {
        guard sessionCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = (current + delta + sessionCount) % sessionCount
        } else {
            selectedIndex = delta > 0 ? 0 : sessionCount - 1
        }
        SessionManager.shared.advanceColorIndex(by: delta > 0 ? 1 : -1)
    }

    /// Sync selection to the current sessions array, preserving selection by ID across reorders.
    func syncSelection(sessions: [Session]) {
        if let id = selectedSessionID,
           let newIndex = sessions.firstIndex(where: { $0.id == id }) {
            // Session found at new position — update index, color stays (managed by SessionManager)
            selectedIndex = newIndex
        } else if sessions.isEmpty {
            selectedIndex = nil
            SessionManager.shared.clearColorIndex()
        } else if let idx = selectedIndex, idx < sessions.count {
            // Selected session was removed but index is still in bounds — retarget, reset color
            SessionManager.shared.setColorIndex(to: idx)
        } else {
            // Index out of bounds or nil — fall back to 0
            selectedIndex = 0
            SessionManager.shared.clearColorIndex()
        }
        selectedSessionID = selectedIndex.flatMap { idx in
            idx < sessions.count ? sessions[idx].id : nil
        }
    }

    /// Set selection explicitly (e.g., from external focus changes).
    /// Skips color reset when an activation is in flight (hotkey or click already set the color)
    /// or when the selection didn't actually change (echo from Enter key).
    func setSelection(to index: Int, sessions: [Session]) {
        guard index >= 0, index < sessions.count else { return }
        if selectedIndex != index, SessionManager.shared.activationTarget == nil {
            SessionManager.shared.setColorIndex(to: index)
        }
        selectedIndex = index
        trackSelectedSession(sessions: sessions)
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
            guard !ShortcutRecorderField.isAnyRecording else { return event }
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
        let all: [Shortcut?] = [
            shortcutMoveDown, shortcutMoveUp, shortcutBackburner,
            shortcutReactivateSelected, shortcutReactivateAll, shortcutRename,
            shortcutCycleModeForward, shortcutCycleModeBackward,
            shortcutTogglePause, shortcutResetStats,
            shortcutToggleAutoNext, shortcutToggleAutoRestart
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

    func handleKeyPress(_ press: KeyPress, sessionManager: SessionManager, queueOrderMode: inout String) -> KeyPress
        .Result {
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
