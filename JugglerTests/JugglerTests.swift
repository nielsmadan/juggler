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

// MARK: - Session agentShortName Tests

@Test func agentShortName_claudeCode() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .idle,
        startedAt: Date()
    )
    #expect(session.agentShortName == "CC")
}

@Test func agentShortName_opencode() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "opencode",
        projectPath: "/test",
        state: .idle,
        startedAt: Date()
    )
    #expect(session.agentShortName == "OC")
}

// MARK: - Session displayName with tmux Tests

@Test func displayName_tmux_prefersTmuxSessionName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        terminalTabName: "tab-name",
        tmuxSessionName: "tmux-sess",
        state: .idle,
        startedAt: Date()
    )
    // tmux branch: customName ?? tmuxSessionName ?? projectFolderName
    #expect(session.displayName == "tmux-sess")
}

@Test func displayName_tmux_fallsBackToFolderName() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%1",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/path/project",
        state: .idle,
        startedAt: Date()
    )
    #expect(session.displayName == "project")
}

// MARK: - Session Working Duration Tests

@Test func currentWorkingDuration_nilWhenIdle() {
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .idle,
        startedAt: Date(),
        lastBecameWorking: Date()
    )
    #expect(session.currentWorkingDuration == nil)
}

@Test func currentWorkingDuration_calculatesWhenWorking() {
    let tenSecondsAgo = Date().addingTimeInterval(-10)
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .working,
        startedAt: Date(),
        lastBecameWorking: tenSecondsAgo
    )
    let duration = session.currentWorkingDuration!
    #expect(duration >= 9 && duration <= 12)
}

@Test func currentWorkingDuration_calculatesWhenCompacting() {
    let fiveSecondsAgo = Date().addingTimeInterval(-5)
    let session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .compacting,
        startedAt: Date(),
        lastBecameWorking: fiveSecondsAgo
    )
    let duration = session.currentWorkingDuration!
    #expect(duration >= 4 && duration <= 7)
}

@Test func totalWorkingTime_sumsAccumulatedAndCurrent() {
    var session = Session(
        claudeSessionID: "test",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test",
        state: .working,
        startedAt: Date(),
        lastBecameWorking: Date().addingTimeInterval(-10),
        accumulatedWorkingTime: 60
    )
    let total = session.totalWorkingTime
    #expect(total >= 69 && total <= 72)

    session.state = .idle
    #expect(session.totalWorkingTime == 60)
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

// MARK: - BeaconPosition Tests

@Test func beaconPosition_displayName() {
    #expect(BeaconPosition.center.displayName == "Center")
    #expect(BeaconPosition.topLeft.displayName == "Top Left")
    #expect(BeaconPosition.topRight.displayName == "Top Right")
    #expect(BeaconPosition.bottomLeft.displayName == "Bottom Left")
    #expect(BeaconPosition.bottomRight.displayName == "Bottom Right")
}

// MARK: - BeaconAnchor Tests

@Test func beaconAnchor_displayName() {
    #expect(BeaconAnchor.screen.displayName == "Screen")
    #expect(BeaconAnchor.activeWindow.displayName == "Active Window")
}

// MARK: - BeaconSize Tests

@Test func beaconSize_displayName() {
    #expect(BeaconSize.xs.displayName == "XS")
    #expect(BeaconSize.s.displayName == "S")
    #expect(BeaconSize.m.displayName == "M")
    #expect(BeaconSize.l.displayName == "L")
    #expect(BeaconSize.xl.displayName == "XL")
}

@Test func beaconSize_fontSize() {
    #expect(BeaconSize.xs.fontSize == 16)
    #expect(BeaconSize.s.fontSize == 22)
    #expect(BeaconSize.m.fontSize == 30)
    #expect(BeaconSize.l.fontSize == 40)
    #expect(BeaconSize.xl.fontSize == 52)
}

@Test func beaconSize_horizontalPadding() {
    #expect(BeaconSize.xs.horizontalPadding == 16)
    #expect(BeaconSize.s.horizontalPadding == 24)
    #expect(BeaconSize.m.horizontalPadding == 32)
    #expect(BeaconSize.l.horizontalPadding == 40)
    #expect(BeaconSize.xl.horizontalPadding == 48)
}

@Test func beaconSize_verticalPadding() {
    #expect(BeaconSize.xs.verticalPadding == 8)
    #expect(BeaconSize.s.verticalPadding == 12)
    #expect(BeaconSize.m.verticalPadding == 16)
    #expect(BeaconSize.l.verticalPadding == 20)
    #expect(BeaconSize.xl.verticalPadding == 24)
}

@Test func beaconSize_minWidth() {
    #expect(BeaconSize.xs.minWidth == 100)
    #expect(BeaconSize.s.minWidth == 150)
    #expect(BeaconSize.m.minWidth == 200)
    #expect(BeaconSize.l.minWidth == 260)
    #expect(BeaconSize.xl.minWidth == 320)
}

// MARK: - Session Equatable Tests

@Test func session_equatable_ignoresTimingFields() {
    let now = Date()
    var s1 = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
        agent: "claude-code", projectPath: "/test", state: .idle, startedAt: now
    )
    var s2 = s1

    // Timing fields should be ignored by ==
    s1.accumulatedIdleTime = 100
    s2.accumulatedIdleTime = 200
    s1.lastBecameIdle = Date(timeIntervalSince1970: 100)
    s2.lastBecameIdle = Date(timeIntervalSince1970: 200)
    s1.accumulatedWorkingTime = 50
    s2.accumulatedWorkingTime = 75
    s1.lastBecameWorking = Date(timeIntervalSince1970: 300)
    s2.lastBecameWorking = Date(timeIntervalSince1970: 400)

    #expect(s1 == s2)
}

@Test func session_equatable_detectsStateDifference() {
    let now = Date()
    let s1 = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
        agent: "claude-code", projectPath: "/test", state: .idle, startedAt: now
    )
    var s2 = s1
    s2.state = .working

    #expect(s1 != s2)
}

@Test func session_equatable_detectsGitBranchDifference() {
    let now = Date()
    var s1 = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
        agent: "claude-code", projectPath: "/test", state: .idle, startedAt: now
    )
    var s2 = s1
    s1.gitBranch = "main"
    s2.gitBranch = "feature"

    #expect(s1 != s2)
}

// MARK: - Session id Tests

@Test func session_id_withoutTmuxPane_usesTerminalSessionID() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test", state: .idle, startedAt: Date()
    )
    #expect(session.id == "w0t0p0:abc")
}

@Test func session_id_withTmuxPane_appendsPane() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc",
        tmuxPane: "%3", terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test", state: .idle, startedAt: Date()
    )
    #expect(session.id == "w0t0p0:abc:%3")
}

// MARK: - SessionState Codable Tests

@Test func sessionState_codableRoundtrip() throws {
    for state in [SessionState.idle, .working, .permission, .backburner, .compacting] {
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        #expect(decoded == state)
    }
}

// MARK: - TerminalType Codable Tests

@Test func terminalType_codableRoundtrip() throws {
    for type in TerminalType.allCases {
        let data = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(TerminalType.self, from: data)
        #expect(decoded == type)
    }
}

// MARK: - Session displayName priority Tests

@Test func displayName_nonTmux_prefersCustomOverTab() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
        agent: "claude-code", projectPath: "/path/project",
        terminalTabName: "tab", customName: "custom",
        state: .idle, startedAt: Date()
    )
    #expect(session.displayName == "custom")
}

@Test func displayName_nonTmux_prefersTabOverFolder() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
        agent: "claude-code", projectPath: "/path/project",
        terminalTabName: "my-tab",
        state: .idle, startedAt: Date()
    )
    #expect(session.displayName == "my-tab")
}

@Test func displayName_nonTmux_fallsBackToFolderName() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
        agent: "claude-code", projectPath: "/path/project",
        state: .idle, startedAt: Date()
    )
    #expect(session.displayName == "project")
}

// MARK: - HighlightConfig Tests

@Test func highlightConfig_codableRoundtrip() throws {
    let config = HighlightConfig(enabled: true, color: [255, 128, 0], duration: 2.5)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(HighlightConfig.self, from: data)

    #expect(decoded.enabled == true)
    #expect(decoded.color == [255, 128, 0])
    #expect(decoded.duration == 2.5)
}
