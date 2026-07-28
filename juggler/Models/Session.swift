import Foundation

struct Session: Identifiable, Codable, Equatable {
    var claudeSessionID: String // May be shared across split panes
    let terminalSessionID: String // e.g., "w0t0p0:UUID"
    var tmuxPane: String? // e.g., "%1", nil if not inside tmux

    var id: String {
        if let pane = tmuxPane {
            return "\(terminalSessionID):\(pane)"
        }
        return terminalSessionID
    }

    let terminalType: TerminalType
    let agent: String
    let projectPath: String
    var terminalTabName: String?
    var terminalWindowName: String?
    var tmuxSessionName: String?
    var customName: String?
    var state: SessionState
    var startedAt: Date
    var lastBecameIdle: Date?
    var lastBecameWorking: Date?
    var busyTimeToday: TimeInterval = 0
    var paneIndex: Int = 0
    var paneCount: Int = 1

    var gitBranch: String?
    var gitRepoName: String?
    var transcriptPath: String?
    var remoteHost: String?

    // Bare UUID of the live local iTerm2 pane, learned from focus events. Set only for
    // remote tmux sessions, whose captured `terminalSessionID` is stale (tmux caches
    // `ITERM_SESSION_ID`). Takes precedence over `terminalSessionID` when set.
    var liveHostPaneID: String?

    // Antigravity has no `UserPromptSubmit`, so a backburnered session is auto-reactivated
    // on its next `working` event only if it was shelved while awaiting the user.
    var wasAwaitingUserBeforeBackburner = false

    var agentShortName: String {
        switch agent {
        case "opencode": "OC"
        case "codex": "CX"
        case "pi": "PI"
        case "antigravity": "AG"
        default: "CC"
        }
    }

    var displayName: String {
        if tmuxPane != nil {
            return customName ?? tmuxSessionName ?? projectFolderName
        }
        return customName ?? terminalTabName ?? projectFolderName
    }

    var projectFolderName: String {
        String(projectPath.split(separator: "/").last ?? "Unknown")
    }

    var parentAndFolderName: String {
        let components = projectPath.split(separator: "/")
        if components.count >= 2 {
            return "\(components[components.count - 2])/\(components[components.count - 1])"
        }
        return projectFolderName
    }

    func title(for mode: SessionTitleMode) -> String {
        if let customName { return customName }
        switch mode {
        case .tabTitle:
            if tmuxPane != nil { return tmuxSessionName ?? projectFolderName }
            return terminalTabName ?? projectFolderName
        case .windowTitle:
            return terminalWindowName ?? projectFolderName
        case .windowAndTabTitle:
            if let window = terminalWindowName, let tab = terminalTabName {
                return "\(window)/\(tab)"
            }
            return terminalWindowName ?? terminalTabName ?? projectFolderName
        case .folderName:
            return projectFolderName
        case .parentAndFolderName:
            return parentAndFolderName
        }
    }

    enum CodingKeys: String, CodingKey {
        case claudeSessionID, terminalSessionID, tmuxPane, terminalType, agent, projectPath
        case terminalTabName, terminalWindowName, tmuxSessionName, customName, state, startedAt
        case lastBecameIdle, lastBecameWorking, busyTimeToday
        case paneIndex, paneCount, gitBranch, gitRepoName, transcriptPath, remoteHost
    }

    // Excludes the volatile timing fields so .onChange(of: sessions) doesn't fire on
    // every hook event.
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.claudeSessionID == rhs.claudeSessionID &&
            lhs.terminalSessionID == rhs.terminalSessionID &&
            lhs.tmuxPane == rhs.tmuxPane &&
            lhs.terminalType == rhs.terminalType &&
            lhs.agent == rhs.agent &&
            lhs.projectPath == rhs.projectPath &&
            lhs.terminalTabName == rhs.terminalTabName &&
            lhs.terminalWindowName == rhs.terminalWindowName &&
            lhs.tmuxSessionName == rhs.tmuxSessionName &&
            lhs.customName == rhs.customName &&
            lhs.state == rhs.state &&
            lhs.startedAt == rhs.startedAt &&
            lhs.paneIndex == rhs.paneIndex &&
            lhs.paneCount == rhs.paneCount &&
            lhs.gitBranch == rhs.gitBranch &&
            lhs.gitRepoName == rhs.gitRepoName &&
            lhs.transcriptPath == rhs.transcriptPath &&
            lhs.remoteHost == rhs.remoteHost
    }

    var fullDisplayName: String {
        if paneCount > 1 {
            return "\(displayName) (\(paneIndex + 1)/\(paneCount))"
        }
        return displayName
    }

    var currentWorkingDuration: TimeInterval? {
        guard state == .working || state == .compacting,
              let lastBecameWorking else { return nil }
        return Date().timeIntervalSince(lastBecameWorking)
    }

    var busyTimeTodayLive: TimeInterval {
        busyTimeToday + (currentWorkingDuration ?? 0)
    }
}
