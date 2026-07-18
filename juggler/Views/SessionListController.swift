import ShortcutField
import SwiftUI

@Observable
final class SessionListController {
    /// The selected session, tracked by id so selection follows the session
    /// across reorders and matches the rendered (visible) row order rather than
    /// the raw `sessions` array index.
    var selectedSessionID: String?
    var sessionToRename: Session?

    // Local NSEvent monitor — feeds every keydown to the matchers. A stateful
    // ShortcutMatcher must see every event to advance, not just the keys
    // SwiftUI's focus system forwards to `.onKeyPress`.
    private var keyEventMonitor: Any?

    /// Supplies the current visible/rendered session order for the monitor's
    /// key path (the SwiftUI `.onKeyPress` path passes the list in directly).
    /// Set in `installKeyMonitor`; reads live singletons so it never goes stale.
    @ObservationIgnored var visibleSessionsProvider: () -> [Session] = { [] }

    /// The window hosting this controller's view. The key monitor only acts on
    /// events for this window, so the menu-bar popover's monitor can't steal
    /// keystrokes meant for the main window (and vice-versa).
    @ObservationIgnored weak var ownWindow: NSWindow?

    // Debug label identifying which view owns this controller/monitor (e.g.
    // "Monitor" vs "MenuBar"), so logs disambiguate the two instances.
    private var ownerLabel = ""

    private(set) var shortcutMoveDown: DiscreteShortcut?
    private(set) var shortcutMoveUp: DiscreteShortcut?
    private(set) var shortcutBackburner: DiscreteShortcut?
    private(set) var shortcutSendToBack: DiscreteShortcut?
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
    @ObservationIgnored private(set) var matcherSendToBack: ShortcutMatcher?
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
        shortcutSendToBack = DiscreteShortcut.load(from: AppStorageKeys.localShortcutSendToBack)
            ?? DiscreteShortcut(keyCode: 31, modifiers: []) // O
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

        // A move binding that loads as `nil` (these have no default) means that
        // direction's key is unbound — it falls through and beeps. Logging the
        // resolved bindings makes an asymmetric/missing mapping obvious.
        logDebug(
            .navigation,
            "reloadShortcuts: moveUp=\(shortcutMoveUp?.displayString ?? "nil") "
                + "moveDown=\(shortcutMoveDown?.displayString ?? "nil") "
                + "backburner=\(shortcutBackburner?.displayString ?? "nil") "
                + "reactivate=\(shortcutReactivateSelected?.displayString ?? "nil") "
                + "rename=\(shortcutRename?.displayString ?? "nil")"
        )

        matcherMoveDown = shortcutMoveDown.map { ShortcutMatcher(.discrete($0)) }
        matcherMoveUp = shortcutMoveUp.map { ShortcutMatcher(.discrete($0)) }
        matcherBackburner = shortcutBackburner.map { ShortcutMatcher(.discrete($0)) }
        matcherSendToBack = shortcutSendToBack.map { ShortcutMatcher(.discrete($0)) }
        matcherReactivateSelected = shortcutReactivateSelected.map { ShortcutMatcher(.discrete($0)) }
        matcherReactivateAll = shortcutReactivateAll.map { ShortcutMatcher(.discrete($0)) }
        matcherRename = shortcutRename.map { ShortcutMatcher(.discrete($0)) }
        matcherCycleModeForward = shortcutCycleModeForward.map { ShortcutMatcher(.discrete($0)) }
        matcherCycleModeBackward = shortcutCycleModeBackward.map { ShortcutMatcher(.discrete($0)) }
        matcherToggleAutoNext = shortcutToggleAutoNext.map { ShortcutMatcher(.discrete($0)) }
        matcherToggleAutoRestart = shortcutToggleAutoRestart.map { ShortcutMatcher(.discrete($0)) }
    }

    // MARK: - Selection

    /// Move the selection within the given visible (rendered) session order.
    /// Selection is tracked by id, so it follows what's on screen rather than the
    /// raw `sessions` array index (the two diverge — see `orderedVisibleSessions`).
    func moveSelection(by delta: Int, in visible: [Session]) {
        let previousID = selectedSessionID
        guard !visible.isEmpty else {
            logDebug(.navigation, "moveSelection(by: \(delta)) ignored — no visible sessions")
            return
        }
        let ids = visible.map(\.id)
        // If the selected session exists but isn't currently rendered (e.g. it's
        // mid section-animation, so it's absent from the visible list), don't jump
        // to first/last — hold the selection until the row reappears.
        if let currentID = selectedSessionID, !ids.contains(currentID) {
            logDebug(
                .navigation,
                "moveSelection[\(ownerLabel)](by: \(delta)) held — selected \(currentID) not in visible"
            )
            return
        }
        let newID: String = if let currentID = selectedSessionID, let idx = ids.firstIndex(of: currentID) {
            ids[(idx + delta + ids.count) % ids.count]
        } else {
            delta > 0 ? ids[0] : ids[ids.count - 1]
        }
        selectedSessionID = newID
        SessionManager.shared.advanceColorIndex(by: delta > 0 ? 1 : -1)
        logDebug(
            .navigation,
            "moveSelection[\(ownerLabel)](by: \(delta)): \(previousID ?? "nil") → \(newID) "
                + "(visible=\(ids.count), colorIndex=\(SessionManager.shared.activeColorIndex))"
        )
    }

    /// Reconcile selection after the sessions list changes. id-based selection is
    /// inherently reorder-stable, so this only handles the selected session
    /// disappearing (fall back to the first visible row) or the list emptying.
    func syncSelection(sessions: [Session]) {
        let previousID = selectedSessionID
        if sessions.isEmpty {
            selectedSessionID = nil
            SessionManager.shared.clearColorIndex()
        } else if let id = selectedSessionID, sessions.contains(where: { $0.id == id }) {
            // Selected session still present — nothing to do.
        } else {
            // Selected session vanished — fall back to the first row. Color is an
            // independent cycling counter, so leave it untouched here.
            selectedSessionID = sessions.first?.id
        }
        if previousID != selectedSessionID {
            logDebug(.navigation, "syncSelection: \(previousID ?? "nil") → \(selectedSessionID ?? "nil")")
        }
    }

    /// Set selection explicitly to a session (e.g., from external focus changes).
    /// Skips the color reset when an activation is in flight (hotkey or click
    /// already set the color) or when the selection didn't actually change.
    ///
    /// `syncColor: false` sets selection without touching the global cycling
    /// `activeColorIndex` — used on popover open so a passive open doesn't retint
    /// the main monitor / beacon / terminal-tab highlight.
    func setSelection(toSessionID id: String, syncColor: Bool = true) {
        let previousID = selectedSessionID
        let activationInFlight = SessionManager.shared.activationTarget != nil
        var resetColor = false
        if syncColor, selectedSessionID != id, !activationInFlight {
            SessionManager.shared.syncColorIndex(toSessionID: id)
            resetColor = true
        }
        selectedSessionID = id
        logDebug(
            .navigation,
            "setSelection(toSessionID: \(id)): \(previousID ?? "nil") → \(id) "
                + "(resetColor=\(resetColor), activationInFlight=\(activationInFlight), "
                + "colorIndex=\(SessionManager.shared.activeColorIndex))"
        )
    }

    // MARK: - Actions

    func backburnerSelected(sessionManager: SessionManager) {
        guard let id = selectedSessionID else { return }
        sessionManager.backburnerSession(terminalSessionID: id)
    }

    func sendToBackSelected(sessionManager: SessionManager) {
        guard let id = selectedSessionID,
              let next = sessionManager.sendToBackOfQueue(sessionID: id) else { return }
        selectedSessionID = next.id
    }

    func reactivateSelected(sessionManager: SessionManager) {
        guard let id = selectedSessionID else { return }
        sessionManager.reactivateSession(terminalSessionID: id)
    }

    func reactivateAll(sessionManager: SessionManager) {
        sessionManager.reactivateAllBackburnered()
    }

    func renameSelected(sessions: [Session]) {
        guard let id = selectedSessionID,
              let session = sessions.first(where: { $0.id == id }) else { return }
        sessionToRename = session
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
        owner: String = "",
        sessionManager: SessionManager,
        queueOrderMode: Binding<String>,
        visibleSessions: @escaping () -> [Session],
        extraHandler: ((NSEvent) -> Bool)? = nil
    ) {
        removeKeyMonitor()
        ownerLabel = owner
        visibleSessionsProvider = visibleSessions
        logDebug(.navigation, "keyMonitor[\(owner)] installed (controller=\(ObjectIdentifier(self)))")
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !ShortcutRecording.isActive else {
                logDebug(.navigation, "keyMonitor[\(ownerLabel)] bail (recording active) keyCode=\(event.keyCode)")
                return event
            }
            // Only act on events for OUR window. `event.window` is whichever window
            // received the keystroke (the key window); requiring it to be our own
            // window stops a lingering popover monitor from stealing the main
            // window's keys (and vice-versa).
            guard let own = ownWindow, event.window === own else {
                logDebug(.navigation, "keyMonitor[\(ownerLabel)] bail (not own window) keyCode=\(event.keyCode)")
                return event
            }
            // Don't steal keystrokes while a text field is being edited (e.g. the
            // rename sheet) — the field editor is the window's first responder then.
            if event.window?.firstResponder is NSText {
                logDebug(
                    .navigation,
                    "keyMonitor[\(ownerLabel)] bail (firstResponder is NSText) keyCode=\(event.keyCode)"
                )
                return event
            }
            var mode = queueOrderMode.wrappedValue
            var handled = handleKeyEvent(event, sessionManager: sessionManager, queueOrderMode: &mode)
            queueOrderMode.wrappedValue = mode
            if let extraHandler, extraHandler(event) {
                handled = true
            }
            if !handled {
                // Event seen but not consumed by any list shortcut — it falls through
                // to SwiftUI's `.onKeyPress` (arrows) or the responder chain (beep if
                // nothing there is focused). `firstResponder` tells us where focus sits.
                let responder = event.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                logDebug(
                    .navigation,
                    "keyMonitor[\(ownerLabel)] passthrough keyCode=\(event.keyCode) (unhandled by list shortcuts; "
                        + "firstResponder=\(responder))"
                )
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

        let bindings: [(String, ShortcutMatcher?, () -> Void)] = [
            ("moveDown", matcherMoveDown, {
                self.moveSelection(by: 1, in: self.visibleSessionsProvider())
            }),
            ("moveUp", matcherMoveUp, {
                self.moveSelection(by: -1, in: self.visibleSessionsProvider())
            }),
            ("backburner", matcherBackburner, { self.backburnerSelected(sessionManager: sessionManager) }),
            ("sendToBack", matcherSendToBack, { self.sendToBackSelected(sessionManager: sessionManager) }),
            (
                "reactivateSelected",
                matcherReactivateSelected,
                { self.reactivateSelected(sessionManager: sessionManager) }
            ),
            ("reactivateAll", matcherReactivateAll, { self.reactivateAll(sessionManager: sessionManager) }),
            ("rename", matcherRename, { self.renameSelected(sessions: sessionManager.sessions) }),
            (
                "cycleModeForward",
                matcherCycleModeForward,
                { newMode = self.cycleMode(forward: true, currentMode: currentMode) }
            ),
            (
                "cycleModeBackward",
                matcherCycleModeBackward,
                { newMode = self.cycleMode(forward: false, currentMode: currentMode) }
            )
        ]

        var handled = false
        var firedAction: (() -> Void)?
        var firedLabel: String?
        for (label, matcher, action) in bindings {
            switch matcher?.handle(event) ?? .ignored {
            case .ignored: continue
            case let .advanced(consumeEvent):
                if consumeEvent { handled = true }
            case .fired:
                handled = true
                if firedAction == nil { firedAction = action; firedLabel = label }
            case .continuousFired:
                handled = true
            }
        }

        if let firedLabel {
            logDebug(.navigation, "keyMonitor[\(ownerLabel)] handled '\(firedLabel)' (keyCode=\(event.keyCode))")
        }
        firedAction?()
        if let newMode { queueOrderMode = newMode }
        return handled
    }

    func handleKeyPress(_ press: KeyPress, sessionManager: SessionManager, queueOrderMode: inout String) -> KeyPress
        .Result {
        if let shortcut = shortcutMoveDown, shortcut.matches(press) {
            logDebug(.navigation, "handleKeyPress matched moveDown (SwiftUI focus path)")
            moveSelection(by: 1, in: visibleSessionsProvider())
            return .handled
        } else if let shortcut = shortcutMoveUp, shortcut.matches(press) {
            logDebug(.navigation, "handleKeyPress matched moveUp (SwiftUI focus path)")
            moveSelection(by: -1, in: visibleSessionsProvider())
            return .handled
        } else if let shortcut = shortcutBackburner, shortcut.matches(press) {
            backburnerSelected(sessionManager: sessionManager)
            return .handled
        } else if let shortcut = shortcutSendToBack, shortcut.matches(press) {
            sendToBackSelected(sessionManager: sessionManager)
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
