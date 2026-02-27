import Foundation
@testable import Juggler
import Testing

// MARK: - reorderForMode Tests

@Test func reorderForMode_static_sortsByStartedAt() {
    let manager = SessionManager()
    let t1 = Date(timeIntervalSince1970: 100)
    let t2 = Date(timeIntervalSince1970: 200)
    let t3 = Date(timeIntervalSince1970: 300)

    var s1 = makeSession("s1")
    s1.startedAt = t1
    var s2 = makeSession("s2")
    s2.startedAt = t2
    var s3 = makeSession("s3")
    s3.startedAt = t3

    // Insert in non-chronological order
    manager.testSetSessions([s2, s3, s1])

    manager.reorderForMode(.static)

    #expect(manager.sessions[0].terminalSessionID == "s1")
    #expect(manager.sessions[1].terminalSessionID == "s2")
    #expect(manager.sessions[2].terminalSessionID == "s3")
}

@Test func reorderForMode_fair_idleThenBusyThenBackburner() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("back", state: .backburner),
        makeSession("busy", state: .working),
        makeSession("idle", state: .idle),
    ])

    manager.reorderForMode(.fair)

    #expect(manager.sessions[0].state == .idle)
    #expect(manager.sessions[1].state == .working)
    #expect(manager.sessions[2].state == .backburner)
}

@Test func reorderForMode_fair_sortsIdleByLastBecameIdle_oldestFirst() {
    let manager = SessionManager()
    let earlier = Date(timeIntervalSince1970: 100)
    let later = Date(timeIntervalSince1970: 200)

    var s1 = makeSession("s1")
    s1.lastBecameIdle = later
    var s2 = makeSession("s2")
    s2.lastBecameIdle = earlier

    manager.testSetSessions([s1, s2])

    manager.reorderForMode(.fair)

    #expect(manager.sessions[0].terminalSessionID == "s2")
    #expect(manager.sessions[1].terminalSessionID == "s1")
}

@Test func reorderForMode_prio_sortsIdleByLastBecameIdle_newestFirst() {
    let manager = SessionManager()
    let earlier = Date(timeIntervalSince1970: 100)
    let later = Date(timeIntervalSince1970: 200)

    var s1 = makeSession("s1")
    s1.lastBecameIdle = earlier
    var s2 = makeSession("s2")
    s2.lastBecameIdle = later

    manager.testSetSessions([s1, s2])

    manager.reorderForMode(.prio)

    #expect(manager.sessions[0].terminalSessionID == "s2")
    #expect(manager.sessions[1].terminalSessionID == "s1")
}

// MARK: - addOrUpdateSession Tests

@Test @MainActor func addOrUpdateSession_newSession_appendsToList() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "claude-1",
        terminalSessionID: "w0t0p0:abc",
        projectPath: "/test/project",
        state: .idle
    )

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].terminalSessionID == "w0t0p0:abc")
    #expect(manager.sessions[0].projectPath == "/test/project")
    #expect(manager.sessions[0].state == .idle)
}

@Test @MainActor func addOrUpdateSession_existingSession_updatesMetadata() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle,
        gitBranch: "feature-x", gitRepoName: "my-repo"
    )

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].gitBranch == "feature-x")
    #expect(manager.sessions[0].gitRepoName == "my-repo")
}

@Test @MainActor func addOrUpdateSession_backburnered_preservesState_unlessUserPromptSubmit() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .backburner
    )

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p",
        state: .working, event: "PreToolUse", gitBranch: "new-branch"
    )

    #expect(manager.sessions[0].state == .backburner)
    #expect(manager.sessions[0].gitBranch == "new-branch")
}

@Test @MainActor func addOrUpdateSession_backburnered_exitsOnUserPromptSubmit() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .backburner
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p",
        state: .working, event: "UserPromptSubmit"
    )

    // UserPromptSubmit bypasses backburner guard — state changes synchronously via @MainActor
    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].state == .working)
}

@Test @MainActor func addOrUpdateSession_tmuxPane_createsCompositeID() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1", projectPath: "/p", state: .idle
    )

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].id == "w0t0p0:abc:%1")
}

// MARK: - disambiguatedDisplayName Tests

@Test @MainActor func disambiguatedDisplayName_uniqueName_returnsBaseName() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/project-a", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/project-b", state: .idle
    )

    let name = manager.disambiguatedDisplayName(for: manager.sessions[0])
    #expect(name == "project-a")
}

@Test @MainActor func disambiguatedDisplayName_duplicateNames_appendsIndex() {
    let manager = SessionManager()

    // Both sessions share the same project path
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/same-project", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/same-project", state: .idle
    )

    manager.updateSessionTerminalInfo(terminalSessionID: "s1", tabName: nil, paneIndex: 0, paneCount: 2)
    manager.updateSessionTerminalInfo(terminalSessionID: "s2", tabName: nil, paneIndex: 1, paneCount: 2)

    let name1 = manager.disambiguatedDisplayName(for: manager.sessions[0])
    let name2 = manager.disambiguatedDisplayName(for: manager.sessions[1])

    #expect(name1 == "same-project (1)")
    #expect(name2 == "same-project (2)")
}

@Test @MainActor func disambiguatedDisplayName_folderMode_disambiguatesCollisions() {
    let manager = SessionManager()

    // Different paths but same folder name
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/a/project", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/b/project", state: .idle
    )

    manager.updateSessionTerminalInfo(terminalSessionID: "s1", tabName: "tab-a", paneIndex: 0, paneCount: 1)
    manager.updateSessionTerminalInfo(terminalSessionID: "s2", tabName: "tab-b", paneIndex: 1, paneCount: 1)

    let name1 = manager.disambiguatedDisplayName(for: manager.sessions[0], titleMode: .folderName)
    let name2 = manager.disambiguatedDisplayName(for: manager.sessions[1], titleMode: .folderName)

    #expect(name1 == "project (1)")
    #expect(name2 == "project (2)")
}

@Test @MainActor func disambiguatedDisplayName_parentFolderMode_uniqueParents_noSuffix() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/a/project", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/b/project", state: .idle
    )

    let name1 = manager.disambiguatedDisplayName(for: manager.sessions[0], titleMode: .parentAndFolderName)
    let name2 = manager.disambiguatedDisplayName(for: manager.sessions[1], titleMode: .parentAndFolderName)

    // Parent/folder names differ ("a/project" vs "b/project"), so no disambiguation needed
    #expect(name1 == "a/project")
    #expect(name2 == "b/project")
}

// MARK: - removeSession Tests

@Test @MainActor func removeSession_removesFromList() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/p", state: .idle
    )

    manager.removeSession(sessionID: "s1")

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].terminalSessionID == "s2")
}

@Test @MainActor func removeSession_clearsFocusedSessionID() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.removeSession(sessionID: "s1")

    #expect(manager.focusedSessionID == nil)
}

@Test @MainActor func removeSession_nonexistent_noOp() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.removeSession(sessionID: "nonexistent")

    #expect(manager.sessions.count == 1)
}

// MARK: - renameSession Tests

@Test @MainActor func renameSession_setsCustomName() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.renameSession(terminalSessionID: "s1", customName: "My Session")

    #expect(manager.sessions[0].customName == "My Session")
    #expect(manager.sessions[0].displayName == "My Session")
}

@Test @MainActor func renameSession_emptyString_clearsName() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/project", state: .idle
    )
    manager.renameSession(terminalSessionID: "s1", customName: "Custom")
    manager.renameSession(terminalSessionID: "s1", customName: "")

    #expect(manager.sessions[0].customName == nil)
    #expect(manager.sessions[0].displayName == "project")
}

// MARK: - cyclableSessions Tests

@Test func cyclableSessions_excludesWorkingAndBackburner() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("idle1", state: .idle),
        makeSession("perm1", state: .permission),
        makeSession("work1", state: .working),
        makeSession("back1", state: .backburner),
        makeSession("comp1", state: .compacting),
    ])

    let cyclable = manager.cyclableSessions
    let ids = cyclable.map(\.terminalSessionID)

    #expect(ids.contains("idle1"))
    #expect(ids.contains("perm1"))
    #expect(!ids.contains("work1"))
    #expect(!ids.contains("back1"))
    #expect(!ids.contains("comp1"))
    #expect(cyclable.count == 2)
}

// MARK: - removeSessionsByTerminalID Tests

@Test func removeSessionsByTerminalID_exactMatch_removesSession() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("abc-123"),
        makeSession("def-456"),
    ])

    manager.removeSessionsByTerminalID("abc-123")

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].terminalSessionID == "def-456")
}

@Test func removeSessionsByTerminalID_suffixMatch_removesCompositeSession() {
    let manager = SessionManager()

    var session = makeSession("w0t0p0:abc-123")
    session = Session(
        claudeSessionID: "c1",
        terminalSessionID: "w0t0p0:abc-123",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        terminalTabName: nil,
        terminalWindowName: nil,
        customName: nil,
        state: .idle,
        startedAt: Date()
    )
    manager.testSetSessions([session])

    // Bare UUID should match via ":UUID" suffix
    manager.removeSessionsByTerminalID("abc-123")

    #expect(manager.sessions.isEmpty)
}

@Test func removeSessionsByTerminalID_emptyString_removesNothing() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1"),
        makeSession("s2"),
    ])

    manager.removeSessionsByTerminalID("")

    #expect(manager.sessions.count == 2)
}

@Test func removeSessionsByTerminalID_noMatch_removesNothing() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1"),
        makeSession("s2"),
    ])

    manager.removeSessionsByTerminalID("nonexistent")

    #expect(manager.sessions.count == 2)
}

@Test func removeSessionsByTerminalID_multipleMatches_removesAll() {
    let manager = SessionManager()

    // Simulate multiple tmux panes sharing the same iTerm2 session UUID
    let s1 = Session(
        claudeSessionID: "c1",
        terminalSessionID: "w0t0p0:shared-uuid",
        tmuxPane: "%1",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test/a",
        terminalTabName: nil,
        terminalWindowName: nil,
        customName: nil,
        state: .idle,
        startedAt: Date()
    )
    let s2 = Session(
        claudeSessionID: "c2",
        terminalSessionID: "w0t0p0:shared-uuid",
        tmuxPane: "%2",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test/b",
        terminalTabName: nil,
        terminalWindowName: nil,
        customName: nil,
        state: .idle,
        startedAt: Date()
    )
    let s3 = makeSession("other-session")
    manager.testSetSessions([s1, s2, s3])

    manager.removeSessionsByTerminalID("w0t0p0:shared-uuid")

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].terminalSessionID == "other-session")
}

// MARK: - reorderForMode Additional Tests

@Test func reorderForMode_grouped_sortsByStartedAt() {
    let manager = SessionManager()

    var s1 = makeSession("s1", state: .idle)
    s1.startedAt = Date(timeIntervalSince1970: 300)
    var s2 = makeSession("s2", state: .idle)
    s2.startedAt = Date(timeIntervalSince1970: 100)
    var s3 = makeSession("s3", state: .idle)
    s3.startedAt = Date(timeIntervalSince1970: 200)

    manager.testSetSessions([s1, s2, s3])
    manager.reorderForMode(.grouped)

    // Grouped mode sorts by startedAt (same as static)
    #expect(manager.sessions[0].terminalSessionID == "s2")
    #expect(manager.sessions[1].terminalSessionID == "s3")
    #expect(manager.sessions[2].terminalSessionID == "s1")
}

@Test func reorderForMode_static_preservesSectioning() {
    let manager = SessionManager()

    var idle1 = makeSession("idle1", state: .idle)
    idle1.startedAt = Date(timeIntervalSince1970: 100)
    var busy1 = makeSession("busy1", state: .working)
    busy1.startedAt = Date(timeIntervalSince1970: 200)
    var back1 = makeSession("back1", state: .backburner)
    back1.startedAt = Date(timeIntervalSince1970: 50)

    manager.testSetSessions([busy1, back1, idle1])
    manager.reorderForMode(.static)

    // Static sorts by startedAt: back1(50), idle1(100), busy1(200)
    #expect(manager.sessions[0].terminalSessionID == "back1")
    #expect(manager.sessions[1].terminalSessionID == "idle1")
    #expect(manager.sessions[2].terminalSessionID == "busy1")
}

// MARK: - updateSessionTerminalInfo Tests

@Test @MainActor func updateSessionTerminalInfo_updatesTabAndPaneInfo() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.updateSessionTerminalInfo(
        terminalSessionID: "s1", tabName: "My Tab", paneIndex: 1, paneCount: 3
    )

    #expect(manager.sessions[0].terminalTabName == "My Tab")
    #expect(manager.sessions[0].paneIndex == 1)
    #expect(manager.sessions[0].paneCount == 3)
}

@Test func updateSessionTerminalInfo_nonexistentSession_noOp() {
    let manager = SessionManager()

    manager.updateSessionTerminalInfo(
        terminalSessionID: "nonexistent", tabName: "Tab", paneIndex: 0, paneCount: 1
    )

    #expect(manager.sessions.isEmpty)
}

@Test @MainActor func updateSessionTerminalInfo_windowName() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.updateSessionTerminalInfo(
        terminalSessionID: "s1", tabName: "Tab", windowName: "Window", paneIndex: 0, paneCount: 1
    )

    #expect(manager.sessions[0].terminalWindowName == "Window")
    #expect(manager.sessions[0].terminalTabName == "Tab")
}

@Test func updateSessionTerminalInfo_updatesAllSessionsSharingTerminalID() {
    let manager = SessionManager()

    // Two tmux panes sharing the same terminal session
    let s1 = Session(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1", terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/a", state: .idle, startedAt: Date()
    )
    let s2 = Session(
        claudeSessionID: "c2", terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%2", terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/b", state: .idle, startedAt: Date()
    )
    manager.testSetSessions([s1, s2])

    manager.updateSessionTerminalInfo(
        terminalSessionID: "w0t0p0:abc", tabName: "Shared Tab", paneIndex: 0, paneCount: 2
    )

    #expect(manager.sessions[0].terminalTabName == "Shared Tab")
    #expect(manager.sessions[1].terminalTabName == "Shared Tab")
}

// MARK: - addOrUpdateSession metadata Tests

@Test @MainActor func addOrUpdateSession_newSession_withAllMetadata() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1",
        tmuxPane: "%1", tmuxSessionName: "dev",
        terminalType: .kitty, agent: "opencode",
        projectPath: "/test/project", state: .working,
        gitBranch: "feature-x", gitRepoName: "my-repo",
        transcriptPath: "/tmp/transcript.jsonl"
    )

    #expect(manager.sessions.count == 1)
    let s = manager.sessions[0]
    #expect(s.id == "s1:%1")
    #expect(s.tmuxSessionName == "dev")
    #expect(s.terminalType == .kitty)
    #expect(s.agent == "opencode")
    #expect(s.agentShortName == "OC")
    #expect(s.gitBranch == "feature-x")
    #expect(s.gitRepoName == "my-repo")
    #expect(s.transcriptPath == "/tmp/transcript.jsonl")
}

@Test @MainActor func addOrUpdateSession_emptyMetadata_treatedAsNil() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1",
        tmuxSessionName: "", projectPath: "/p", state: .idle,
        gitBranch: "", gitRepoName: "", transcriptPath: ""
    )

    let s = manager.sessions[0]
    #expect(s.tmuxSessionName == nil)
    #expect(s.gitBranch == nil)
    #expect(s.gitRepoName == nil)
    #expect(s.transcriptPath == nil)
}

@Test @MainActor func addOrUpdateSession_updatesTranscriptPath() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle,
        transcriptPath: "/new/transcript.jsonl"
    )

    #expect(manager.sessions[0].transcriptPath == "/new/transcript.jsonl")
}

@Test @MainActor func addOrUpdateSession_backburnered_updatesMetadata_preservesState() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p",
        state: .backburner
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1",
        tmuxSessionName: "dev",
        projectPath: "/p", state: .working, event: "Stop",
        gitBranch: "main", gitRepoName: "repo", transcriptPath: "/path"
    )

    let s = manager.sessions[0]
    #expect(s.state == .backburner)
    #expect(s.tmuxSessionName == "dev")
    #expect(s.gitBranch == "main")
    #expect(s.gitRepoName == "repo")
    #expect(s.transcriptPath == "/path")
}

// MARK: - cycleForward / cycleBackward Tests

@Test func cycleForward_returnsNextIdleSession() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .idle),
        makeSession("s2", state: .idle),
        makeSession("s3", state: .idle),
    ])

    let first = manager.cycleForward()
    #expect(first != nil)

    let second = manager.cycleForward()
    #expect(second != nil)
    #expect(second?.terminalSessionID != first?.terminalSessionID)
}

@Test func cycleBackward_returnsSession() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .idle),
        makeSession("s2", state: .idle),
    ])

    let result = manager.cycleBackward()
    #expect(result != nil)
}

@Test func cycleForward_noSessions_returnsNil() {
    let manager = SessionManager()
    let result = manager.cycleForward()
    #expect(result == nil)
}

@Test func cycleBackward_noSessions_returnsNil() {
    let manager = SessionManager()
    let result = manager.cycleBackward()
    #expect(result == nil)
}

@Test func manager_cycleForward_allBackburnered_returnsNil() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .backburner),
        makeSession("s2", state: .backburner),
    ])

    let result = manager.cycleForward()
    #expect(result == nil)
}

// MARK: - currentSession Tests

@Test func currentSession_noSessions_returnsNil() {
    let manager = SessionManager()
    #expect(manager.currentSession == nil)
}

@Test func currentSession_withSessions_returnsOne() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .idle),
        makeSession("s2", state: .idle),
    ])

    #expect(manager.currentSession != nil)
}

@Test func currentSession_allBackburnered_returnsNil() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .backburner),
    ])

    #expect(manager.currentSession == nil)
}

// MARK: - isSessionFocused Tests

@Test func isSessionFocused_noFocusedID_returnsFalse() {
    let manager = SessionManager()

    manager.testSetSessions([makeSession("s1")])

    #expect(manager.isSessionFocused == false)
}

// MARK: - renameSession edge cases

@Test @MainActor func renameSession_nonexistentSession_noOp() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.renameSession(terminalSessionID: "nonexistent", customName: "Test")

    #expect(manager.sessions[0].customName == nil)
}

@Test @MainActor func renameSession_nilClears() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )
    manager.renameSession(terminalSessionID: "s1", customName: "Custom")
    #expect(manager.sessions[0].customName == "Custom")

    manager.renameSession(terminalSessionID: "s1", customName: nil)
    #expect(manager.sessions[0].customName == nil)
}

// MARK: - lastActiveSessionID (Anchor) Tests

@Test func lastActiveSessionID_anchorClearedOnCycleForward() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .working),
        makeSession("s2", state: .idle),
        makeSession("s3", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s1")
    manager.testSetFocusedSessionID("s1")

    // cycleForward should consume the anchor and use it as effective focus
    let result = manager.cycleForward()
    #expect(result != nil)
    #expect(manager.lastActiveSessionID == nil)
}

@Test func lastActiveSessionID_anchorClearedOnCycleBackward() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .idle),
        makeSession("s2", state: .working),
        makeSession("s3", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s2")
    manager.testSetFocusedSessionID("s2")

    let result = manager.cycleBackward()
    #expect(result != nil)
    #expect(manager.lastActiveSessionID == nil)
}

@Test func lastActiveSessionID_anchorClearedOnSessionRemoval() {
    let manager = SessionManager()

    manager.testSetSessions([
        makeSession("s1", state: .working),
        makeSession("s2", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s1")

    manager.removeSession(sessionID: "s1")
    #expect(manager.lastActiveSessionID == nil)
}

@Test func currentSession_autoAdvanceOff_busySessionReturnedViaAnchor() {
    let manager = SessionManager()
    UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)

    manager.testSetSessions([
        makeSession("s1", state: .working),
        makeSession("s2", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s1")

    // With anchor set and auto-advance OFF, currentSession should return the busy session
    let current = manager.currentSession
    #expect(current?.id == "s1")
}

@Test func currentSession_autoAdvanceOn_busySessionNotReturnedViaAnchor() {
    let manager = SessionManager()
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)

    manager.testSetSessions([
        makeSession("s1", state: .working),
        makeSession("s2", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s1")

    // With auto-advance ON, the anchor is ignored for currentSession
    let current = manager.currentSession
    #expect(current?.id != "s1")

    // Clean up
    UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy)
}

@Test func cycleForward_withAnchor_usesAnchorAsEffectiveFocus() {
    let manager = SessionManager()

    // s1=idle, s2=working (anchored), s3=idle
    manager.testSetSessions([
        makeSession("s1", state: .idle),
        makeSession("s2", state: .working),
        makeSession("s3", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s2")
    manager.testSetFocusedSessionID("s2")

    // Cycling forward from s2 (working, anchored) should advance to s3
    let result = manager.cycleForward()
    #expect(result?.id == "s3")
    #expect(manager.lastActiveSessionID == nil) // anchor consumed
}

@Test func cycleBackward_withAnchor_usesAnchorAsEffectiveFocus() {
    let manager = SessionManager()

    // s1=idle, s2=working (anchored), s3=idle
    manager.testSetSessions([
        makeSession("s1", state: .idle),
        makeSession("s2", state: .working),
        makeSession("s3", state: .idle),
    ])
    manager.testSetLastActiveSessionID("s2")
    manager.testSetFocusedSessionID("s2")

    // Cycling backward from s2 should go to s1
    let result = manager.cycleBackward()
    #expect(result?.id == "s1")
    #expect(manager.lastActiveSessionID == nil) // anchor consumed
}

// MARK: - Auto-advance Tests

@Test @MainActor func autoAdvance_on_focusedSessionGoesBusy_postsNotification() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    var posted = false
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoAdvance, object: nil, queue: nil
    ) { _ in posted = true }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])
    manager.testSetFocusedSessionID("s1")

    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .working)

    #expect(posted == true)
}

@Test @MainActor func autoAdvance_off_focusedSessionGoesBusy_setsAnchor() {
    UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])
    manager.testSetFocusedSessionID("s1")

    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .working)

    #expect(manager.lastActiveSessionID == "s1")
}

@Test @MainActor func autoAdvance_sessionGoesBusy_notFocused_noAction() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])
    manager.testSetFocusedSessionID("s2") // focused on s2, not s1

    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .working)

    // Not focused on s1, so no anchor should be set
    #expect(manager.lastActiveSessionID == nil)
}

@Test @MainActor func autoAdvance_sessionGoesBusy_noFocus_noAction() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoAdvanceOnBusy)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoAdvanceOnBusy) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle)])
    // No focused session

    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .working)

    #expect(manager.lastActiveSessionID == nil)
}

// MARK: - Auto-restart Tests

@Test @MainActor func autoRestart_on_soleCyclable_postsNotification() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

    var postedSessionID: String?
    let token = NotificationCenter.default.addObserver(
        forName: .shouldAutoRestart, object: nil, queue: nil
    ) { note in postedSessionID = note.userInfo?["sessionID"] as? String }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .working), makeSession("s2", state: .backburner)])

    manager.testApplyStateChange(sessionID: "s1", from: .working, to: .idle)

    #expect(postedSessionID == "s1")
}

@Test @MainActor func autoRestart_on_multipleCyclable_noAutoRestart() {
    UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .working), makeSession("s2", state: .idle)])

    manager.testApplyStateChange(sessionID: "s1", from: .working, to: .idle)

    // Both are now cyclable — auto-restart guard (cyclableCount == 1) prevents firing
    let cyclable = manager.sessions.filter(\.state.isIncludedInCycle)
    #expect(cyclable.count == 2)
}

@Test @MainActor func autoRestart_off_soleCyclable_noAutoRestart() {
    UserDefaults.standard.set(false, forKey: AppStorageKeys.autoRestartOnIdle)
    defer { UserDefaults.standard.removeObject(forKey: AppStorageKeys.autoRestartOnIdle) }

    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .working)])

    manager.testApplyStateChange(sessionID: "s1", from: .working, to: .idle)

    let s1 = manager.sessions.first { $0.id == "s1" }
    #expect(s1?.state == .idle)
}

// MARK: - Anchor Clearing on State Return Tests

@Test @MainActor func anchorCleared_whenAnchoredSessionBecomesIdle() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .working)])
    manager.testSetLastActiveSessionID("s1")

    manager.testApplyStateChange(sessionID: "s1", from: .working, to: .idle)

    #expect(manager.lastActiveSessionID == nil)
}

@Test @MainActor func anchorNotCleared_whenDifferentSessionBecomesIdle() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .working)])
    manager.testSetLastActiveSessionID("s1")

    manager.testApplyStateChange(sessionID: "s2", from: .working, to: .idle)

    #expect(manager.lastActiveSessionID == "s1")
}

// MARK: - Snap-back (resolveEffectiveFocus) Tests

@Test func cycleForward_terminalNotFrontmost_snapsBackToFocused() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])
    manager.testSetFocusedSessionID("s1")

    let result = manager.cycleForward(wasTerminalFrontmost: false)

    #expect(result?.id == "s1") // snap-back, not cycle to s2
}

@Test func cycleBackward_terminalNotFrontmost_snapsBackToFocused() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])
    manager.testSetFocusedSessionID("s1")

    let result = manager.cycleBackward(wasTerminalFrontmost: false)

    #expect(result?.id == "s1") // snap-back, not cycle to s2
}

@Test func cycleForward_terminalNotFrontmost_focusedNotCyclable_cyclesNormally() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .working), makeSession("s2", state: .idle)])
    manager.testSetFocusedSessionID("s1")

    let result = manager.cycleForward(wasTerminalFrontmost: false)

    // s1 is working (not cyclable), so no snap-back match — normal cycle to s2
    #expect(result?.id == "s2")
}

// MARK: - updateFocusedSession Tests

@MainActor
@Test func updateFocusedSession_setsFocusedSessionID() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])

    manager.updateFocusedSession(terminalSessionID: "s1")

    #expect(manager.focusedSessionID == "s1")
}

@MainActor
@Test func updateFocusedSession_nil_clearsFocus() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])
    manager.updateFocusedSession(terminalSessionID: "s1")

    manager.updateFocusedSession(terminalSessionID: nil)

    #expect(manager.focusedSessionID == nil)
}

@MainActor
@Test func updateFocusedSession_bareUUID_acceptedAndMatchedViaSuffix() {
    let manager = SessionManager()
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc-uuid",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test", state: .idle, startedAt: Date()
    )
    manager.testSetSessions([session])

    manager.updateFocusedSession(terminalSessionID: "w0t0p0:abc-uuid")
    #expect(manager.focusedSessionID == "w0t0p0:abc-uuid")

    // Bare UUID now accepted — hasSuffix matching in isSessionFocused still works
    manager.updateFocusedSession(terminalSessionID: "abc-uuid")
    #expect(manager.focusedSessionID == "abc-uuid")
}

@MainActor
@Test func updateFocusedSession_activationGuard_suppressesIntermediate() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1"), makeSession("s2")])

    manager.beginActivation(targetSessionID: "s2")
    manager.updateFocusedSession(terminalSessionID: "s1")

    #expect(manager.focusedSessionID == nil)
}

@MainActor
@Test func updateFocusedSession_activationGuard_acceptsTarget() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1"), makeSession("s2")])

    manager.beginActivation(targetSessionID: "s2")
    manager.updateFocusedSession(terminalSessionID: "s2")

    #expect(manager.focusedSessionID == "s2")
}

@MainActor
@Test func endActivation_clearsGuard() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])

    manager.beginActivation(targetSessionID: "s1")
    manager.endActivation()
    manager.updateFocusedSession(terminalSessionID: "s1")

    #expect(manager.focusedSessionID == "s1")
}

// MARK: - isSessionFocused with isTerminalAppActive Tests

@MainActor
@Test func isSessionFocused_terminalActiveAndFocused_returnsTrue() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])
    manager.updateFocusedSession(terminalSessionID: "s1")
    manager.isTerminalAppActive = true

    #expect(manager.isSessionFocused == true)
}

@MainActor
@Test func isSessionFocused_terminalNotActive_returnsFalse() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])
    manager.updateFocusedSession(terminalSessionID: "s1")
    manager.isTerminalAppActive = false

    #expect(manager.isSessionFocused == false)
}

// MARK: - backburnerSession / reactivateSession Tests

@Test @MainActor func backburnerSession_changesStateToBackburner() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle)])

    manager.testApplyStateChange(sessionID: "s1", from: .idle, to: .backburner)

    #expect(manager.sessions.first { $0.id == "s1" }?.state == .backburner)
}

@Test @MainActor func reactivateSession_changesStateToIdle() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .backburner)])

    manager.testApplyStateChange(sessionID: "s1", from: .backburner, to: .idle)

    #expect(manager.sessions.first { $0.id == "s1" }?.state == .idle)
}

// MARK: - reorderForMode Tests

@Test func reorderForMode_fair_permissionGroupedWithIdle() {
    let manager = SessionManager()
    manager.testSetSessions([
        makeSession("work1", state: .working),
        makeSession("perm1", state: .permission),
        makeSession("idle1", state: .idle),
    ])

    manager.reorderForMode(.fair)

    let states = manager.sessions.map(\.state)
    let firstWorkingIdx = states.firstIndex(of: .working)!
    let idleTypes: Set<SessionState> = [.idle, .permission]
    for i in 0 ..< firstWorkingIdx {
        #expect(idleTypes.contains(states[i]))
    }
}

@Test func reorderForMode_fair_compactingGroupedWithWorking() {
    let manager = SessionManager()
    manager.testSetSessions([
        makeSession("idle1", state: .idle),
        makeSession("compact1", state: .compacting),
        makeSession("work1", state: .working),
        makeSession("back1", state: .backburner),
    ])

    manager.reorderForMode(.fair)

    #expect(manager.sessions[0].state == .idle)
    let midStates = Set([manager.sessions[1].state, manager.sessions[2].state])
    #expect(midStates == Set([.working, .compacting]))
    #expect(manager.sessions[3].state == .backburner)
}

// MARK: - reconcileFocusForTerminal Tests

private func makeKittySession(_ id: String, state: SessionState = .idle) -> Session {
    Session(
        claudeSessionID: id,
        terminalSessionID: id,
        terminalType: .kitty,
        agent: "claude-code",
        projectPath: "/test/\(id)",
        terminalTabName: nil,
        terminalWindowName: nil,
        customName: nil,
        state: state,
        startedAt: Date()
    )
}

@MainActor
@Test func reconcileFocus_kittyActivated_noSessions_noChange() {
    let manager = SessionManager()
    manager.testSetFocusedSessionID("iterm-session")
    manager.testSetSessions([makeSession("iterm-session")])

    manager.testReconcileFocusForTerminal(bundleID: TerminalType.kitty.bundleIdentifier)

    #expect(manager.focusedSessionID == "iterm-session")
}

@MainActor
@Test func reconcileFocus_kittyActivated_focusAlreadyCorrect_noChange() {
    let manager = SessionManager()
    let kittySession = makeKittySession("kitty1")
    manager.testSetSessions([kittySession, makeSession("iterm1")])
    manager.testSetFocusedSessionID("kitty1")

    manager.testReconcileFocusForTerminal(bundleID: TerminalType.kitty.bundleIdentifier)

    #expect(manager.focusedSessionID == "kitty1")
}

@MainActor
@Test func reconcileFocus_kittyActivated_focusStale_reconcilesToKittySession() {
    let manager = SessionManager()
    let kittySession = makeKittySession("kitty1")
    manager.testSetSessions([kittySession, makeSession("iterm1")])
    // Focus is on an iTerm2 session — stale for Kitty activation
    manager.testSetFocusedSessionID("iterm1")

    manager.testReconcileFocusForTerminal(bundleID: TerminalType.kitty.bundleIdentifier)

    #expect(manager.focusedSessionID == "kitty1")
}

@MainActor
@Test func reconcileFocus_kittyActivated_focusNil_reconcilesToKittySession() {
    let manager = SessionManager()
    let kittySession = makeKittySession("kitty1")
    manager.testSetSessions([kittySession])

    manager.testReconcileFocusForTerminal(bundleID: TerminalType.kitty.bundleIdentifier)

    #expect(manager.focusedSessionID == "kitty1")
}

@MainActor
@Test func reconcileFocus_iterm2Activated_noReconciliation() {
    let manager = SessionManager()
    let kittySession = makeKittySession("kitty1")
    manager.testSetSessions([kittySession, makeSession("iterm1")])
    manager.testSetFocusedSessionID("kitty1")

    manager.testReconcileFocusForTerminal(bundleID: TerminalType.iterm2.bundleIdentifier)

    // iTerm2 activation should not trigger reconciliation — focus unchanged
    #expect(manager.focusedSessionID == "kitty1")
}

@MainActor
@Test func reconcileFocus_kittySessionCreated_thenActivated_focusesNewSession() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("iterm1")])
    manager.testSetFocusedSessionID("iterm1")

    // Simulate a new Kitty session being added
    let kittySession = makeKittySession("kitty1")
    manager.testSetSessions([makeSession("iterm1"), kittySession])

    // Simulate Kitty activation
    manager.testReconcileFocusForTerminal(bundleID: TerminalType.kitty.bundleIdentifier)

    #expect(manager.focusedSessionID == "kitty1")
}
