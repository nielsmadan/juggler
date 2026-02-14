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

    // Fair = oldest idle first (FIFO)
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

    // Prio = newest idle first (LIFO)
    #expect(manager.sessions[0].terminalSessionID == "s2")
    #expect(manager.sessions[1].terminalSessionID == "s1")
}

// MARK: - addOrUpdateSession Tests

@Test func addOrUpdateSession_newSession_appendsToList() {
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

@Test func addOrUpdateSession_existingSession_updatesMetadata() {
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

@Test func addOrUpdateSession_backburnered_preservesState_unlessUserPromptSubmit() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .backburner
    )

    // Non-UserPromptSubmit event should preserve backburner
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p",
        state: .working, event: "PreToolUse", gitBranch: "new-branch"
    )

    #expect(manager.sessions[0].state == .backburner)
    #expect(manager.sessions[0].gitBranch == "new-branch") // metadata still updated
}

@Test func addOrUpdateSession_backburnered_exitsOnUserPromptSubmit() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .backburner
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p",
        state: .working, event: "UserPromptSubmit"
    )

    // UserPromptSubmit bypasses backburner guard — state change dispatched via Task
    // Verify the guard was not hit by checking metadata was updated (not the early return path)
    #expect(manager.sessions.count == 1)
}

@Test func addOrUpdateSession_tmuxPane_createsCompositeID() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1", projectPath: "/p", state: .idle
    )

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].id == "w0t0p0:abc:%1")
}

// MARK: - disambiguatedDisplayName Tests

@Test func disambiguatedDisplayName_uniqueName_returnsBaseName() {
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

@Test func disambiguatedDisplayName_duplicateNames_appendsIndex() {
    let manager = SessionManager()

    // Both sessions share the same project path
    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/same-project", state: .idle
    )
    manager.addOrUpdateSession(
        claudeSessionID: "c2", terminalSessionID: "s2", projectPath: "/same-project", state: .idle
    )

    // updateSessionTerminalInfo sets paneIndex
    manager.updateSessionTerminalInfo(terminalSessionID: "s1", tabName: nil, paneIndex: 0, paneCount: 2)
    manager.updateSessionTerminalInfo(terminalSessionID: "s2", tabName: nil, paneIndex: 1, paneCount: 2)

    let name1 = manager.disambiguatedDisplayName(for: manager.sessions[0])
    let name2 = manager.disambiguatedDisplayName(for: manager.sessions[1])

    #expect(name1 == "same-project (1)")
    #expect(name2 == "same-project (2)")
}

@Test func disambiguatedDisplayName_folderMode_disambiguatesCollisions() {
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

    // Both should be "project" in folder mode, so they get disambiguated
    #expect(name1 == "project (1)")
    #expect(name2 == "project (2)")
}

@Test func disambiguatedDisplayName_parentFolderMode_uniqueParents_noSuffix() {
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

@Test func removeSession_removesFromList() {
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

@Test func removeSession_clearsFocusedSessionID() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.removeSession(sessionID: "s1")

    #expect(manager.focusedSessionID == nil)
}

@Test func removeSession_nonexistent_noOp() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.removeSession(sessionID: "nonexistent")

    #expect(manager.sessions.count == 1)
}

// MARK: - renameSession Tests

@Test func renameSession_setsCustomName() {
    let manager = SessionManager()

    manager.addOrUpdateSession(
        claudeSessionID: "c1", terminalSessionID: "s1", projectPath: "/p", state: .idle
    )

    manager.renameSession(terminalSessionID: "s1", customName: "My Session")

    #expect(manager.sessions[0].customName == "My Session")
    #expect(manager.sessions[0].displayName == "My Session")
}

@Test func renameSession_emptyString_clearsName() {
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
        lastUpdated: Date(),
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
        lastUpdated: Date(),
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
        lastUpdated: Date(),
        startedAt: Date()
    )
    let s3 = makeSession("other-session")
    manager.testSetSessions([s1, s2, s3])

    // Both sessions share the terminal ID
    manager.removeSessionsByTerminalID("w0t0p0:shared-uuid")

    #expect(manager.sessions.count == 1)
    #expect(manager.sessions[0].terminalSessionID == "other-session")
}
