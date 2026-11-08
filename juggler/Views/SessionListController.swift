import AppKit
import SwiftUI

@Observable
final class SessionListController {
    struct SelectionSource: Equatable {
        let currentSessionID: String?
        let listedSessionIDs: [String]
        let hiddenSessionIDs: Set<String>

        init(currentSessionID: String?, listedSessions: [Session]) {
            self.currentSessionID = currentSessionID
            listedSessionIDs = listedSessions.map(\.id)
            hiddenSessionIDs = Set(listedSessions.filter(\.isHidden).map(\.id))
        }

        init(sessionManager: SessionManager) {
            let listed = sessionManager.listedSessions
            let focused = SessionListController.listedSession(matching: sessionManager.focusedSessionID, in: listed)
            self.init(currentSessionID: focused?.id ?? sessionManager.currentSession?.id, listedSessions: listed)
        }
    }

    /// The selected session, tracked by id so selection follows the session
    /// across reorders and matches the rendered (visible) row order rather than
    /// the raw `sessions` array index.
    var selectedSessionID: String?
    var sessionToRename: Session?
    var sessionToEditNote: Session?
    private var renderedSessionIDs: [String] = []

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
        renderedSessionIDs = ids
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

    func syncSelection(
        sessions: [Session],
        renderedSessions: [Session]? = nil,
        clearsColorWhenEmpty: Bool = true
    ) {
        let previousID = selectedSessionID
        let renderedIDs = (renderedSessions ?? sessions).map(\.id)
        if sessions.isEmpty {
            selectedSessionID = nil
            if clearsColorWhenEmpty { SessionManager.shared.clearColorIndex() }
        } else if let id = selectedSessionID, sessions.contains(where: { $0.id == id }) {
            // Selected session still present — nothing to do.
        } else {
            selectedSessionID = replacementSelection(in: renderedIDs) ?? sessions.first?.id
        }
        if selectedSessionID == nil || renderedIDs.contains(where: { $0 == selectedSessionID }) {
            renderedSessionIDs = renderedIDs
        }
        if previousID != selectedSessionID {
            logDebug(.navigation, "syncSelection: \(previousID ?? "nil") → \(selectedSessionID ?? "nil")")
        }
    }

    private func replacementSelection(in availableIDs: [String]) -> String? {
        guard let selectedSessionID, let index = renderedSessionIDs.firstIndex(of: selectedSessionID) else {
            return availableIDs.first
        }
        let available = Set(availableIDs)
        return renderedSessionIDs.dropFirst(index + 1).first(where: { available.contains($0) })
            ?? renderedSessionIDs.prefix(index).reversed().first(where: { available.contains($0) })
            ?? availableIDs.first
    }

    func syncMonitorSelection(sessionManager: SessionManager) {
        syncSelection(
            sessions: sessionManager.listedSessions,
            renderedSessions: sessionManager.orderedVisibleSessions()
        )
    }

    func selectListedSession(matching id: String?, in sessions: [Session], syncColor: Bool = true) {
        guard let session = Self.listedSession(matching: id, in: sessions) else { return }
        setSelection(toSessionID: session.id, syncColor: syncColor)
    }

    private static func listedSession(matching id: String?, in sessions: [Session]) -> Session? {
        guard let id else { return nil }
        return sessions.first(where: { $0.id == id })
            ?? sessions.first(where: { $0.terminalSessionID == id || $0.terminalSessionID.hasSuffix(":\(id)") })
    }

    func syncPopoverSelection(sessionManager: SessionManager) {
        let listed = sessionManager.listedSessions
        syncSelection(sessions: listed, clearsColorWhenEmpty: false)
        let target = Self.listedSession(matching: sessionManager.focusedSessionID, in: listed)
            ?? Self.listedSession(matching: sessionManager.currentReferenceSessionID, in: listed)
        if let target { setSelection(toSessionID: target.id, syncColor: false) }
    }

    func syncCurrentSelection(from previous: SelectionSource, to current: SelectionSource, sessions: [Session]) {
        guard previous.currentSessionID != current.currentSessionID,
              previous.listedSessionIDs == current.listedSessionIDs,
              previous.hiddenSessionIDs == current.hiddenSessionIDs else { return }
        selectListedSession(matching: current.currentSessionID, in: sessions)
    }

    func selectedSession(in sessions: [Session]) -> Session? {
        sessions.first { $0.id == selectedSessionID }
    }

    func toggleHidden(sessionID: String, sessionManager: SessionManager) {
        guard sessionManager.listedSessions.contains(where: { $0.id == sessionID }) else { return }
        syncMonitorSelection(sessionManager: sessionManager)
        sessionManager.toggleSessionHidden(sessionID: sessionID)
        syncMonitorSelection(sessionManager: sessionManager)
    }

    func toggleHiddenVisibility(sessionManager: SessionManager) {
        syncMonitorSelection(sessionManager: sessionManager)
        sessionManager.showsHiddenSessions.toggle()
        syncMonitorSelection(sessionManager: sessionManager)
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

    func editNoteSelected(sessions: [Session]) {
        guard let id = selectedSessionID,
              let session = sessions.first(where: { $0.id == id }) else { return }
        sessionToEditNote = session
    }

    @discardableResult
    func performContextAction(
        _ action: SessionRowContextAction,
        on session: Session,
        sessionManager: SessionManager
    ) -> SessionListAction {
        setSelection(toSessionID: session.id, syncColor: false)
        switch action {
        case .rename:
            sessionToRename = session
        case .editNote:
            sessionToEditNote = session
        case .backburner:
            sessionManager.backburnerSession(terminalSessionID: session.id)
        case .reactivate:
            sessionManager.reactivateSession(terminalSessionID: session.id)
        }
        return action.shortcutAction
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
