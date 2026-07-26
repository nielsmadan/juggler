import AppKit
import SwiftUI

@Observable
final class SessionListController {
    /// The selected session, tracked by id so selection follows the session
    /// across reorders and matches the rendered (visible) row order rather than
    /// the raw `sessions` array index.
    var selectedSessionID: String?
    var sessionToRename: Session?

    /// The window hosting this controller's view. Set by `WindowAccessor`; used
    /// by the view to gate session-list shortcut activation on key-window state.
    @ObservationIgnored weak var ownWindow: NSWindow?

    // Debug label identifying which view owns this controller (e.g. "Monitor"
    // vs "MenuBar"), so logs disambiguate the two instances.
    @ObservationIgnored var ownerLabel = ""

    init() {}

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
}
