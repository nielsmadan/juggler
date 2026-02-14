//
//  JugglerTests.swift
//  JugglerTests
//
//  Created by Niels Madan on 22.01.26.
//

import Foundation
@testable import Juggler
import Testing

@Test func sessionDisplayNamePrefersCustomName() {
    var session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/Users/test/project",
        terminalTabName: "tab-name",
        customName: "my-custom-name",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )

    #expect(session.displayName == "my-custom-name")

    session.customName = nil
    #expect(session.displayName == "tab-name")

    session.terminalTabName = nil
    #expect(session.displayName == "project")
}

@Test func sessionFullDisplayNameShowsPaneInfo() {
    var session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/Users/test/project",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date(),
        paneIndex: 0,
        paneCount: 1
    )

    #expect(session.fullDisplayName == "project")

    session.paneCount = 2
    #expect(session.fullDisplayName == "project (1/2)")

    session.paneIndex = 1
    #expect(session.fullDisplayName == "project (2/2)")
}

@Test func sessionStateIcons() {
    #expect(SessionState.idle.iconName == "figure.wave")
    #expect(SessionState.permission.iconName == "figure.wave")
    #expect(SessionState.working.iconName == "figure.run")
    #expect(SessionState.backburner.iconName == "moon.zzz")
    #expect(SessionState.compacting.iconName == "arrow.3.trianglepath")
}

@Test func sessionStateIsIncludedInCycle() {
    #expect(SessionState.idle.isIncludedInCycle == true)
    #expect(SessionState.permission.isIncludedInCycle == true)
    #expect(SessionState.working.isIncludedInCycle == false)
    #expect(SessionState.backburner.isIncludedInCycle == false)
    #expect(SessionState.compacting.isIncludedInCycle == false)
}

// MARK: - Session projectFolderName Tests

@Test func projectFolderName_extractsLastPathComponent() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/Users/test/myproject",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.projectFolderName == "myproject")
}

@Test func projectFolderName_singleComponent() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/single",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.projectFolderName == "single")
}

@Test func projectFolderName_rootPath_returnsUnknown() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.projectFolderName == "Unknown")
}

@Test func projectFolderName_emptyPath_returnsUnknown() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.projectFolderName == "Unknown")
}

// MARK: - Session parentAndFolderName Tests

@Test func parentAndFolderName_extractsLastTwoComponents() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/a/b/c",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.parentAndFolderName == "b/c")
}

@Test func parentAndFolderName_deepPath() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/Users/test/projects/myproject",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.parentAndFolderName == "projects/myproject")
}

@Test func parentAndFolderName_singleComponent_fallsBackToFolderName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/single",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.parentAndFolderName == "single")
}

@Test func parentAndFolderName_emptyPath_returnsUnknown() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.parentAndFolderName == "Unknown")
}

// MARK: - Session title(for:) Tests

@Test func titleForMode_tabTitle_usesTerminalTabName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalTabName: "my-tab",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .tabTitle) == "my-tab")
}

@Test func titleForMode_tabTitle_fallsBackToFolderName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .tabTitle) == "project")
}

@Test func titleForMode_windowTitle_usesTerminalWindowName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalWindowName: "my-window",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .windowTitle) == "my-window")
}

@Test func titleForMode_windowTitle_fallsBackToFolderName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .windowTitle) == "project")
}

@Test func titleForMode_windowAndTabTitle_combinesBoth() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalTabName: "my-tab",
        terminalWindowName: "my-window",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .windowAndTabTitle) == "my-window/my-tab")
}

@Test func titleForMode_windowAndTabTitle_fallsBackToAvailable() {
    let sessionWindowOnly = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalWindowName: "my-window",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(sessionWindowOnly.title(for: .windowAndTabTitle) == "my-window")

    let sessionTabOnly = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalTabName: "my-tab",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(sessionTabOnly.title(for: .windowAndTabTitle) == "my-tab")

    let sessionNeither = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(sessionNeither.title(for: .windowAndTabTitle) == "project")
}

@Test func titleForMode_folderName_usesFolderName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalTabName: "my-tab",
        terminalWindowName: "my-window",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .folderName) == "project")
}

@Test func titleForMode_parentAndFolderName_usesParentAndFolder() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/a/b/c",
        terminalTabName: "my-tab",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .parentAndFolderName) == "b/c")
}

@Test func titleForMode_customName_overridesAllModes() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalTabName: "tab",
        terminalWindowName: "window",
        customName: "custom",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    for mode in SessionTitleMode.allCases {
        #expect(session.title(for: mode) == "custom")
    }
}

@Test func titleForMode_tabTitle_tmux_usesTmuxSessionName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        tmuxSessionName: "my-tmux",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .tabTitle) == "my-tmux")
}

@Test func titleForMode_tmux_folderMode_ignoresTmuxSessionName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        tmuxSessionName: "my-tmux",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .folderName) == "project")
}

@Test func titleForMode_tmux_windowMode_ignoresTmuxSessionName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalWindowName: "my-window",
        tmuxSessionName: "my-tmux",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.title(for: .windowTitle) == "my-window")
}

@Test func parentAndFolderName_rootPath_returnsUnknown() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date()
    )
    #expect(session.parentAndFolderName == "Unknown")
}

// MARK: - SessionTitleMode Tests

@Test func sessionTitleMode_displayName() {
    #expect(SessionTitleMode.tabTitle.displayName == "Tab Title")
    #expect(SessionTitleMode.windowTitle.displayName == "Window Title")
    #expect(SessionTitleMode.windowAndTabTitle.displayName == "Window / Tab Title")
    #expect(SessionTitleMode.folderName.displayName == "Folder Name")
    #expect(SessionTitleMode.parentAndFolderName.displayName == "Parent / Folder Name")
}

// MARK: - Session Idle Duration Tests

@Test func currentIdleDuration_nilWhenWorking() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .working,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: Date()
    )
    #expect(session.currentIdleDuration == nil)
}

@Test func currentIdleDuration_nilWhenBackburner() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .backburner,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: Date()
    )
    #expect(session.currentIdleDuration == nil)
}

@Test func currentIdleDuration_nilWhenCompacting() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .compacting,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: Date()
    )
    #expect(session.currentIdleDuration == nil)
}

@Test func currentIdleDuration_nilWhenNoLastBecameIdle() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: nil
    )
    #expect(session.currentIdleDuration == nil)
}

@Test func currentIdleDuration_calculatesWhenIdle() {
    let tenSecondsAgo = Date().addingTimeInterval(-10)
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: tenSecondsAgo
    )
    // Allow 1 second tolerance for test execution time
    let duration = session.currentIdleDuration!
    #expect(duration >= 9 && duration <= 12)
}

@Test func currentIdleDuration_calculatesWhenPermission() {
    let fiveSecondsAgo = Date().addingTimeInterval(-5)
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .permission,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: fiveSecondsAgo
    )
    let duration = session.currentIdleDuration!
    #expect(duration >= 4 && duration <= 7)
}

@Test func totalIdleTime_sumsAccumulatedAndCurrent() {
    let tenSecondsAgo = Date().addingTimeInterval(-10)
    var session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .idle,
        lastUpdated: Date(),
        startedAt: Date(),
        lastBecameIdle: tenSecondsAgo,
        accumulatedIdleTime: 60
    )
    // Total should be accumulated (60) + current (~10)
    let total = session.totalIdleTime
    #expect(total >= 69 && total <= 72)

    // When not idle, total is just accumulated
    session.state = .working
    #expect(session.totalIdleTime == 60)
}

// MARK: - Session Codable Tests

@Test func session_codableRoundtrip() throws {
    let original = Session(
        claudeSessionID: "claude-123",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/Users/test/project",
        terminalTabName: "my-tab",
        terminalWindowName: "my-window",
        customName: "custom",
        state: .idle,
        lastUpdated: Date(timeIntervalSince1970: 1000),
        startedAt: Date(timeIntervalSince1970: 900),
        lastBecameIdle: Date(timeIntervalSince1970: 950),
        accumulatedIdleTime: 30,
        paneIndex: 1,
        paneCount: 2,
        gitBranch: "main",
        gitRepoName: "juggler",
        transcriptPath: "/path/to/transcript"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Session.self, from: data)

    #expect(decoded == original)
}

// MARK: - SessionState displayText Tests

@Test func sessionState_displayText() {
    #expect(SessionState.idle.displayText == "idle")
    #expect(SessionState.working.displayText == "working")
    #expect(SessionState.permission.displayText == "permission")
    #expect(SessionState.backburner.displayText == "backburner")
    #expect(SessionState.compacting.displayText == "compacting")
}

// MARK: - TerminalType displayName Tests

@Test func terminalType_displayName() {
    #expect(TerminalType.iterm2.displayName == "iTerm2")
    #expect(TerminalType.kitty.displayName == "Kitty")
    #expect(TerminalType.ghostty.displayName == "Ghostty")
    #expect(TerminalType.wezterm.displayName == "WezTerm")
}

// MARK: - QueueOrderMode displayName Tests

@Test func queueOrderMode_displayName() {
    #expect(QueueOrderMode.fair.displayName == "Fair")
    #expect(QueueOrderMode.prio.displayName == "Prio")
    #expect(QueueOrderMode.static.displayName == "Static")
    #expect(QueueOrderMode.grouped.displayName == "Grouped")
}
