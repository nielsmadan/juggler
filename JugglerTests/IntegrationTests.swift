import Foundation
@testable import Juggler
import Testing

// MARK: - Integration Test Helper

/// Simulates what HookServer.handleUnifiedHookEvent does: maps the event then calls SessionManager.
/// Now @MainActor since addOrUpdateSession is @MainActor — state changes apply synchronously.
@MainActor
private func simulateHook(
    manager: SessionManager,
    agent: String = "claude-code",
    event: String,
    claudeSessionID: String = "claude-1",
    terminalSessionID: String,
    tmuxPane: String? = nil,
    projectPath: String = "/test/project",
    gitBranch: String? = nil,
    gitRepoName: String? = nil
) {
    let action = HookEventMapper.map(event: event, agent: agent)
    switch action {
    case let .updateState(state):
        manager.addOrUpdateSession(
            claudeSessionID: claudeSessionID,
            terminalSessionID: terminalSessionID,
            tmuxPane: tmuxPane,
            terminalType: .iterm2,
            agent: agent,
            projectPath: projectPath,
            state: state,
            event: event,
            gitBranch: gitBranch,
            gitRepoName: gitRepoName
        )
    case .removeSession:
        let removeID: String = if let pane = tmuxPane {
            "\(terminalSessionID):\(pane)"
        } else {
            terminalSessionID
        }
        manager.removeSession(sessionID: removeID)
    case .ignore:
        break
    }
}

// MARK: - Hook → Session Appears

@Test @MainActor func integration_sessionStart_createsSession() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        terminalSessionID: "w0t0p0:abc-123",
        projectPath: "/Users/test/my-project",
        gitBranch: "main",
        gitRepoName: "my-project"
    )

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].terminalSessionID == "w0t0p0:abc-123")
    #expect(manager.sessions[0].state == .idle)
    #expect(manager.sessions[0].projectPath == "/Users/test/my-project")
    #expect(manager.sessions[0].gitBranch == "main")
}

@Test @MainActor func integration_sessionEnd_removesSession() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    #expect(manager.sessions.count == 1)

    simulateHook(manager: manager, event: "SessionEnd", terminalSessionID: "s1")
    #expect(manager.sessions.isEmpty)
}

@Test @MainActor func integration_multipleSessionsFromHooks() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c3",
        terminalSessionID: "s3",
        projectPath: "/c"
    )

    #expect(manager.sessions.count == 3)
    #expect(manager.cyclableSessions.count == 3)
}

// MARK: - State Transitions via Hooks

@Test @MainActor func integration_stateTransitions_idleWorkingIdle() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .idle)

    // UserPromptSubmit on existing session now applies state change synchronously
    simulateHook(manager: manager, event: "UserPromptSubmit", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .working)

    simulateHook(manager: manager, event: "Stop", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .idle)
}

@Test @MainActor func integration_permissionState() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    simulateHook(manager: manager, event: "PermissionRequest", terminalSessionID: "s1")

    #expect(manager.sessions[0].state == .permission)
    #expect(manager.sessions[0].state.isIncludedInCycle)
}

// MARK: - Cycle Forward

@Test @MainActor func integration_cycleForward_visitsAllSessions() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c3",
        terminalSessionID: "s3",
        projectPath: "/c"
    )

    var visited: [String] = []
    for _ in 0 ..< 3 {
        if let target = manager.cycleForward() {
            visited.append(target.id)
        }
    }

    #expect(visited.count == 3)
    #expect(Set(visited).count == 3) // all different
}

@Test @MainActor func integration_cycleForward_wrapsAround() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    let first = manager.cycleForward()
    let second = manager.cycleForward()
    let third = manager.cycleForward()

    #expect(first != nil)
    #expect(second != nil)
    #expect(third != nil)
    #expect(third!.id == first!.id) // wrapped
}

@Test @MainActor func integration_cycleForward_setsFocusedSessionID() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    let target = manager.cycleForward()
    #expect(target != nil)
    #expect(manager.focusedSessionID == target!.id)
}

@Test @MainActor func integration_cycleSkipsBusySessions() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c3",
        terminalSessionID: "s3",
        projectPath: "/c"
    )

    // s2 goes working via hook
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    let cyclable = manager.cyclableSessions
    let cyclableIDs = Set(cyclable.map(\.id))
    #expect(cyclableIDs.contains("s1"))
    #expect(cyclableIDs.contains("s3"))
    #expect(!cyclableIDs.contains("s2"))
}

// MARK: - Terminal Focus Event → UI State

@Test @MainActor func integration_focusEvent_updatesCurrentSession() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    manager.updateFocusedSession(terminalSessionID: "s2")

    #expect(manager.focusedSessionID == "s2")
    #expect(manager.currentSession?.id == "s2")
}

@Test @MainActor func integration_focusEvent_isSessionFocused() {
    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )

    #expect(manager.isSessionFocused == false)

    manager.updateFocusedSession(terminalSessionID: "s1")
    manager.isTerminalAppActive = true

    #expect(manager.isSessionFocused == true)
}

// MARK: - Full Lifecycle

@Test @MainActor func integration_fullLifecycle() {
    let manager = SessionManager()

    // 1. Sessions arrive via hooks
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/project-a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/project-b"
    )
    #expect(manager.sessions.count == 2)
    #expect(manager.cyclableSessions.count == 2)

    // 2. Terminal reports focus on s1 (simulates iTerm2/Kitty event)
    manager.updateFocusedSession(terminalSessionID: "s1")
    manager.isTerminalAppActive = true
    #expect(manager.currentSession?.id == "s1")
    #expect(manager.isSessionFocused == true)

    // 3. User cycles forward → moves to s2
    let next = manager.cycleForward()
    #expect(next?.id == "s2")
    #expect(manager.focusedSessionID == "s2")

    // 4. s2 starts working (hook: UserPromptSubmit)
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/project-b"
    )
    #expect(manager.sessions.first { $0.id == "s2" }?.state == .working)

    // 5. Only s1 remains cyclable
    #expect(manager.cyclableSessions.count == 1)
    #expect(manager.cyclableSessions[0].id == "s1")

    // 6. s2 finishes (hook: Stop → idle)
    simulateHook(
        manager: manager,
        event: "Stop",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/project-b"
    )
    #expect(manager.cyclableSessions.count == 2)

    // 7. Session ends
    simulateHook(manager: manager, event: "SessionEnd", terminalSessionID: "s1")
    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].id == "s2")
}

// MARK: - PreCompact & SubagentStop

@Test @MainActor func integration_preCompact_setsCompactingState() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    simulateHook(manager: manager, event: "UserPromptSubmit", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .working)

    simulateHook(manager: manager, event: "PreCompact", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .compacting)
}

@Test @MainActor func integration_subagentStop_isIgnored() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    simulateHook(manager: manager, event: "UserPromptSubmit", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .working)

    // SubagentStop maps to .ignore — state should not change
    simulateHook(manager: manager, event: "SubagentStop", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .working)
}

// MARK: - Backburner Preservation via Hooks

@Test @MainActor func integration_backburner_preservedOnNonUserPromptHooks() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .backburner)
    #expect(manager.sessions[0].state == .backburner)

    // Stop hook on backburnered session — should stay backburner
    simulateHook(manager: manager, event: "Stop", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .backburner)

    // PreToolUse hook on backburnered session — should stay backburner
    simulateHook(manager: manager, event: "PreToolUse", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .backburner)
}

@Test @MainActor func integration_backburner_exitsOnUserPromptSubmit() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .backburner)
    #expect(manager.sessions[0].state == .backburner)

    // UserPromptSubmit should exit backburner
    simulateHook(manager: manager, event: "UserPromptSubmit", terminalSessionID: "s1")
    #expect(manager.sessions[0].state == .working)
}

// MARK: - Backburner Does Not Trigger Auto-Advance

@Test @MainActor func integration_goToNextOnBackburner_doesNotAnchor() {
    UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    manager.updateFocusedSession(terminalSessionID: "s1")

    // Backburner s1 — should NOT set lastActiveSessionID anchor
    manager.backburnerSession(terminalSessionID: "s1")

    #expect(manager.lastActiveSessionID == nil)
    // currentSession should return s2 (next cyclable), not s1 via anchor
    #expect(manager.currentSession?.id == "s2")
}

@Test @MainActor func integration_backburner_doesNotPostAutoAdvance() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    var posted = false
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoAdvance, object: nil, queue: nil
    ) { _ in posted = true }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    manager.updateFocusedSession(terminalSessionID: "s1")

    manager.backburnerSession(terminalSessionID: "s1")
    #expect(posted == false)
}

// MARK: - Tmux Pane Composite ID

@Test @MainActor func integration_tmuxPane_compositeID_lifecycle() {
    let manager = SessionManager()

    // Session with tmux pane creates composite ID
    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1", tmuxPane: "%1", projectPath: "/a")
    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].id == "s1:%1")

    // State transition works with composite ID
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        terminalSessionID: "s1",
        tmuxPane: "%1",
        projectPath: "/a"
    )
    #expect(manager.sessions[0].state == .working)

    // Session removal via SessionEnd with same tmux pane
    simulateHook(manager: manager, event: "SessionEnd", terminalSessionID: "s1", tmuxPane: "%1")
    #expect(manager.sessions.isEmpty)
}

// MARK: - Timestamp Tracking

@Test @MainActor func integration_timestamps_setOnStateTransitions() {
    let manager = SessionManager()

    simulateHook(manager: manager, event: "SessionStart", terminalSessionID: "s1")
    let session0 = manager.sessions[0]
    // New session starts idle — lastBecameIdle should be set by handleStateTransition
    #expect(session0.lastBecameIdle != nil || session0.state == .idle)

    // Transition to working
    simulateHook(manager: manager, event: "UserPromptSubmit", terminalSessionID: "s1")
    let session1 = manager.sessions[0]
    #expect(session1.lastBecameWorking != nil)

    // Transition back to idle
    simulateHook(manager: manager, event: "Stop", terminalSessionID: "s1")
    let session2 = manager.sessions[0]
    #expect(session2.lastBecameIdle != nil)
    #expect(session2.accumulatedWorkingTime >= 0)
}

// MARK: - Queue Reordering

@Test @MainActor func integration_fairMode_reorderOnStateTransition() {
    UserDefaults.standard.set(QueueOrderMode.fair.rawValue, forKey: "queueOrderMode")
    defer { UserDefaults.standard.removeObject(forKey: "queueOrderMode") }

    let manager = SessionManager()

    // Create 3 idle sessions: s1, s2, s3
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c3",
        terminalSessionID: "s3",
        projectPath: "/c"
    )

    // s1 goes working
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )

    // In fair mode, s1 (now working) should move to bottom of busy section
    // s2 and s3 remain idle, s1 is working
    let workingIDs = manager.sessions.filter { $0.state == .working }.map(\.id)
    #expect(workingIDs == ["s1"])

    // s1 returns to idle — in fair mode, should go to BOTTOM of idle group
    simulateHook(manager: manager, event: "Stop", claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/a")
    let idleIDs = manager.sessions.filter { $0.state == .idle }.map(\.id)
    #expect(idleIDs.last == "s1")
}

@Test @MainActor func integration_prioMode_reorderOnStateTransition() {
    UserDefaults.standard.set(QueueOrderMode.prio.rawValue, forKey: "queueOrderMode")
    defer { UserDefaults.standard.removeObject(forKey: "queueOrderMode") }

    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c3",
        terminalSessionID: "s3",
        projectPath: "/c"
    )

    // s3 goes working then idle
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c3",
        terminalSessionID: "s3",
        projectPath: "/c"
    )
    simulateHook(manager: manager, event: "Stop", claudeSessionID: "c3", terminalSessionID: "s3", projectPath: "/c")

    // In prio mode, s3 (returning to idle) should go to TOP of idle group
    let idleIDs = manager.sessions.filter { $0.state == .idle }.map(\.id)
    #expect(idleIDs.first == "s3")
}

// MARK: - Auto-Advance

@Test @MainActor func integration_autoAdvance_on_postsNotification() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    var posted = false
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoAdvance, object: nil, queue: nil
    ) { _ in posted = true }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()

    // Two sessions arrive via hooks
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    // User is focused on s1
    manager.testSetFocusedSessionID("s1")

    // s1 goes busy via hook → auto-advance fires
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )

    #expect(posted == true)
}

@Test @MainActor func integration_autoAdvance_off_setsAnchor() {
    UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    let manager = SessionManager()

    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    manager.testSetFocusedSessionID("s1")

    // s1 goes busy via hook — auto-advance is OFF, so anchor should be set
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )

    #expect(manager.lastActiveSessionID == "s1")
    // currentSession should still return the busy s1 (anchored)
    #expect(manager.currentSession?.id == "s1")
    #expect(manager.currentSession?.state == .working)
}

@Test @MainActor func integration_autoAdvance_lifecycle() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    var autoAdvanceFired = false
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoAdvance, object: nil, queue: nil
    ) { _ in autoAdvanceFired = true }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()

    // 1. Sessions arrive
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    // 2. User focuses s1
    manager.updateFocusedSession(terminalSessionID: "s1")

    // 3. s1 goes busy via hook → auto-advance fires
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    #expect(autoAdvanceFired == true)

    // 4. In response to notification, HotkeyManager would call cycleForward
    let next = manager.cycleForward()
    #expect(next?.id == "s2")
    #expect(manager.focusedSessionID == "s2")

    // 5. s1 finishes via hook → idle again, both cyclable
    simulateHook(manager: manager, event: "Stop", claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/a")
    #expect(manager.cyclableSessions.count == 2)
}

// MARK: - Auto-Restart

@Test @MainActor func integration_autoRestart_on_soleCyclable_postsNotification() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

    var restartSessionID: String?
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoRestart, object: nil, queue: nil
    ) { notification in
        restartSessionID = notification.userInfo?["sessionID"] as? String
    }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()

    // Two sessions, both go working via hooks
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    #expect(manager.cyclableSessions.isEmpty)

    // s1 goes idle via hook — sole cyclable session
    simulateHook(manager: manager, event: "Stop", claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/a")

    #expect(restartSessionID == "s1")
}

@Test @MainActor func integration_autoRestart_on_multipleCyclable_noNotification() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

    var posted = false
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoRestart, object: nil, queue: nil
    ) { _ in posted = true }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()

    // Two sessions: s1 idle, s2 goes working via hook
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    #expect(manager.cyclableSessions.count == 1) // only s1

    // s2 goes idle via hook — now 2 cyclable, should NOT auto-restart
    simulateHook(manager: manager, event: "Stop", claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/b")

    #expect(posted == false)
    #expect(manager.cyclableSessions.count == 2)
}

@Test @MainActor func integration_autoRestart_lifecycle() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

    var restartSessionID: String?
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoRestart, object: nil, queue: nil
    ) { notification in
        restartSessionID = notification.userInfo?["sessionID"] as? String
    }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()

    // 1. Two sessions arrive, both go working via hooks
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "SessionStart",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c1",
        terminalSessionID: "s1",
        projectPath: "/a"
    )
    simulateHook(
        manager: manager,
        event: "UserPromptSubmit",
        claudeSessionID: "c2",
        terminalSessionID: "s2",
        projectPath: "/b"
    )

    // 2. s1 finishes via hook → sole cyclable → auto-restart fires
    simulateHook(manager: manager, event: "Stop", claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/a")
    #expect(restartSessionID == "s1")

    // 3. HotkeyManager would activate s1 — simulate focus arriving
    manager.updateFocusedSession(terminalSessionID: "s1")
    manager.isTerminalAppActive = true
    #expect(manager.currentSession?.id == "s1")
    #expect(manager.isSessionFocused == true)
}
