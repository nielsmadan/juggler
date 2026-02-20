import Foundation
import SwiftUI

enum QueuePosition: Equatable {
    case topOfIdle
    case bottomOfIdle
    case bottomOfBusy
    case bottomOfBackburner
}

@Observable
final class SessionManager {
    static let shared = SessionManager()

    private(set) var sessions: [Session] = []

    /// Test-only: directly set session properties. Only accessible via @testable import.
    func testSetSessions(_ newSessions: [Session]) {
        sessions = newSessions
    }

    /// Test-only: set focusedSessionID. Only accessible via @testable import.
    func testSetFocusedSessionID(_ id: String?) {
        focusedSessionID = id
    }

    /// Test-only: set lastActiveSessionID. Only accessible via @testable import.
    func testSetLastActiveSessionID(_ id: String?) {
        lastActiveSessionID = id
    }

    /// Test-only: synchronously apply a state change (bypasses Task dispatch).
    @MainActor
    func testApplyStateChange(sessionID: String, from oldState: SessionState, to newState: SessionState) {
        applyStateChange(sessionID: sessionID, from: oldState, to: newState)
    }

    private(set) var cyclingState = CyclingState.initial
    private(set) var focusedSessionID: String? // terminalSessionID of actually focused session in iTerm2
    internal(set) var isTerminalAppActive = false

    /// Tracks the session the user was last focused on, even after it goes busy.
    /// Used when auto-advance is OFF to keep the busy session highlighted as "current".
    private(set) var lastActiveSessionID: String?

    /// Check whether a terminal app is currently the frontmost application (live check, no caching).
    func isTerminalFrontmost() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier
        else { return false }
        return TerminalType.allCases.contains { $0.bundleIdentifier == bundleID }
    }

    private let cyclingEngine: CyclingEngine
    private var appFocusObserver: NSObjectProtocol?

    /// True when a tracked session is focused in an active terminal app.
    /// Computed from two independent signals to avoid race conditions.
    var isSessionFocused: Bool {
        guard isTerminalAppActive, let focusedID = focusedSessionID else { return false }
        return matchesTrackedSession(focusedID)
    }

    /// Set during hotkey-driven activation to suppress intermediate focus events from terminals.
    /// When non-nil, `updateFocusedSession` ignores focus events that don't match this target.
    private var activationTarget: String?

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

    // MARK: - State Transitions

    private func handleStateTransition(at index: Int, from oldState: SessionState, to newState: SessionState) {
        let sessionName = sessions[index].displayName
        Task { @MainActor in
            logDebug(.session, "\(sessionName): \(oldState.rawValue) → \(newState.rawValue)")
        }

        let wasIdle = oldState == .idle || oldState == .permission
        let isIdle = newState == .idle || newState == .permission

        if wasIdle, !isIdle {
            if let lastBecameIdle = sessions[index].lastBecameIdle {
                let idleDuration = Date().timeIntervalSince(lastBecameIdle)
                sessions[index].accumulatedIdleTime += idleDuration
            }
        }

        if isIdle, !wasIdle {
            sessions[index].lastBecameIdle = Date()
        }

        let wasWorking = oldState == .working || oldState == .compacting
        let isWorking = newState == .working || newState == .compacting

        if wasWorking, !isWorking {
            if let lastBecameWorking = sessions[index].lastBecameWorking {
                let workingDuration = Date().timeIntervalSince(lastBecameWorking)
                sessions[index].accumulatedWorkingTime += workingDuration
            }
        }

        if isWorking, !wasWorking {
            sessions[index].lastBecameWorking = Date()
        }

        // Reorder for queue mode (no manual animation - List handles it)
        guard queueOrderMode != .static, queueOrderMode != .grouped else { return }

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

        // Handle auto-advance when a session goes busy
        let wasCyclable = oldState.isIncludedInCycle
        let isCyclable = newState.isIncludedInCycle
        if wasCyclable, !isCyclable {
            // Only act if the user is still focused on this session.
            // If they already cycled away, the hook arrived late — don't yank them.
            // Re-find the session after handleStateTransition may have reordered the array.
            let isStillFocused: Bool = if let fid = focusedSessionID,
                                          let session = sessions.first(where: { $0.id == sessionID })
            {
                session.id == fid
                    || session.terminalSessionID == fid
                    || session.terminalSessionID.hasSuffix(fid)
            } else {
                false
            }

            if isStillFocused {
                let autoAdvance = UserDefaults.standard.bool(forKey: AppStorageKeys.autoAdvanceOnBusy)
                if autoAdvance {
                    // Auto-advance ON: notify HotkeyManager to navigate to next idle session
                    NotificationCenter.default.post(name: .shouldAutoAdvance, object: nil)
                } else {
                    // Auto-advance OFF: remember this session as the anchor
                    lastActiveSessionID = sessionID
                }
            }
        }

        // Clear lastActiveSessionID when the session returns to cyclable state
        if isCyclable, lastActiveSessionID == sessionID {
            lastActiveSessionID = nil
        }

        // Handle auto-restart: when a session becomes idle and it's the only cyclable one
        if !wasCyclable, isCyclable {
            let autoRestart = UserDefaults.standard.bool(forKey: AppStorageKeys.autoRestartOnIdle)
            if autoRestart {
                let cyclableCount = sessions.filter(\.state.isIncludedInCycle).count
                if cyclableCount == 1 {
                    NotificationCenter.default.post(
                        name: .shouldAutoRestart,
                        object: nil,
                        userInfo: ["sessionID": sessionID]
                    )
                }
            }
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
        guard mode != .static, mode != .grouped else {
            sessions.sort { $0.startedAt < $1.startedAt }
            return
        }

        let idle = sessions.filter { $0.state == .idle || $0.state == .permission }
        let working = sessions.filter { $0.state == .working || $0.state == .compacting }
        let backburner = sessions.filter { $0.state == .backburner }

        let sortedIdle = idle.sorted {
            switch mode {
            case .fair:
                ($0.lastBecameIdle ?? .distantPast) < ($1.lastBecameIdle ?? .distantPast)
            case .prio:
                ($0.lastBecameIdle ?? .distantPast) > ($1.lastBecameIdle ?? .distantPast)
            case .static, .grouped:
                $0.startedAt < $1.startedAt
            }
        }

        sessions = sortedIdle + working + backburner
    }

    var cyclableSessions: [Session] {
        sessions.filter(\.state.isIncludedInCycle)
    }

    var currentSession: Session? {
        let cyclable = cyclableSessions

        // When auto-advance is OFF and we have a lastActiveSessionID pointing to a busy session,
        // return that session as current even though it's not cyclable.
        // This keeps the UI highlighting stable when a session goes busy.
        let autoAdvance = UserDefaults.standard.bool(forKey: AppStorageKeys.autoAdvanceOnBusy)
        if !autoAdvance, let lastID = lastActiveSessionID,
           let session = sessions.first(where: { $0.id == lastID }),
           !session.state.isIncludedInCycle
        {
            return session
        }

        guard !cyclable.isEmpty else { return nil }

        // Prefer focused session if it's cyclable
        // Try composite id first (set from hook events), then terminalSessionID with hasSuffix for bare UUID focus
        // events
        if let focusedID = focusedSessionID,
           let session = cyclable.first(where: {
               $0.id == focusedID || $0.terminalSessionID == focusedID
                   || $0.terminalSessionID.hasSuffix(focusedID)
           })
        {
            return session
        }

        // Fall back to index-based
        let safeIndex = cyclingState.currentIndex % cyclable.count
        return cyclable[safeIndex]
    }

    /// Called before hotkey activation to suppress intermediate focus events.
    @MainActor
    func beginActivation(targetSessionID: String) {
        activationTarget = targetSessionID
    }

    /// Called after hotkey activation completes (success or failure) to resume normal focus tracking.
    @MainActor
    func endActivation() {
        activationTarget = nil
    }

    /// Whether the given terminal session ID matches any tracked session.
    private func matchesTrackedSession(_ terminalSessionID: String) -> Bool {
        sessions.contains(where: {
            $0.id == terminalSessionID
                || $0.terminalSessionID == terminalSessionID
                || $0.terminalSessionID.hasSuffix(terminalSessionID)
        })
    }

    /// Observe app activation to track whether a terminal app is frontmost.
    @MainActor
    func startAppFocusObserver() {
        // Guard against double-registration
        if let existing = appFocusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
        }

        let terminalBundleIDs = Set(TerminalType.allCases.map(\.bundleIdentifier))

        appFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier
            else { return }

            let isTerminal = terminalBundleIDs.contains(bundleID)
            logDebug(.session, "App focus: \(bundleID) activated, isTerminal=\(isTerminal)")
            isTerminalAppActive = isTerminal
        }

        // Initialize based on current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier
        {
            isTerminalAppActive = terminalBundleIDs.contains(bundleID)
        }
    }

    @MainActor
    func updateFocusedSession(terminalSessionID: String?) {
        // During hotkey activation, ignore focus events that don't match the target.
        // This prevents intermediate events (e.g., iTerm2 briefly focusing the wrong tab
        // as the app comes to foreground) from causing UI flicker.
        if let target = activationTarget, let newID = terminalSessionID {
            let matchesTarget = sessions.contains(where: {
                $0.id == target
                    && ($0.terminalSessionID == newID || $0.terminalSessionID.hasSuffix(newID)
                        || newID == $0.id)
            })
            if matchesTarget {
                // Focus arrived at our target — accept it and clear the guard
                activationTarget = nil
            } else {
                // Spurious intermediate focus event — ignore it
                logDebug(.hotkey, "Suppressed intermediate focus event for \(newID) during activation of \(target)")
                return
            }
        }

        // Don't let a bare UUID from iTerm2 focus events overwrite
        // a more specific composite ID (e.g., "w0t0p0:UUID:%1" contains "UUID")
        if let newID = terminalSessionID, let currentID = focusedSessionID,
           currentID != newID, currentID.contains(newID)
        {
            logDebug(.session, "Focus event (bare UUID \(newID) subsumed by \(currentID))")
            return
        }

        focusedSessionID = terminalSessionID

        if let newID = terminalSessionID {
            logDebug(.session, "Focus updated to \(newID) → isSessionFocused=\(isSessionFocused)")
            cyclingState = cyclingEngine.syncStateToFocus(
                sessions: sessions,
                focusedSessionID: terminalSessionID,
                state: cyclingState
            )
        } else {
            logDebug(.session, "Focus cleared → isSessionFocused=\(isSessionFocused)")
        }
    }

    func addOrUpdateSession(
        claudeSessionID: String,
        terminalSessionID: String,
        tmuxPane: String? = nil,
        tmuxSessionName: String? = nil,
        terminalType: TerminalType = .iterm2,
        agent: String = "claude-code",
        projectPath: String,
        state: SessionState,
        event: String? = nil,
        gitBranch: String? = nil,
        gitRepoName: String? = nil,
        transcriptPath: String? = nil
    ) {
        let compositeID: String = if let pane = tmuxPane {
            "\(terminalSessionID):\(pane)"
        } else {
            terminalSessionID
        }

        if let index = sessions.firstIndex(where: { $0.id == compositeID }) {
            let oldState = sessions[index].state

            // Preserve backburner state - only UserPromptSubmit should exit backburner
            // (explicit reactivation via UI uses updateSessionState, not this method)
            if oldState == .backburner, event != "UserPromptSubmit" {
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
                agent: agent,
                projectPath: projectPath,
                terminalTabName: nil,
                terminalWindowName: nil,
                customName: nil,
                state: state,
                startedAt: now
            )
            session.tmuxSessionName = tmuxSessionName?.isEmpty == true ? nil : tmuxSessionName
            session.gitBranch = gitBranch?.isEmpty == true ? nil : gitBranch
            session.gitRepoName = gitRepoName?.isEmpty == true ? nil : gitRepoName
            session.transcriptPath = transcriptPath?.isEmpty == true ? nil : transcriptPath
            sessions.append(session)

            // If this new session matches the currently focused pane, sync cycling state
            if let focusedID = focusedSessionID,
               session.terminalSessionID.hasSuffix(focusedID)
            {
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
        if lastActiveSessionID == sessionID {
            lastActiveSessionID = nil
        }
    }

    /// Resolve the effective focus ID for cycling, consuming `lastActiveSessionID` as an anchor.
    /// Returns an early-return session if the user should be returned to a previously focused session
    /// (e.g., terminal wasn't frontmost, or focused pane isn't a tracked session).
    private func resolveEffectiveFocus(
        wasTerminalFrontmost: Bool,
        direction: String
    ) -> (effectiveFocusID: String?, earlyReturn: Session?) {
        let effectiveFocusID = lastActiveSessionID ?? focusedSessionID
        if lastActiveSessionID != nil {
            lastActiveSessionID = nil
        }

        let focusedIsTracked = effectiveFocusID.map { matchesTrackedSession($0) } ?? false
        if let focusedID = effectiveFocusID, !wasTerminalFrontmost || !focusedIsTracked {
            let cyclable = sessions.filter(\.state.isIncludedInCycle)
            if let session = cyclable.first(where: {
                $0.id == focusedID || $0.terminalSessionID == focusedID
                    || $0.terminalSessionID.hasSuffix(focusedID)
            }) {
                logDebug(
                    .hotkey,
                    "cycle\(direction): returning to focused session \(session.id) (terminalFrontmost=\(wasTerminalFrontmost), focusedIsTracked=\(focusedIsTracked))"
                )
                focusedSessionID = session.id
                return (effectiveFocusID, session)
            }
        }
        return (effectiveFocusID, nil)
    }

    func cycleForward(wasTerminalFrontmost: Bool = true) -> Session? {
        let (effectiveFocusID, earlyReturn) = resolveEffectiveFocus(
            wasTerminalFrontmost: wasTerminalFrontmost, direction: "Forward"
        )
        if let session = earlyReturn { return session }

        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        logDebug(
            .hotkey,
            "cycleForward: focused=\(effectiveFocusID ?? "nil") stateIdx=\(cyclingState.currentIndex) cyclable=\(cyclable.map { "\($0.id)(\($0.terminalType.displayName))" })"
        )

        let result = cyclingEngine.cycleForward(
            sessions: sessions,
            focusedSessionID: effectiveFocusID,
            state: cyclingState
        )
        cyclingState = result.newState

        logDebug(
            .hotkey,
            "cycleForward -> target=\(result.targetSession?.id ?? "nil") newIdx=\(result.newState.currentIndex)"
        )

        if let target = result.targetSession {
            focusedSessionID = target.id
        }
        return result.targetSession
    }

    func cycleBackward(wasTerminalFrontmost: Bool = true) -> Session? {
        let (effectiveFocusID, earlyReturn) = resolveEffectiveFocus(
            wasTerminalFrontmost: wasTerminalFrontmost, direction: "Backward"
        )
        if let session = earlyReturn { return session }

        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        logDebug(
            .hotkey,
            "cycleBackward: focused=\(effectiveFocusID ?? "nil") stateIdx=\(cyclingState.currentIndex) cyclable=\(cyclable.map { "\($0.id)(\($0.terminalType.displayName))" })"
        )

        let result = cyclingEngine.cycleBackward(
            sessions: sessions,
            focusedSessionID: effectiveFocusID,
            state: cyclingState
        )
        cyclingState = result.newState

        logDebug(
            .hotkey,
            "cycleBackward -> target=\(result.targetSession?.id ?? "nil") newIdx=\(result.newState.currentIndex)"
        )

        if let target = result.targetSession {
            focusedSessionID = target.id
        }
        return result.targetSession
    }

    func disambiguatedDisplayName(for session: Session, titleMode: SessionTitleMode = .tabTitle) -> String {
        let baseName = session.title(for: titleMode)
        let sessionsWithSameName = sessions.filter { $0.title(for: titleMode) == baseName }

        guard sessionsWithSameName.count > 1 else {
            return baseName
        }

        // Sort by paneIndex for stable, deterministic numbering
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

extension Notification.Name {
    static let shouldAutoAdvance = Notification.Name("shouldAutoAdvance")
    static let shouldAutoRestart = Notification.Name("shouldAutoRestart")
}
