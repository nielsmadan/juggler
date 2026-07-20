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

    /// Persisted per-day busy-time totals. Fed by state transitions and rollover.
    let dailyStats: DailyStatsStore

    /// Start-of-day of the last day we observed, for detecting midnight rollover.
    private var lastSeenDay: Date

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

    /// Test-only: set the last-seen day for rollover tests.
    func testSetLastSeenDay(_ date: Date) {
        lastSeenDay = date
    }

    /// Test-only: synchronously apply a state change (bypasses Task dispatch).
    @MainActor
    func testApplyStateChange(
        sessionID: String,
        from oldState: SessionState,
        to newState: SessionState,
        now: Date = Date()
    ) {
        applyStateChange(sessionID: sessionID, from: oldState, to: newState, now: now)
    }

    /// Test-only: trigger focus reconciliation. Only accessible via @testable import.
    @MainActor
    func testReconcileFocusForTerminal(bundleID: String) {
        reconcileFocusForTerminal(bundleID: bundleID)
    }

    private(set) var cyclingState = CyclingState.initial
    private(set) var focusedSessionID: String? // terminalSessionID of actually focused session in iTerm2
    internal(set) var isTerminalAppActive = false

    /// Live local handle (iTerm2 pane UUID / kitty window id) of the most recently
    /// focused pane per terminal, captured from that terminal's own focus events. Used
    /// to bind remote tmux sessions — whose remote-captured `terminalSessionID` is stale
    /// — to the live local pane/window hosting their tmux client. Keyed by terminal so a
    /// kitty focus can never be mistaken for an iTerm2 one (and vice versa).
    private(set) var lastFocusedLocalPaneByTerminal: [TerminalType: String] = [:]

    /// The frontmost app's terminal type, or nil if the frontmost app isn't a terminal.
    /// Injectable so the binding logic is testable without a live `NSWorkspace`.
    @ObservationIgnored
    var frontmostTerminalTypeProvider: () -> TerminalType? = {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return TerminalType.allCases.first { $0.bundleIdentifier == bundleID }
    }

    /// Tracks the session the user was last focused on, even after it goes busy.
    /// Used when auto-advance is OFF to keep the busy session highlighted as "current".
    private(set) var lastActiveSessionID: String?

    /// Session ID from the most recent successfully delivered notification.
    /// Consumed by the "go to last notification" hotkey.
    private(set) var lastNotifiedSessionID: String?

    func recordLastNotification(sessionID: String) {
        lastNotifiedSessionID = sessionID
    }

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

    /// The session shown as the "current"/reference highlight: the `lastActiveSessionID`
    /// anchor if it's still present (that field is only ever set when auto-advance is
    /// off — see `applyStateChange` — so no flag check is needed here), otherwise
    /// `currentSession` while a terminal is focused (which may resolve via the cycling
    /// cursor, not strictly `focusedSessionID`). `nil` if neither. Single source of
    /// truth for the popover's reference highlight and its initial selection on open;
    /// preserves the old per-row `SessionRowView.isCurrent` logic.
    var currentReferenceSessionID: String? {
        if let lastActive = lastActiveSessionID, sessions.contains(where: { $0.id == lastActive }) {
            return lastActive
        }
        if isSessionFocused { return currentSession?.id }
        return nil
    }

    /// Set during hotkey-driven activation to suppress intermediate focus events from terminals.
    /// When non-nil, `updateFocusedSession` ignores focus events that don't match this target.
    private(set) var activationTarget: String?

    private(set) var activeColorIndex: Int = 0

    var activeColor: Color {
        CyclingColors.palette[activeColorIndex % CyclingColors.palette.count]
    }

    func advanceColorIndex(by delta: Int = 1) {
        let count = CyclingColors.palette.count
        activeColorIndex = (activeColorIndex + delta + count) % count
    }

    func setColorIndex(to index: Int) {
        activeColorIndex = index % CyclingColors.palette.count
    }

    func clearColorIndex() {
        activeColorIndex = 0
    }

    func syncColorIndex(toSessionID sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              activeColorIndex != index else { return }
        setColorIndex(to: index)
    }

    let animationController = SectionAnimationController()

    private var queueOrderMode: QueueOrderMode {
        let rawValue = UserDefaults.standard.string(forKey: "queueOrderMode") ?? QueueOrderMode.fair.rawValue
        return QueueOrderMode(rawValue: rawValue) ?? .fair
    }

    /// Fallback group label for sessions with no `terminalWindowName` (Grouped mode).
    static let unknownWindowGroup = "Unknown"

    /// Visual sections (idle → working → backburner) with the sessions currently
    /// shown in each, by `effectiveSection`. The single source for the Fair/Prio
    /// section order — consumed by both the monitor's section rows and navigation.
    func sessionsBySection() -> [(section: SectionType, sessions: [Session])] {
        let sections: [SectionType] = [.idle, .working, .backburner]
        return sections.map { section in
            (section, sessions.filter { animationController.effectiveSection(for: $0) == section })
        }
    }

    /// Sessions grouped by terminal window, in Grouped-mode render order (keys
    /// sorted, each group by `startedAt`). The single source for that ordering.
    func sessionsByWindowGroup() -> [(key: String, sessions: [Session])] {
        Dictionary(grouping: sessions) { $0.terminalWindowName ?? Self.unknownWindowGroup }
            .map { (key: $0.key, sessions: $0.value.sorted { $0.startedAt < $1.startedAt }) }
            .sorted { $0.key < $1.key }
    }

    /// The sessions in the exact top-to-bottom order the monitor renders them for
    /// the current queue mode. This is the single source of truth for keyboard
    /// navigation, so selection/highlight/scroll follow what's on screen rather
    /// than the raw `sessions` array order (which drifts out of section order and
    /// disagrees with the render during section animations). Derived from the same
    /// `sessionsBySection`/`sessionsByWindowGroup` the view renders, so the two
    /// can't diverge.
    func orderedVisibleSessions() -> [Session] {
        switch queueOrderMode {
        case .fair, .prio:
            sessionsBySection().flatMap(\.sessions)
        case .static:
            sessions
        case .grouped:
            sessionsByWindowGroup().flatMap(\.sessions)
        }
    }

    init(dailyStats: DailyStatsStore = DailyStatsStore()) {
        cyclingEngine = DefaultCyclingEngine()
        self.dailyStats = dailyStats
        lastSeenDay = Calendar.current.startOfDay(for: Date())
        Self.migrateLegacyQueueOrderModeValues(in: .standard)
    }

    static func migrateLegacyQueueOrderModeValues(in defaults: UserDefaults) {
        guard let raw = defaults.string(forKey: "queueOrderMode") else { return }
        if raw == "filo" {
            defaults.set(QueueOrderMode.fair.rawValue, forKey: "queueOrderMode")
        } else if raw == "fifo" {
            defaults.set(QueueOrderMode.prio.rawValue, forKey: "queueOrderMode")
        }
    }

    // MARK: - State Transitions

    private func handleStateTransition(
        at index: Int,
        from oldState: SessionState,
        to newState: SessionState,
        now: Date = Date()
    ) {
        let wasIdle = oldState == .idle || oldState == .permission
        let isIdle = newState == .idle || newState == .permission

        if isIdle, !wasIdle {
            sessions[index].lastBecameIdle = now
        }

        let wasWorking = oldState == .working || oldState == .compacting
        let isWorking = newState == .working || newState == .compacting

        if wasWorking, !isWorking {
            if let lastBecameWorking = sessions[index].lastBecameWorking {
                let workingDuration = now.timeIntervalSince(lastBecameWorking)
                sessions[index].busyTimeToday += workingDuration
                dailyStats.addBusyTime(workingDuration, on: now)
                sessions[index].lastBecameWorking = nil
            }
        }

        if isWorking, !wasWorking {
            sessions[index].lastBecameWorking = now
        }

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
            // Removing at `index` shifts later elements left by 1, so when moving forward
            // (index < targetIdx) the desired insertion slot is targetIdx - 1.
            let insertIdx = index < targetIdx ? targetIdx - 1 : targetIdx
            if index != insertIdx {
                let session = sessions.remove(at: index)
                sessions.insert(session, at: insertIdx)
            }
        }
    }

    @MainActor
    private func applyStateChange(
        sessionID: String,
        from oldState: SessionState,
        to newState: SessionState,
        now: Date = Date()
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        logDebug(.session, "\(sessions[index].displayName): \(oldState.rawValue) → \(newState.rawValue)")

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
                handleStateTransition(at: index, from: oldState, to: newState, now: now)
            }
        } else {
            sessions[index].state = newState
            handleStateTransition(at: index, from: oldState, to: newState, now: now)
        }

        // Handle auto-advance when a session goes busy (not backburner — that's a deliberate user action
        // handled by HotkeyManager.handleBackburner directly)
        let wasCyclable = oldState.isIncludedInCycle
        let isCyclable = newState.isIncludedInCycle
        if wasCyclable, !isCyclable, newState != .backburner {
            // Only act if the user is still focused on this session.
            // If they already cycled away, the hook arrived late — don't yank them.
            // Re-find the session after handleStateTransition may have reordered the array.
            let isStillFocused: Bool = if let fid = focusedSessionID,
                                          let session = sessions.first(where: { $0.id == sessionID }) {
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
                    logDebug(.session, "Auto-advance triggered for \(sessionID)")
                    NotificationCenter.default.post(name: .shouldAutoAdvance, object: nil)
                } else {
                    // Auto-advance OFF: remember this session as the anchor
                    logDebug(.session, "Anchored lastActiveSessionID to \(sessionID)")
                    lastActiveSessionID = sessionID
                }
            }
        }

        // Clear lastActiveSessionID when the session returns to cyclable state
        if isCyclable, lastActiveSessionID == sessionID {
            logDebug(.session, "Cleared lastActiveSessionID for \(sessionID)")
            lastActiveSessionID = nil
        }

        // Handle auto-restart: when a session becomes idle and it's the only cyclable one
        if !wasCyclable, isCyclable {
            let autoRestart = UserDefaults.standard.bool(forKey: AppStorageKeys.autoRestartOnIdle)
            if autoRestart {
                let cyclableCount = sessions.filter(\.state.isIncludedInCycle).count
                if cyclableCount == 1 {
                    logDebug(.session, "Auto-restart triggered for \(sessionID)")
                    NotificationCenter.default.post(
                        name: .shouldAutoRestart,
                        object: nil,
                        userInfo: ["sessionID": sessionID]
                    )
                }
            }
        }
    }

    /// Detects local-midnight rollover (called from the monitor view's periodic
    /// tick). On a new day: splits each still-working session's in-progress
    /// stretch at midnight (the pre-midnight portion is committed to the
    /// previous day) and resets every session's `busyTimeToday`. Historical
    /// daily totals are kept indefinitely — no pruning.
    func handleDayRolloverIfNeeded(now: Date) {
        let newDay = Calendar.current.startOfDay(for: now)
        guard newDay > lastSeenDay else { return }

        for index in sessions.indices {
            let isBusy = sessions[index].state == .working || sessions[index].state == .compacting
            if isBusy,
               let lastBecameWorking = sessions[index].lastBecameWorking,
               lastBecameWorking < newDay {
                let beforeMidnight = newDay.timeIntervalSince(lastBecameWorking)
                dailyStats.addBusyTime(beforeMidnight, on: lastSeenDay)
                sessions[index].lastBecameWorking = newDay
            }
            sessions[index].busyTimeToday = 0
        }

        lastSeenDay = newDay
    }

    /// Best-effort commit of in-progress busy time, e.g. on app termination.
    /// For each still-working session, commits the elapsed turn and clears the
    /// working clock so it can't be double-counted.
    func commitInProgressBusyTime() {
        let now = Date()
        for index in sessions.indices {
            let isBusy = sessions[index].state == .working || sessions[index].state == .compacting
            guard isBusy, let lastBecameWorking = sessions[index].lastBecameWorking else { continue }
            let elapsed = now.timeIntervalSince(lastBecameWorking)
            guard elapsed > 0 else { continue }
            sessions[index].busyTimeToday += elapsed
            dailyStats.addBusyTime(elapsed, on: now)
            sessions[index].lastBecameWorking = nil
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
           !session.state.isIncludedInCycle {
            return session
        }

        guard !cyclable.isEmpty else { return nil }

        // Prefer focused session if it's cyclable (focusedSessionID is normalized on entry)
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
            if isTerminal {
                reconcileFocusForTerminal(bundleID: bundleID)
            }
        }

        // Initialize based on current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier {
            isTerminalAppActive = terminalBundleIDs.contains(bundleID)
            if isTerminalAppActive {
                reconcileFocusForTerminal(bundleID: bundleID)
            }
        }
    }

    /// When a terminal app is activated, ensure focusedSessionID points to a session
    /// in that terminal. Kitty uses fire-and-forget focus events (curl from a watcher script)
    /// with no persistent connection or retry, so events can be lost. This reconciles state
    /// on every app activation so a single missed event can't permanently break highlighting.
    @MainActor
    private func reconcileFocusForTerminal(bundleID: String) {
        guard let terminalType = TerminalType.allCases.first(where: { $0.bundleIdentifier == bundleID })
        else { return }

        // Only reconcile for terminals without persistent focus tracking
        guard terminalType == .kitty else { return }

        let kittySessions = sessions.filter { $0.terminalType == terminalType }
        logDebug(
            .kitty,
            "Reconcile: focusedSessionID=\(focusedSessionID ?? "nil"), "
                + "kittySessions=\(kittySessions.map(\.terminalSessionID)), "
                + "isSessionFocused=\(isSessionFocused)"
        )

        // Check if focusedSessionID already matches a session in this terminal
        if let focusedID = focusedSessionID,
           kittySessions.contains(where: { $0.id == focusedID || $0.terminalSessionID == focusedID }) {
            logDebug(.kitty, "Reconcile: already focused on kitty session, no change needed")
            return
        }

        // Set focus to a session in this terminal
        if let session = kittySessions.first {
            logDebug(.kitty, "Reconcile: setting focus to \(session.terminalSessionID)")
            updateFocusedSession(terminalSessionID: session.terminalSessionID)
        } else {
            logDebug(.kitty, "Reconcile: no kitty sessions to reconcile")
        }
    }

    @MainActor
    func updateFocusedSession(terminalSessionID: String?, focusTerminalType: TerminalType? = nil) {
        // Remember the live local handle so remote tmux sessions can be bound to the pane
        // hosting them later (see resolveLiveHostPaneBinding). Capture only genuine live
        // focus events tagged with their source terminal (iTerm2 daemon / kitty watcher);
        // internal focus-reconciliation calls pass a nil type and must not feed the
        // binding, since they carry stored — possibly stale — ids. Empty ids are ignored,
        // and a nil event (focus cleared) leaves the last known handle in place.
        if let type = focusTerminalType, let newID = terminalSessionID, !newID.isEmpty {
            lastFocusedLocalPaneByTerminal[type] = newID
        }

        // Normalize: resolve bare UUIDs to the full terminalSessionID so all
        // downstream matching can use exact equality instead of hasSuffix. A remote
        // tmux session whose stored terminalSessionID is stale is matched through its
        // learned liveHostPaneID and resolved to the session's composite id.
        let resolved: String? = if let newID = terminalSessionID {
            if sessions.contains(where: { $0.id == newID || $0.terminalSessionID == newID }) {
                newID
            } else if let session = sessions.first(where: { $0.liveHostPaneID == newID }) {
                session.id
            } else if let session = sessions.first(where: { $0.terminalSessionID.hasSuffix(newID) }) {
                session.terminalSessionID
            } else {
                newID
            }
        } else {
            nil
        }

        // During hotkey activation, ignore focus events that don't match the target.
        // This prevents intermediate events (e.g., iTerm2 briefly focusing the wrong tab
        // as the app comes to foreground) from causing UI flicker.
        if let target = activationTarget, let newID = resolved {
            let matchesTarget = sessions.contains(where: {
                $0.id == target
                    && ($0.terminalSessionID == newID || newID == $0.id)
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

        focusedSessionID = resolved

        if let newID = resolved {
            logDebug(.session, "Focus updated to \(newID) → isSessionFocused=\(isSessionFocused)")
            cyclingState = cyclingEngine.syncStateToFocus(
                sessions: sessions,
                focusedSessionID: resolved,
                state: cyclingState
            )
        } else {
            logDebug(.session, "Focus cleared → isSessionFocused=\(isSessionFocused)")
        }
    }

    private func mergeSessionMetadata(
        at index: Int,
        tmuxSessionName: String?,
        gitBranch: String?,
        gitRepoName: String?,
        transcriptPath: String?,
        remoteHost: String?
    ) {
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
        if let remoteHost, !remoteHost.isEmpty {
            sessions[index].remoteHost = remoteHost
        }
    }

    /// Decides the live host-pane binding for a remote tmux session. Pure so it can be
    /// unit-tested without a live iTerm2 / NSWorkspace.
    ///
    /// - A `UserPromptSubmit` fires in the pane the user is actively typing in, so it is
    ///   the authoritative signal and always (re)binds.
    /// - Any other event binds only to bootstrap an as-yet-unbound session, so a
    ///   background event that fires while the user is looking at a different pane can't
    ///   clobber a good binding.
    static func resolveLiveHostPaneBinding(
        current: String?,
        lastFocusedPaneUUID: String?,
        isHostTerminalFrontmost: Bool,
        event: String?,
        needsBinding: Bool
    ) -> String? {
        guard needsBinding, isHostTerminalFrontmost, let uuid = lastFocusedPaneUUID else {
            return current
        }
        if event == "UserPromptSubmit" {
            return uuid
        }
        return current ?? uuid
    }

    /// Re-evaluates and applies the live host-pane binding for the session at `index`.
    /// Binds against the last focused handle from the session's own terminal, and only
    /// while that terminal is frontmost — so a remote tmux session is pinned to the pane
    /// the user is actually looking at.
    @MainActor
    private func applyLiveHostPaneBinding(at index: Int, event: String?) {
        let session = sessions[index]
        let needsBinding = (session.remoteHost?.isEmpty == false) && (session.tmuxPane != nil)
        let newBinding = Self.resolveLiveHostPaneBinding(
            current: session.liveHostPaneID,
            lastFocusedPaneUUID: lastFocusedLocalPaneByTerminal[session.terminalType],
            isHostTerminalFrontmost: frontmostTerminalTypeProvider() == session.terminalType,
            event: event,
            needsBinding: needsBinding
        )
        if newBinding != session.liveHostPaneID {
            sessions[index].liveHostPaneID = newBinding
        }
    }

    @MainActor
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
        transcriptPath: String? = nil,
        remoteHost: String? = nil
    ) {
        let compositeID: String = if let pane = tmuxPane {
            "\(terminalSessionID):\(pane)"
        } else {
            terminalSessionID
        }

        if let index = sessions.firstIndex(where: { $0.id == compositeID }) {
            let oldState = sessions[index].state

            // Keep the live host-pane binding fresh on every hook (before the backburner
            // early-return, so backburnered remote sessions stay reachable too).
            applyLiveHostPaneBinding(at: index, event: event)

            // Preserve backburner state - only UserPromptSubmit should exit backburner
            // (explicit reactivation via UI uses updateSessionState, not this method)
            if oldState == .backburner, event != "UserPromptSubmit" {
                mergeSessionMetadata(
                    at: index,
                    tmuxSessionName: tmuxSessionName,
                    gitBranch: gitBranch,
                    gitRepoName: gitRepoName,
                    transcriptPath: transcriptPath,
                    remoteHost: remoteHost
                )
                return
            }

            mergeSessionMetadata(
                at: index,
                tmuxSessionName: tmuxSessionName,
                gitBranch: gitBranch,
                gitRepoName: gitRepoName,
                transcriptPath: transcriptPath,
                remoteHost: remoteHost
            )

            if oldState != state {
                let sessionID = sessions[index].id
                applyStateChange(sessionID: sessionID, from: oldState, to: state)
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
            // Initialize the state-entry timestamp so the first observed state
            // has a sensible reference (no transition fires for new sessions).
            // For idle/permission this also seeds the Fair/Prio queue sort key
            // (`lastBecameIdle`) — see `reorderForMode`.
            switch state {
            case .working, .compacting:
                session.lastBecameWorking = now
            case .idle, .permission:
                session.lastBecameIdle = now
            case .backburner:
                // No relevant timestamp; explicit reactivation will set
                // `lastBecameIdle` via `handleStateTransition`.
                break
            }
            session.remoteHost = remoteHost?.isEmpty == true ? nil : remoteHost
            sessions.append(session)
            applyLiveHostPaneBinding(at: sessions.count - 1, event: event)
            // Reconcile against the stored (now-bound) element, not the local copy, so a
            // focus event that arrived before this remote session existed can resolve.
            reconcileFocus(forNewSession: sessions[sessions.count - 1])

            // Highlight immediately without waiting for the next app switch
            let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if session.terminalType == .kitty,
               frontmostBundle == TerminalType.kitty.bundleIdentifier {
                logDebug(
                    .kitty,
                    "New kitty session \(session.terminalSessionID) created while kitty is frontmost, setting focus"
                )
                updateFocusedSession(terminalSessionID: session.terminalSessionID)
            }

            logInfo(.session, "New session added: \(session.displayName)")
        }
    }

    /// Reconciles focus state for a session that was just appended. Focus events can
    /// arrive before the session exists, leaving a bare UUID stored — re-point it at
    /// the session's id, then re-sync the cycling cursor to that focus.
    @MainActor
    private func reconcileFocus(forNewSession session: Session) {
        // A remote tmux session's live pane UUID matches neither terminalSessionID nor a
        // suffix of it, so resolve it through the learned liveHostPaneID first.
        if let focusedID = focusedSessionID, focusedID == session.liveHostPaneID {
            focusedSessionID = session.id
        } else if let focusedID = focusedSessionID,
                  focusedID != session.terminalSessionID,
                  session.terminalSessionID.hasSuffix(focusedID) {
            focusedSessionID = session.terminalSessionID
        }

        if let focusedID = focusedSessionID,
           session.terminalSessionID == focusedID || session.id == focusedID
           || session.terminalSessionID.hasSuffix(focusedID) {
            cyclingState = cyclingEngine.syncStateToFocus(
                sessions: sessions,
                focusedSessionID: focusedID,
                state: cyclingState
            )
        }
    }

    @MainActor
    func updateSessionState(terminalSessionID: String, state: SessionState) {
        guard let index = sessions.firstIndex(where: { $0.id == terminalSessionID }) else { return }
        let oldState = sessions[index].state
        if oldState != state {
            let sessionID = sessions[index].id
            applyStateChange(sessionID: sessionID, from: oldState, to: state)
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
            let name = session.displayName
            Task { @MainActor in
                logInfo(.session, "Session removed: \(name)")
            }
        }
        sessions.removeAll { $0.id == sessionID }
        if focusedSessionID == sessionID {
            focusedSessionID = nil
        }
        if lastActiveSessionID == sessionID {
            lastActiveSessionID = nil
        }
        if lastNotifiedSessionID == sessionID {
            lastNotifiedSessionID = nil
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
        if result.didMove { advanceColorIndex(by: 1) }

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
        if result.didMove { advanceColorIndex(by: -1) }

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

    @discardableResult
    @MainActor
    func moveSessionToBackOfQueue(sessionID: String) -> Bool {
        guard queueOrderMode == .fair || queueOrderMode == .prio else { return false }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        guard sessions[index].state.isIncludedInCycle else { return false }

        let targetIdx = targetIndex(for: .bottomOfIdle, in: sessions)
        let insertIdx = index < targetIdx ? targetIdx - 1 : targetIdx
        guard index != insertIdx else { return true }

        withAnimation(.easeInOut(duration: SectionAnimationTiming.upMoveDuration)) {
            let session = sessions.remove(at: index)
            sessions.insert(session, at: insertIdx)
        }
        return true
    }

    /// Sends `sessionID` to the back of the idle queue and returns the session that
    /// followed it in cycle order — the one to jump to next — wrapping to the top of
    /// the queue when it was already last. Returns nil when the move doesn't apply
    /// (static/grouped mode, or the session isn't cyclable).
    @discardableResult
    @MainActor
    func sendToBackOfQueue(sessionID: String) -> Session? {
        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        guard let currentIdx = cyclable.firstIndex(where: { $0.id == sessionID }) else { return nil }
        let next = cyclable[(currentIdx + 1) % cyclable.count]
        guard moveSessionToBackOfQueue(sessionID: sessionID) else { return nil }
        if next.id != sessionID { advanceColorIndex(by: 1) }
        return next
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
