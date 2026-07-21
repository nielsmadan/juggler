import Foundation

struct Session: Identifiable, Codable, Equatable {
    let claudeSessionID: String // May be shared across split panes
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

    /// Bare UUID of the local iTerm2 pane currently hosting this session, learned from
    /// live focus events. Set only for remote tmux sessions, whose remote-captured
    /// `terminalSessionID` is a stale value that no longer maps to a live local pane
    /// (tmux caches `ITERM_SESSION_ID` in its environment). When set, activation and
    /// focus-matching address this pane instead of `terminalSessionID`. Ephemeral —
    /// pane UUIDs don't survive an iTerm2 restart — so it is neither coded nor part of
    /// Equatable.
    var liveHostPaneID: String?

    var agentShortName: String {
        switch agent {
        case "opencode": "OC"
        case "codex": "CX"
        case "pi": "PI"
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

    // Explicit Equatable: excludes computed 'id', volatile timing fields
    // (lastBecameIdle, lastBecameWorking, busyTimeToday), and the ephemeral
    // 'liveHostPaneID' binding — to prevent .onChange(of: sessions) from firing on
    // every hook event heartbeat.
    // Timing fields are display-only and refreshed by TimelineView on a 5-second cadence.
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

    /// Busy time accrued today by this session, including the current turn.
    var busyTimeTodayLive: TimeInterval {
        busyTimeToday + (currentWorkingDuration ?? 0)
    }
}
