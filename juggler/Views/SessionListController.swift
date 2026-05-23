import ShortcutField
import SwiftUI

@Observable
final class SessionListController {
    var selectedIndex: Int?
    var sessionToRename: Session?

    // Track selection by session ID so reorder doesn't lose it
    private var selectedSessionID: String?

    // Local NSEvent monitor — feeds every keydown to the matchers. A stateful
    // ShortcutMatcher must see every event to advance, not just the keys
    // SwiftUI's focus system forwards to `.onKeyPress`.
    private var keyEventMonitor: Any?

    private(set) var shortcutMoveDown: DiscreteShortcut?
    private(set) var shortcutMoveUp: DiscreteShortcut?
    private(set) var shortcutBackburner: DiscreteShortcut?
    private(set) var shortcutReactivateSelected: DiscreteShortcut?
    private(set) var shortcutReactivateAll: DiscreteShortcut?
    private(set) var shortcutRename: DiscreteShortcut?
    private(set) var shortcutCycleModeForward: DiscreteShortcut?
    private(set) var shortcutCycleModeBackward: DiscreteShortcut?
    private(set) var shortcutToggleBeacon: DiscreteShortcut?
    private(set) var shortcutToggleAutoNext: DiscreteShortcut?
    private(set) var shortcutToggleAutoRestart: DiscreteShortcut?

    // Stateful matchers — required for multi-step sequences (e.g. `A → T`)
    // because a step-by-step matcher needs to remember progress across events.
    @ObservationIgnored private(set) var matcherMoveDown: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherMoveUp: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherBackburner: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherReactivateSelected: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherReactivateAll: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherRename: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherCycleModeForward: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherCycleModeBackward: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherToggleAutoNext: ShortcutMatcher?
    @ObservationIgnored private(set) var matcherToggleAutoRestart: ShortcutMatcher?

    init() {
        reloadShortcuts()
    }

    func reloadShortcuts() {
        shortcutMoveDown = DiscreteShortcut.load(from: AppStorageKeys.localShortcutMoveDown)
        shortcutMoveUp = DiscreteShortcut.load(from: AppStorageKeys.localShortcutMoveUp)
        shortcutBackburner = DiscreteShortcut.load(from: AppStorageKeys.localShortcutBackburner)
        shortcutReactivateSelected = DiscreteShortcut.load(from: AppStorageKeys.localShortcutReactivateSelected)
        shortcutReactivateAll = DiscreteShortcut.load(from: AppStorageKeys.localShortcutReactivateAll)
        shortcutRename = DiscreteShortcut.load(from: AppStorageKeys.localShortcutRename)
        shortcutCycleModeForward = DiscreteShortcut.load(from: AppStorageKeys.localShortcutCycleModeForward)
        shortcutCycleModeBackward = DiscreteShortcut.load(from: AppStorageKeys.localShortcutCycleModeBackward)
        shortcutToggleBeacon = DiscreteShortcut.load(from: AppStorageKeys.localShortcutToggleBeacon)
            ?? DiscreteShortcut(keyCode: 11, modifiers: []) // B
        shortcutToggleAutoNext = DiscreteShortcut.load(from: AppStorageKeys.localShortcutToggleAutoNext)
            ?? DiscreteShortcut(keyCode: 0, modifiers: []) // A
        shortcutToggleAutoRestart = DiscreteShortcut.load(from: AppStorageKeys.localShortcutToggleAutoRestart)
            ?? DiscreteShortcut(keyCode: 12, modifiers: []) // Q

        matcherMoveDown = shortcutMoveDown.map { ShortcutMatcher(.discrete($0)) }
        matcherMoveUp = shortcutMoveUp.map { ShortcutMatcher(.discrete($0)) }
        matcherBackburner = shortcutBackburner.map { ShortcutMatcher(.discrete($0)) }
        matcherReactivateSelected = shortcutReactivateSelected.map { ShortcutMatcher(.discrete($0)) }
        matcherReactivateAll = shortcutReactivateAll.map { ShortcutMatcher(.discrete($0)) }
        matcherRename = shortcutRename.map { ShortcutMatcher(.discrete($0)) }
        matcherCycleModeForward = shortcutCycleModeForward.map { ShortcutMatcher(.discrete($0)) }
        matcherCycleModeBackward = shortcutCycleModeBackward.map { ShortcutMatcher(.discrete($0)) }
        matcherToggleAutoNext = shortcutToggleAutoNext.map { ShortcutMatcher(.discrete($0)) }
        matcherToggleAutoRestart = shortcutToggleAutoRestart.map { ShortcutMatcher(.discrete($0)) }
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

    // MARK: - Key Event Monitor

    /// Install a local NSEvent monitor that feeds every keydown to the configured
    /// matchers. This is what makes multi-step sequences (e.g. `A → T`) work:
    /// `ShortcutMatcher` is stateful and needs to see every event to advance,
    /// not just keys SwiftUI's `.onKeyPress` happens to forward.
    ///
    /// The `extraHandler` closure lets the calling view handle view-specific
    /// shortcuts on the same event stream.
    func installKeyMonitor(
        sessionManager: SessionManager,
        queueOrderMode: Binding<String>,
        extraHandler: ((NSEvent) -> Bool)? = nil
    ) {
        removeKeyMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !ShortcutRecording.isActive else { return event }
            guard event.window?.isKeyWindow == true else { return event }
            // Don't steal keystrokes while a text field is being edited (e.g. the
            // rename sheet) — the field editor is the window's first responder then.
            if event.window?.firstResponder is NSText { return event }
            var mode = queueOrderMode.wrappedValue
            var handled = handleKeyEvent(event, sessionManager: sessionManager, queueOrderMode: &mode)
            queueOrderMode.wrappedValue = mode
            if let extraHandler, extraHandler(event) {
                handled = true
            }
            return handled ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - Key Handling

    /// Feed a key event to every configured matcher. Returns true if the event
    /// should be consumed.
    ///
    /// Every matcher must see every event so prefix-sharing multi-step sequences
    /// all advance together. Completed matches are collected and only the first
    /// fires, so a single keystroke never triggers two list actions.
    func handleKeyEvent(_ event: NSEvent, sessionManager: SessionManager, queueOrderMode: inout String) -> Bool {
        // Cycle-mode actions can't capture the `inout` binding, so they write the
        // result into `newMode`, applied once after dispatch.
        let currentMode = queueOrderMode
        var newMode: String?

        let bindings: [(ShortcutMatcher?, () -> Void)] = [
            (matcherMoveDown, {
                self.moveSelection(by: 1, sessionCount: sessionManager.sessions.count)
                self.trackSelectedSession(sessions: sessionManager.sessions)
            }),
            (matcherMoveUp, {
                self.moveSelection(by: -1, sessionCount: sessionManager.sessions.count)
                self.trackSelectedSession(sessions: sessionManager.sessions)
            }),
            (matcherBackburner, { self.backburnerSelected(sessionManager: sessionManager) }),
            (matcherReactivateSelected, { self.reactivateSelected(sessionManager: sessionManager) }),
            (matcherReactivateAll, { self.reactivateAll(sessionManager: sessionManager) }),
            (matcherRename, { self.renameSelected(sessions: sessionManager.sessions) }),
            (matcherCycleModeForward, { newMode = self.cycleMode(forward: true, currentMode: currentMode) }),
            (matcherCycleModeBackward, { newMode = self.cycleMode(forward: false, currentMode: currentMode) })
        ]

        var handled = false
        var firedAction: (() -> Void)?
        for (matcher, action) in bindings {
            switch matcher?.handle(event) ?? .ignored {
            case .ignored: continue
            case let .advanced(consumeEvent):
                if consumeEvent { handled = true }
            case .fired:
                handled = true
                if firedAction == nil { firedAction = action }
            case .continuousFired:
                handled = true
            }
        }

        firedAction?()
        if let newMode { queueOrderMode = newMode }
        return handled
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
