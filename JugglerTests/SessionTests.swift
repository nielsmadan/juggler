import Foundation
@testable import Juggler
import Testing

@Suite("Session")
struct SessionTests {
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
        let total = session.totalIdleTime
        #expect(total >= 69 && total <= 72)

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

    @Test func agentShortName_codex() {
        let session = Session(
            claudeSessionID: "test",
            terminalSessionID: "w0t0p0:abc",
            terminalType: .iterm2,
            agent: "codex",
            projectPath: "/test",
            state: .idle,
            startedAt: Date()
        )
        #expect(session.agentShortName == "CX")
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

    // MARK: - Session Equatable Tests

    @Test func session_equatable_ignoresTimingFields() {
        let now = Date()
        var s1 = Session(
            claudeSessionID: "c1", terminalSessionID: "s1", terminalType: .iterm2,
            agent: "claude-code", projectPath: "/test", state: .idle, startedAt: now
        )
        var s2 = s1

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
}
