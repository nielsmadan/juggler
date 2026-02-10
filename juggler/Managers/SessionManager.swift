import Foundation
import SwiftUI

@Observable
final class SessionManager {
    static let shared = SessionManager()

    // internal(set) to allow @testable import to manipulate sessions in tests
    private(set) var sessions: [Session] = []

    /// Test-only: directly set session properties. Only accessible via @testable import.
    func testSetSessions(_ newSessions: [Session]) {
        sessions = newSessions
    }

    private(set) var cyclingState = CyclingState.initial
    private(set) var focusedSessionID: String? // terminalSessionID of actually focused session in iTerm2
    private let cyclingEngine: CyclingEngine

    /// Animation controller for section transitions
    let animationController = SectionAnimationController()

    private var queueOrderMode: QueueOrderMode {
        let rawValue = UserDefaults.standard.string(forKey: "queueOrderMode") ?? QueueOrderMode.fair.rawValue
        return QueueOrderMode(rawValue: rawValue) ?? .fair
    }

    init() {
        cyclingEngine = DefaultCyclingEngine()

        // One-time migration of legacy queue order mode values
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "queueOrderMode") {
            if raw == "filo" {
                defaults.set(QueueOrderMode.fair.rawValue, forKey: "queueOrderMode")
            } else if raw == "fifo" {
                defaults.set(QueueOrderMode.prio.rawValue, forKey: "queueOrderMode")
            }
        }
    }

    // MARK: - Backwards compatibility computed properties

    var currentIndex: Int { cyclingState.currentIndex }
    var highlightColorIndex: Int { cyclingState.highlightColorIndex }

    // MARK: - State Transitions

    private func handleStateTransition(at index: Int, from oldState: SessionState, to newState: SessionState) {
        let sessionName = sessions[index].displayName
        Task { @MainActor in
            logDebug(.session, "\(sessionName): \(oldState.rawValue) → \(newState.rawValue)")
        }

        let wasIdle = oldState == .idle || oldState == .permission
        let isIdle = newState == .idle || newState == .permission

        // Leaving idle: accumulate the completed idle time
        if wasIdle, !isIdle {
            if let lastBecameIdle = sessions[index].lastBecameIdle {
                let idleDuration = Date().timeIntervalSince(lastBecameIdle)
                sessions[index].accumulatedIdleTime += idleDuration
            }
        }

        // Entering idle: mark timestamp
        if isIdle, !wasIdle {
            sessions[index].lastBecameIdle = Date()
        }

        let wasWorking = oldState == .working || oldState == .compacting
        let isWorking = newState == .working || newState == .compacting

        // Leaving working: accumulate the completed working time
        if wasWorking, !isWorking {
            if let lastBecameWorking = sessions[index].lastBecameWorking {
                let workingDuration = Date().timeIntervalSince(lastBecameWorking)
                sessions[index].accumulatedWorkingTime += workingDuration
            }
        }

        // Entering working: mark timestamp
        if isWorking, !wasWorking {
            sessions[index].lastBecameWorking = Date()
        }

        // Reorder for queue mode (no manual animation - List handles it)
        guard queueOrderMode != .static else { return }

        let wasBusy = oldState == .working || oldState == .compacting
        let isBusy = newState == .working || newState == .compacting
        let isBackburner = newState == .backburner
        let wasBackburner = oldState == .backburner

        // Determine target position
        var targetPosition: QueuePosition?
        if isBackburner, !wasBackburner {
            targetPosition = .bottomOfBackburner
        } else if isBusy, !wasBusy {
            targetPosition = .bottomOfBusy
        } else if isIdle, !wasIdle {
            targetPosition = queueOrderMode == .prio ? .topOfIdle : .bottomOfIdle
        }

        // Move session to correct position in array
        if let position = targetPosition {
            let targetIdx = targetIndex(for: position, in: sessions)
            if index != targetIdx {
                let session = sessions.remove(at: index)
                sessions.insert(session, at: min(targetIdx, sessions.count))
            }
        }
    }

    @MainActor
    private func applyStateChange(sessionID: String, from oldState: SessionState, to newState: SessionState) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        // Trigger animation (must be before state change so effectiveState works)
        animationController.animateTransition(
            sessionID: sessions[index].id,
            from: oldState,
            to: newState
        )

        let fromSection = SectionType(from: oldState)
        let toSection = SectionType(from: newState)
        let isUpMove = toSection.rawValue < fromSection.rawValue

        if isUpMove {
            withAnimation(.easeInOut(duration: SectionAnimationTiming.upMoveDuration)) {
                sessions[index].state = newState
                handleStateTransition(at: index, from: oldState, to: newState)
            }
        } else {
            sessions[index].state = newState
            handleStateTransition(at: index, from: oldState, to: newState)
        }
    }

    private func targetIndex(for position: QueuePosition, in sessions: [Session]) -> Int {
        switch position {
        case .topOfIdle:
            return 0
        case .bottomOfIdle:
            if let firstBusy = sessions.firstIndex(where: { $0.state == .working || $0.state == .compacting }) {
                return firstBusy
            }
            if let firstBackburner = sessions.firstIndex(where: { $0.state == .backburner }) {
                return firstBackburner
            }
            return sessions.count
        case .bottomOfBusy:
            if let firstBackburner = sessions.firstIndex(where: { $0.state == .backburner }) {
                return firstBackburner
            }
            return sessions.count
        case .bottomOfBackburner:
            return sessions.count
        }
    }

    func reorderForMode(_ mode: QueueOrderMode) {
        guard mode != .static else {
            sessions.sort { $0.startedAt < $1.startedAt }
            return
        }

        let idle = sessions.filter { $0.state == .idle || $0.state == .permission }
        let busy = sessions.filter { $0.state == .working || $0.state == .compacting }
        let backburner = sessions.filter { $0.state == .backburner }

        let sortedIdle = idle.sorted {
            switch mode {
            case .fair:
                ($0.lastBecameIdle ?? .distantPast) < ($1.lastBecameIdle ?? .distantPast)
            case .prio:
                ($0.lastBecameIdle ?? .distantPast) > ($1.lastBecameIdle ?? .distantPast)
            case .static:
                $0.startedAt < $1.startedAt
            }
        }

        sessions = sortedIdle + busy + backburner
    }

    var cyclableSessions: [Session] {
        sessions.filter(\.state.isIncludedInCycle)
    }

    var currentSession: Session? {
        let cyclable = cyclableSessions
        guard !cyclable.isEmpty else { return nil }

        // Prefer focused session if it's cyclable
        // Try composite id first (set from hook events), then terminalSessionID with hasSuffix for bare UUID focus
        // events
        if let focusedID = focusedSessionID,
           let session = cyclable.first(where: {
               $0.id == focusedID || $0.terminalSessionID == focusedID
                   || $0.terminalSessionID.hasSuffix(focusedID)
           }) {
            return session
        }

        // Fall back to index-based
        let safeIndex = cyclingState.currentIndex % cyclable.count
        return cyclable[safeIndex]
    }

    @MainActor
    func updateFocusedSession(terminalSessionID: String?) {
        // Don't let a bare UUID from iTerm2 focus events overwrite
        // a more specific composite ID (e.g., "w0t0p0:UUID:%1" contains "UUID")
        if let newID = terminalSessionID, let currentID = focusedSessionID,
           currentID != newID, currentID.contains(newID) {
            return
        }

        focusedSessionID = terminalSessionID

        if terminalSessionID != nil {
            cyclingState = cyclingEngine.syncStateToFocus(
                sessions: sessions,
                focusedSessionID: terminalSessionID,
                state: cyclingState
            )
        }
    }

    func addOrUpdateSession(
        claudeSessionID: String,
        terminalSessionID: String,
        tmuxPane: String? = nil,
        tmuxSessionName: String? = nil,
        terminalType: TerminalType = .iterm2,
        projectPath: String,
        state: SessionState,
        event: String? = nil,
        gitBranch: String? = nil,
        gitRepoName: String? = nil,
        transcriptPath: String? = nil
    ) {
        // Compute composite ID for lookup (includes tmux pane if present)
        let compositeID: String = if let pane = tmuxPane {
            "\(terminalSessionID):\(pane)"
        } else {
            terminalSessionID
        }

        // Key by composite ID for uniqueness - each terminal pane (including tmux) has unique ID
        if let index = sessions.firstIndex(where: { $0.id == compositeID }) {
            let oldState = sessions[index].state

            // Preserve backburner state - only UserPromptSubmit should exit backburner
            // (explicit reactivation via UI uses updateSessionState, not this method)
            if oldState == .backburner, event != "UserPromptSubmit" {
                // Update metadata but preserve backburner state
                sessions[index].lastUpdated = Date()
                if let tmuxSessionName, !tmuxSessionName.isEmpty {
                    sessions[index].tmuxSessionName = tmuxSessionName
                }
                if let gitBranch, !gitBranch.isEmpty {
                    sessions[index].gitBranch = gitBranch
                }
                if let gitRepoName, !gitRepoName.isEmpty {
                    sessions[index].gitRepoName = gitRepoName
                }
                if let transcriptPath, !transcriptPath.isEmpty {
                    sessions[index].transcriptPath = transcriptPath
                }
                return
            }

            // Update metadata (doesn't need animation)
            sessions[index].lastUpdated = Date()
            if let tmuxSessionName, !tmuxSessionName.isEmpty {
                sessions[index].tmuxSessionName = tmuxSessionName
            }
            if let gitBranch, !gitBranch.isEmpty {
                sessions[index].gitBranch = gitBranch
            }
            if let gitRepoName, !gitRepoName.isEmpty {
                sessions[index].gitRepoName = gitRepoName
            }
            if let transcriptPath, !transcriptPath.isEmpty {
                sessions[index].transcriptPath = transcriptPath
            }

            // State change with animation
            if oldState != state {
                let sessionID = sessions[index].id
                Task { @MainActor in
                    self.applyStateChange(sessionID: sessionID, from: oldState, to: state)
                }
            }
        } else {
            let now = Date()
            var session = Session(
                claudeSessionID: claudeSessionID,
                terminalSessionID: terminalSessionID,
                tmuxPane: tmuxPane,
                terminalType: terminalType,
                projectPath: projectPath,
                terminalTabName: nil,
                terminalWindowName: nil,
                customName: nil,
                state: state,
                lastUpdated: now,
                startedAt: now
            )
            session.tmuxSessionName = tmuxSessionName?.isEmpty == true ? nil : tmuxSessionName
            session.gitBranch = gitBranch?.isEmpty == true ? nil : gitBranch
            session.gitRepoName = gitRepoName?.isEmpty == true ? nil : gitRepoName
            session.transcriptPath = transcriptPath?.isEmpty == true ? nil : transcriptPath
            sessions.append(session)

            // If this new session matches the currently focused pane, sync cycling state
            if let focusedID = focusedSessionID,
               session.terminalSessionID.hasSuffix(focusedID) {
                cyclingState = cyclingEngine.syncStateToFocus(
                    sessions: sessions,
                    focusedSessionID: focusedID,
                    state: cyclingState
                )
            }

            Task { @MainActor in
                logInfo(.session, "New session added: \(session.displayName)")
            }
        }
    }

    func updateSessionState(terminalSessionID: String, state: SessionState) {
        guard let index = sessions.firstIndex(where: { $0.id == terminalSessionID }) else { return }
        let oldState = sessions[index].state
        sessions[index].lastUpdated = Date()
        if oldState != state {
            let sessionID = sessions[index].id
            Task { @MainActor in
                self.applyStateChange(sessionID: sessionID, from: oldState, to: state)
            }
        }
    }

    func updateSessionTerminalInfo(
        terminalSessionID: String,
        tabName: String?,
        windowName: String? = nil,
        paneIndex: Int,
        paneCount: Int
    ) {
        // Update all sessions sharing this iTerm2 session (multiple tmux panes may share one)
        for index in sessions.indices where sessions[index].terminalSessionID == terminalSessionID {
            sessions[index].terminalTabName = tabName
            sessions[index].terminalWindowName = windowName
            sessions[index].paneIndex = paneIndex
            sessions[index].paneCount = paneCount
        }
    }

    func renameSession(terminalSessionID: String, customName: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == terminalSessionID }) else { return }
        sessions[index].customName = customName?.isEmpty == true ? nil : customName
    }

    func removeSessionsByTerminalID(_ terminalSessionID: String) {
        guard !terminalSessionID.isEmpty else { return }
        let matching = sessions.filter {
            $0.terminalSessionID == terminalSessionID
                || $0.terminalSessionID.hasSuffix(":\(terminalSessionID)")
        }
        for session in matching {
            removeSession(sessionID: session.id)
        }
    }

    func removeSession(sessionID: String) {
        if let session = sessions.first(where: { $0.id == sessionID }) {
            Task { @MainActor in
                logInfo(.session, "Session removed: \(session.displayName)")
            }
        }
        sessions.removeAll { $0.id == sessionID }
        if focusedSessionID == sessionID {
            focusedSessionID = nil
        }
    }

    func cycleForward() -> Session? {
        let result = cyclingEngine.cycleForward(
            sessions: sessions,
            focusedSessionID: focusedSessionID,
            state: cyclingState
        )
        cyclingState = result.newState
        if let target = result.targetSession {
            focusedSessionID = target.id
        }
        return result.targetSession
    }

    func cycleBackward() -> Session? {
        let result = cyclingEngine.cycleBackward(
            sessions: sessions,
            focusedSessionID: focusedSessionID,
            state: cyclingState
        )
        cyclingState = result.newState
        if let target = result.targetSession {
            focusedSessionID = target.id
        }
        return result.targetSession
    }

    func disambiguatedDisplayName(for session: Session) -> String {
        let baseName = session.displayName
        let sessionsWithSameName = sessions.filter { $0.displayName == baseName }

        guard sessionsWithSameName.count > 1 else {
            return baseName
        }

        // Sort by paneIndex to ensure consistent numbering
        let sorted = sessionsWithSameName.sorted { $0.paneIndex < $1.paneIndex }
        if let index = sorted.firstIndex(where: { $0.id == session.id }) {
            return "\(baseName) (\(index + 1))"
        }
        return baseName
    }

    func backburnerSession(terminalSessionID: String) {
        updateSessionState(terminalSessionID: terminalSessionID, state: .backburner)
    }

    func reactivateSession(terminalSessionID: String) {
        updateSessionState(terminalSessionID: terminalSessionID, state: .idle)
    }

    @MainActor
    func reactivateAllBackburnered() {
        let backburneredIDs = sessions.filter { $0.state == .backburner }.map(\.id)
        for id in backburneredIDs {
            applyStateChange(sessionID: id, from: .backburner, to: .idle)
        }
    }
}
