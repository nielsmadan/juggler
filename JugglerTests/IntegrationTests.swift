import Foundation
@testable import Juggler
import Testing

@Suite("Hooks → SessionManager", .serialized, .tags(.integration))
struct IntegrationTests {
    // MARK: - Integration Test Helper

    /// Sends an HTTP request through a real HookServer with an injected SessionManager.
    /// This exercises the full pipeline: HTTP → JSON decode → field extraction → SessionManager mutation.
    @MainActor
    private func simulateHook(
        server: HookServer,
        agent: String = "claude-code",
        event: String,
        claudeSessionID: String = "claude-1",
        terminalSessionID: String,
        tmuxPane: String? = nil,
        tmuxSessionName: String? = nil,
        projectPath: String = "/test/project",
        gitBranch: String? = nil,
        gitRepoName: String? = nil
    ) async {
        struct HookPayload: Encodable {
            struct HookInput: Encodable { let session_id: String }
            struct Terminal: Encodable { let sessionId: String; let cwd: String }
            struct Git: Encodable { let branch: String?; let repo: String? }
            struct Tmux: Encodable { let pane: String?; let sessionName: String? }
            let agent: String
            let event: String
            let hookInput: HookInput
            let terminal: Terminal
            let git: Git?
            let tmux: Tmux?
        }

        let payload = HookPayload(
            agent: agent,
            event: event,
            hookInput: .init(session_id: claudeSessionID),
            terminal: .init(sessionId: terminalSessionID, cwd: projectPath),
            git: (gitBranch != nil || gitRepoName != nil)
                ? .init(branch: gitBranch, repo: gitRepoName) : nil,
            tmux: (tmuxPane != nil || tmuxSessionName != nil)
                ? .init(pane: tmuxPane, sessionName: tmuxSessionName) : nil
        )

        // swiftlint:disable:next force_try
        let body = String(data: try! JSONEncoder().encode(payload), encoding: .utf8)!
        let request = HTTPRequest(method: "POST", path: "/hook", body: body)
        let response = await server.processRequest(request)
        #expect(response.status == 200)
    }

    // MARK: - Hook → Session Appears

    @Test @MainActor func integration_sessionStart_createsSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
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

    @Test @MainActor func integration_sessionEnd_removesSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        #expect(manager.sessions.count == 1)

        await simulateHook(server: server, event: "SessionEnd", terminalSessionID: "s1")
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func integration_multipleSessionsFromHooks() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c3",
            terminalSessionID: "s3",
            projectPath: "/c"
        )

        #expect(manager.sessions.count == 3)
        #expect(manager.cyclableSessions.count == 3)
    }

    // MARK: - State Transitions via Hooks

    @Test @MainActor func integration_stateTransitions_idleWorkingIdle() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .idle)

        await simulateHook(server: server, event: "UserPromptSubmit", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .working)

        await simulateHook(server: server, event: "Stop", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .idle)
    }

    @Test @MainActor func integration_permissionState() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        await simulateHook(server: server, event: "PermissionRequest", terminalSessionID: "s1")

        #expect(manager.sessions[0].state == .permission)
        #expect(manager.sessions[0].state.isIncludedInCycle)
    }

    // MARK: - Cycle Forward

    @Test @MainActor func integration_cycleForward_setsFocusedSessionID() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        let target = manager.cycleForward()
        #expect(target != nil)
        #expect(manager.focusedSessionID == target!.id)
    }

    @Test @MainActor func integration_cycleSkipsBusySessions() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c3",
            terminalSessionID: "s3",
            projectPath: "/c"
        )

        // s2 goes working via hook
        await simulateHook(
            server: server,
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

    @Test @MainActor func integration_focusEvent_updatesCurrentSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        manager.updateFocusedSession(terminalSessionID: "s2")

        #expect(manager.focusedSessionID == "s2")
        #expect(manager.currentSession?.id == "s2")
    }

    @Test @MainActor func integration_focusEvent_isSessionFocused() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
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

    @Test @MainActor func integration_fullLifecycle() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // 1. Sessions arrive via hooks
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/project-a"
        )
        await simulateHook(
            server: server,
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
        await simulateHook(
            server: server,
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
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/project-b"
        )
        #expect(manager.cyclableSessions.count == 2)

        // 7. Session ends
        await simulateHook(server: server, event: "SessionEnd", terminalSessionID: "s1")
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "s2")
    }

    // MARK: - PreCompact & SubagentStop

    @Test @MainActor func integration_preCompact_setsCompactingState() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        await simulateHook(server: server, event: "UserPromptSubmit", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .working)

        await simulateHook(server: server, event: "PreCompact", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .compacting)
    }

    @Test @MainActor func integration_subagentStop_isIgnored() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        await simulateHook(server: server, event: "UserPromptSubmit", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .working)

        // SubagentStop maps to .ignore — state should not change
        await simulateHook(server: server, event: "SubagentStop", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .working)
    }

    // MARK: - Backburner Preservation via Hooks

    @Test @MainActor func integration_backburner_preservedOnNonUserPromptHooks() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .backburner)
        #expect(manager.sessions[0].state == .backburner)

        // Stop hook on backburnered session — should stay backburner
        await simulateHook(server: server, event: "Stop", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .backburner)

        // PreToolUse hook on backburnered session — should stay backburner
        await simulateHook(server: server, event: "PreToolUse", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .backburner)
    }

    @Test @MainActor func integration_backburner_exitsOnUserPromptSubmit() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .backburner)
        #expect(manager.sessions[0].state == .backburner)

        // UserPromptSubmit should exit backburner
        await simulateHook(server: server, event: "UserPromptSubmit", terminalSessionID: "s1")
        #expect(manager.sessions[0].state == .working)
    }

    // MARK: - Backburner Does Not Trigger Auto-Advance

    @Test @MainActor func integration_goToNextOnBackburner_doesNotAnchor() async {
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
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

    @Test @MainActor func integration_backburner_doesNotPostAutoAdvance() async {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
        defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .shouldAutoAdvance, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
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

    @Test @MainActor func integration_tmuxPane_compositeID_lifecycle() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Session with tmux pane creates composite ID
        await simulateHook(
            server: server,
            event: "SessionStart",
            terminalSessionID: "s1",
            tmuxPane: "%1",
            projectPath: "/a"
        )
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "s1:%1")

        // State transition works with composite ID
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            terminalSessionID: "s1",
            tmuxPane: "%1",
            projectPath: "/a"
        )
        #expect(manager.sessions[0].state == .working)

        // Session removal via SessionEnd with same tmux pane
        await simulateHook(server: server, event: "SessionEnd", terminalSessionID: "s1", tmuxPane: "%1")
        #expect(manager.sessions.isEmpty)
    }

    // MARK: - Timestamp Tracking

    @Test @MainActor func integration_timestamps_setOnStateTransitions() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, event: "SessionStart", terminalSessionID: "s1")
        let session0 = manager.sessions[0]
        // New session starts idle — lastBecameIdle should be set by handleStateTransition
        #expect(session0.lastBecameIdle != nil || session0.state == .idle)

        // Transition to working
        await simulateHook(server: server, event: "UserPromptSubmit", terminalSessionID: "s1")
        let session1 = manager.sessions[0]
        #expect(session1.lastBecameWorking != nil)

        // Transition back to idle
        await simulateHook(server: server, event: "Stop", terminalSessionID: "s1")
        let session2 = manager.sessions[0]
        #expect(session2.lastBecameIdle != nil)
        #expect(session2.accumulatedWorkingTime >= 0)
    }

    // MARK: - Queue Reordering

    @Test @MainActor func integration_fairMode_reorderOnStateTransition() async {
        UserDefaults.standard.set(QueueOrderMode.fair.rawValue, forKey: "queueOrderMode")
        defer { UserDefaults.standard.removeObject(forKey: "queueOrderMode") }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Create 3 idle sessions: s1, s2, s3
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c3",
            terminalSessionID: "s3",
            projectPath: "/c"
        )

        // s1 goes working
        await simulateHook(
            server: server,
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
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        let idleIDs = manager.sessions.filter { $0.state == .idle }.map(\.id)
        #expect(idleIDs.last == "s1")
    }

    @Test @MainActor func integration_prioMode_reorderOnStateTransition() async {
        UserDefaults.standard.set(QueueOrderMode.prio.rawValue, forKey: "queueOrderMode")
        defer { UserDefaults.standard.removeObject(forKey: "queueOrderMode") }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c3",
            terminalSessionID: "s3",
            projectPath: "/c"
        )

        // s3 goes working then idle
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c3",
            terminalSessionID: "s3",
            projectPath: "/c"
        )
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c3",
            terminalSessionID: "s3",
            projectPath: "/c"
        )

        // In prio mode, s3 (returning to idle) should go to TOP of idle group
        let idleIDs = manager.sessions.filter { $0.state == .idle }.map(\.id)
        #expect(idleIDs.first == "s3")
    }

    // MARK: - Auto-Advance

    @Test @MainActor func integration_autoAdvance_on_postsNotification() async {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
        defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .shouldAutoAdvance, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Two sessions arrive via hooks
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        // User is focused on s1
        manager.testSetFocusedSessionID("s1")

        // s1 goes busy via hook → auto-advance fires
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )

        #expect(posted == true)
    }

    @Test @MainActor func integration_autoAdvance_off_setsAnchor() async {
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        manager.testSetFocusedSessionID("s1")

        // s1 goes busy via hook — auto-advance is OFF, so anchor should be set
        await simulateHook(
            server: server,
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

    @Test @MainActor func integration_autoAdvance_lifecycle() async {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
        defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

        var autoAdvanceFired = false
        let token = NotificationCenter.default.addObserver(
            forName: .shouldAutoAdvance, object: nil, queue: nil
        ) { _ in autoAdvanceFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // 1. Sessions arrive
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        // 2. User focuses s1
        manager.updateFocusedSession(terminalSessionID: "s1")

        // 3. s1 goes busy via hook → auto-advance fires
        await simulateHook(
            server: server,
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
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        #expect(manager.cyclableSessions.count == 2)
    }

    // MARK: - Auto-Restart

    @Test @MainActor func integration_autoRestart_on_soleCyclable_postsNotification() async {
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
        let server = HookServer(sessionManager: manager)

        // Two sessions, both go working via hooks
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        #expect(manager.cyclableSessions.isEmpty)

        // s1 goes idle via hook — sole cyclable session
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )

        #expect(restartSessionID == "s1")
    }

    @Test @MainActor func integration_autoRestart_on_multipleCyclable_noNotification() async {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
        defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .shouldAutoRestart, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Two sessions: s1 idle, s2 goes working via hook
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        #expect(manager.cyclableSessions.count == 1) // only s1

        // s2 goes idle via hook — now 2 cyclable, should NOT auto-restart
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        #expect(posted == false)
        #expect(manager.cyclableSessions.count == 2)
    }

    @Test @MainActor func integration_autoRestart_lifecycle() async {
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
        let server = HookServer(sessionManager: manager)

        // 1. Two sessions arrive, both go working via hooks
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "UserPromptSubmit",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        // 2. s1 finishes via hook → sole cyclable → auto-restart fires
        await simulateHook(
            server: server,
            event: "Stop",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        #expect(restartSessionID == "s1")

        // 3. HotkeyManager would activate s1 — simulate focus arriving
        manager.updateFocusedSession(terminalSessionID: "s1")
        manager.isTerminalAppActive = true
        #expect(manager.currentSession?.id == "s1")
        #expect(manager.isSessionFocused == true)
    }

    // MARK: - Focus Normalization & Activation Guard

    @Test @MainActor func integration_focusBeforeSessionCreated_normalizesOnArrival() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Focus arrives with bare UUID before session exists — stored as-is
        manager.updateFocusedSession(terminalSessionID: "abc-uuid")
        #expect(manager.focusedSessionID == "abc-uuid")

        // Session arrives via hook with composite terminalSessionID
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "w0t0p0:abc-uuid",
            projectPath: "/test"
        )

        // focusedSessionID should be re-normalized to the full composite ID
        #expect(manager.focusedSessionID == "w0t0p0:abc-uuid")

        // isSessionFocused should work correctly now
        manager.isTerminalAppActive = true
        #expect(manager.isSessionFocused == true)
    }

    @Test @MainActor func integration_guiActivation_suppressesFocusResyncDuringFlight() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Two sessions arrive via hooks
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        // User is focused on s1
        manager.updateFocusedSession(terminalSessionID: "s1")
        manager.isTerminalAppActive = true
        #expect(manager.focusedSessionID == "s1")

        // User presses Enter in monitor to activate s2 → beginActivation
        manager.beginActivation(targetSessionID: "s2")
        #expect(manager.activationTarget == "s2")

        // Intermediate focus event for s1 (terminal still showing s1) — should be suppressed
        manager.updateFocusedSession(terminalSessionID: "s1")
        #expect(manager.focusedSessionID == "s1") // unchanged from before activation

        // Target focus arrives for s2 → accepted and guard auto-cleared
        manager.updateFocusedSession(terminalSessionID: "s2")
        #expect(manager.focusedSessionID == "s2")
        #expect(manager.activationTarget == nil)
    }

    @Test @MainActor func integration_guiActivation_endActivationAllowsSubsequentFocus() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "s1",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "s2",
            projectPath: "/b"
        )

        // Activation completes normally
        manager.beginActivation(targetSessionID: "s1")
        manager.endActivation()
        #expect(manager.activationTarget == nil)

        // Subsequent focus change should not be suppressed
        manager.updateFocusedSession(terminalSessionID: "s2")
        #expect(manager.focusedSessionID == "s2")
    }

    @Test @MainActor func integration_bareUUIDNormalization_thenCycling() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Two sessions with composite IDs
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c1",
            terminalSessionID: "w0t0p0:uuid-a",
            projectPath: "/a"
        )
        await simulateHook(
            server: server,
            event: "SessionStart",
            claudeSessionID: "c2",
            terminalSessionID: "w0t1p0:uuid-b",
            projectPath: "/b"
        )

        // Focus via bare UUID — should be normalized to composite
        manager.updateFocusedSession(terminalSessionID: "uuid-a")
        #expect(manager.focusedSessionID == "w0t0p0:uuid-a")

        // currentSession should resolve correctly
        #expect(manager.currentSession?.id == "w0t0p0:uuid-a")

        // Cycling should move to the other session
        let next = manager.cycleForward()
        #expect(next?.id == "w0t1p0:uuid-b")
    }

    // MARK: - OpenCode Hook Integration

    @Test @MainActor func integration_opencode_sessionCreated_createsSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1",
            projectPath: "/Users/test/oc-project"
        )

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalSessionID == "s1")
        #expect(manager.sessions[0].state == .idle)
        #expect(manager.sessions[0].agent == "opencode")
        #expect(manager.sessions[0].projectPath == "/Users/test/oc-project")
    }

    @Test @MainActor func integration_opencode_statusBusy_toWorking() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions[0].state == .idle)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.status.busy",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions[0].state == .working)
    }

    @Test @MainActor func integration_opencode_statusBusy_then_statusIdle_returnsToIdle() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.status.busy",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions[0].state == .working)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.status.idle",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions[0].state == .idle)
    }

    @Test @MainActor func integration_opencode_permissionAsked_state() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "permission.asked",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )

        #expect(manager.sessions[0].state == .permission)
        #expect(manager.sessions[0].state.isIncludedInCycle)
    }

    @Test @MainActor func integration_opencode_sessionCompacted_compactingState() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.status.busy",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.compacted",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )

        #expect(manager.sessions[0].state == .compacting)
    }

    @Test @MainActor func integration_opencode_sessionDeleted_removesSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions.count == 1)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.deleted",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func integration_opencode_serverDisposed_removesSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions.count == 1)

        // server.instance.disposed maps to .removeSession in HookEventMapper.mapOpenCode,
        // so the associated session should be removed from the manager.
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "server.instance.disposed",
            claudeSessionID: "oc-1",
            terminalSessionID: "s1"
        )
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func integration_opencode_mixedWithClaudeCode_bothTracked() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        // Claude Code session
        await simulateHook(
            server: server,
            agent: "claude-code",
            event: "SessionStart",
            claudeSessionID: "cc-1",
            terminalSessionID: "s-cc",
            projectPath: "/claude/project"
        )

        // OpenCode session
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.created",
            claudeSessionID: "oc-1",
            terminalSessionID: "s-oc",
            projectPath: "/opencode/project"
        )

        #expect(manager.sessions.count == 2)

        let ccSession = manager.sessions.first { $0.id == "s-cc" }
        let ocSession = manager.sessions.first { $0.id == "s-oc" }

        #expect(ccSession?.agent == "claude-code")
        #expect(ccSession?.state == .idle)
        #expect(ocSession?.agent == "opencode")
        #expect(ocSession?.state == .idle)

        // Verify they update independently: OpenCode goes working, Claude stays idle
        await simulateHook(
            server: server,
            agent: "opencode",
            event: "session.status.busy",
            claudeSessionID: "oc-1",
            terminalSessionID: "s-oc",
            projectPath: "/opencode/project"
        )

        #expect(manager.sessions.first { $0.id == "s-oc" }?.state == .working)
        #expect(manager.sessions.first { $0.id == "s-cc" }?.state == .idle)
    }

    // MARK: - Codex Hook Integration

    @Test @MainActor func integration_codex_sessionStart_createsSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "codex",
            event: "SessionStart",
            claudeSessionID: "codex-1",
            terminalSessionID: "s1",
            projectPath: "/Users/test/codex-project"
        )

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalSessionID == "s1")
        #expect(manager.sessions[0].state == .idle)
        #expect(manager.sessions[0].agent == "codex")
        #expect(manager.sessions[0].projectPath == "/Users/test/codex-project")
    }

    @Test @MainActor func integration_codex_stateTransitions() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(server: server, agent: "codex", event: "SessionStart",
                           claudeSessionID: "codex-1", terminalSessionID: "s1")
        #expect(manager.sessions.first?.state == .idle)

        await simulateHook(server: server, agent: "codex", event: "UserPromptSubmit",
                           claudeSessionID: "codex-1", terminalSessionID: "s1")
        #expect(manager.sessions.first?.state == .working)

        await simulateHook(server: server, agent: "codex", event: "PermissionRequest",
                           claudeSessionID: "codex-1", terminalSessionID: "s1")
        #expect(manager.sessions.first?.state == .permission)

        await simulateHook(server: server, agent: "codex", event: "PreCompact",
                           claudeSessionID: "codex-1", terminalSessionID: "s1")
        #expect(manager.sessions.first?.state == .compacting)

        await simulateHook(server: server, agent: "codex", event: "PostCompact",
                           claudeSessionID: "codex-1", terminalSessionID: "s1")
        #expect(manager.sessions.first?.state == .working)

        await simulateHook(server: server, agent: "codex", event: "Stop",
                           claudeSessionID: "codex-1", terminalSessionID: "s1")
        #expect(manager.sessions.first?.state == .idle)

        // The whole sequence is a single session.
        #expect(manager.sessions.count == 1)
    }

    @Test @MainActor func integration_codex_mixedWithClaudeCode_bothTracked() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await simulateHook(
            server: server,
            agent: "claude-code",
            event: "SessionStart",
            claudeSessionID: "cc-1",
            terminalSessionID: "s-cc",
            projectPath: "/claude/project"
        )
        await simulateHook(
            server: server,
            agent: "codex",
            event: "SessionStart",
            claudeSessionID: "codex-1",
            terminalSessionID: "s-codex",
            projectPath: "/codex/project"
        )

        #expect(manager.sessions.count == 2)
        #expect(manager.sessions.first { $0.id == "s-cc" }?.agent == "claude-code")
        #expect(manager.sessions.first { $0.id == "s-codex" }?.agent == "codex")

        // They update independently: Codex goes working, Claude stays idle.
        await simulateHook(
            server: server,
            agent: "codex",
            event: "UserPromptSubmit",
            claudeSessionID: "codex-1",
            terminalSessionID: "s-codex",
            projectPath: "/codex/project"
        )
        #expect(manager.sessions.first { $0.id == "s-codex" }?.state == .working)
        #expect(manager.sessions.first { $0.id == "s-cc" }?.state == .idle)
    }
}
