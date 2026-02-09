import Foundation

struct Session: Identifiable, Codable, Equatable {
    let claudeSessionID: String // Claude session ID (may be shared across split panes)
    let terminalSessionID: String // e.g., "w0t0p0:UUID"
    var tmuxPane: String? // e.g., "%1", nil if not inside tmux

    // Composite ID: unique per terminal pane, including tmux panes
    var id: String {
        if let pane = tmuxPane {
            return "\(terminalSessionID):\(pane)"
        }
        return terminalSessionID
    }

    let terminalType: TerminalType
    let projectPath: String
    var terminalTabName: String?
    var terminalWindowName: String?
    var tmuxSessionName: String?
    var customName: String?
    var state: SessionState
    var lastUpdated: Date
    var startedAt: Date
    var lastBecameIdle: Date?
    var accumulatedIdleTime: TimeInterval = 0
    var lastBecameWorking: Date?
    var accumulatedWorkingTime: TimeInterval = 0
    var paneIndex: Int = 0
    var paneCount: Int = 1

    // Git info
    var gitBranch: String?
    var gitRepoName: String?

    // Claude transcript
    var transcriptPath: String?

    var displayName: String {
        if tmuxPane != nil {
            return customName ?? tmuxSessionName ?? projectFolderName
        }
        return customName ?? terminalTabName ?? projectFolderName
    }

    var projectFolderName: String {
        String(projectPath.split(separator: "/").last ?? "Unknown")
    }

    // Explicit CodingKeys to exclude computed 'id' property
    enum CodingKeys: String, CodingKey {
        case claudeSessionID, terminalSessionID, tmuxPane, terminalType, projectPath
        case terminalTabName, terminalWindowName, tmuxSessionName, customName, state, lastUpdated, startedAt
        case lastBecameIdle, accumulatedIdleTime, lastBecameWorking, accumulatedWorkingTime
        case paneIndex, paneCount, gitBranch, gitRepoName, transcriptPath
    }

    // Explicit Equatable: excludes computed 'id' and volatile timing fields
    // (lastUpdated, lastBecameIdle, accumulatedIdleTime, lastBecameWorking, accumulatedWorkingTime)
    // to prevent .onChange(of: sessions) from firing on every hook event heartbeat.
    // Timing fields are display-only and refreshed by TimelineView on a 5-second cadence.
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.claudeSessionID == rhs.claudeSessionID &&
            lhs.terminalSessionID == rhs.terminalSessionID &&
            lhs.tmuxPane == rhs.tmuxPane &&
            lhs.terminalType == rhs.terminalType &&
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
            lhs.transcriptPath == rhs.transcriptPath
    }

    // Full display name including window/tab context
    var fullDisplayName: String {
        if paneCount > 1 {
            return "\(displayName) (\(paneIndex + 1)/\(paneCount))"
        }
        return displayName
    }

    var currentIdleDuration: TimeInterval? {
        guard state == .idle || state == .permission,
              let lastBecameIdle else { return nil }
        return Date().timeIntervalSince(lastBecameIdle)
    }

    var totalIdleTime: TimeInterval {
        accumulatedIdleTime + (currentIdleDuration ?? 0)
    }

    var currentWorkingDuration: TimeInterval? {
        guard state == .working || state == .compacting,
              let lastBecameWorking else { return nil }
        return Date().timeIntervalSince(lastBecameWorking)
    }

    var totalWorkingTime: TimeInterval {
        accumulatedWorkingTime + (currentWorkingDuration ?? 0)
    }
}
