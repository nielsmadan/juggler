import Foundation

struct SessionDetails: Equatable, Sendable {
    var agentTitle: String?
    var model: String?
    var effort: String?
    var permissionMode: String?
    var currentTool: String?
    var lastProblem: String?
    var subagentCount: Int = 0
    var contextPercent: Int?
    var turns: Int?
    var reportedTurns: Int?
    var processStartedAt: Date?
    var observedAt: Date?

    func replaced(by incoming: SessionDetails) -> SessionDetails {
        if let current = observedAt, let next = incoming.observedAt, next < current { return self }
        var result = incoming
        result.processStartedAt = incoming.processStartedAt ?? processStartedAt
        return result
    }
}

nonisolated struct BindingTurnObservation: Equatable, Sendable {
    let turns: Int?
    let observedAt: Date?

    func merging(_ incoming: Self) -> Self {
        if let currentTime = observedAt, let incomingTime = incoming.observedAt, currentTime != incomingTime {
            return currentTime > incomingTime ? self : incoming
        }
        let count = if let turns, let incomingTurns = incoming.turns { max(turns, incomingTurns) } else { nil as Int? }
        return Self(turns: count, observedAt: observedAt == incoming.observedAt ? observedAt : nil)
    }
}

nonisolated enum DetailsChange: Sendable {
    case replace(SessionDetails)
    case antigravity(event: String, model: String?, terminationReason: String?)

    @MainActor
    func applied(to details: SessionDetails) -> SessionDetails {
        switch self {
        case let .replace(incoming):
            details.replaced(by: incoming)
        case let .antigravity(event, model, terminationReason):
            HookEventMapper.antigravityDetails(
                details, event: event, model: model, terminationReason: terminationReason
            )
        }
    }
}

nonisolated enum StatusSource: Sendable {
    case live
    case hydration
}

extension String? {
    nonisolated var nonEmpty: String? {
        guard let text = self, !text.isEmpty else { return nil }
        return text
    }
}

struct Session: Identifiable, Codable, Equatable {
    var agentSessionID: String // May be shared across split panes
    let terminalSessionID: String // e.g., "w0t0p0:UUID"
    var tmuxPane: String? // e.g., "%1", nil if not inside tmux

    var id: String {
        if let pane = tmuxPane {
            return "\(terminalSessionID):\(pane)"
        }
        return terminalSessionID
    }

    let terminalType: TerminalType
    var agent: String
    let projectPath: String
    var terminalTabName: String?
    var terminalWindowName: String?
    var tmuxSessionName: String?
    var customName: String?
    var note: String?
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

    var disposition = SessionDisposition.empty
    var transientDispositionOverrides = TransientDispositionOverrides()

    var isHidden: Bool { disposition.isHidden }
    var isCycleEligible: Bool { state.isIncludedInCycle && !isHidden }
    var notificationToken = UUID()
    var automationToken = UUID()
    var wasAwaitingUserBeforeBackburner: Bool { disposition.backburner?.wasAwaitingUser ?? false }

    var hooklinesinkerBindingIDs: Set<String> = []
    var bindingTurnObservations: [String: BindingTurnObservation] = [:]

    var details = SessionDetails()
    var turnCount: Int = 0

    var agentShortName: String {
        switch agent {
        case "opencode": "OC"
        case "codex": "CX"
        case "pi": "PI"
        case "antigravity": "AG"
        case "droid": "DR"
        case "qwen": "QW"
        case "kimi": "KM"
        default: "CC"
        }
    }

    var agentDisplayName: String {
        switch agent {
        case "claude-code": "Claude Code"
        case "opencode": "OpenCode"
        case "codex": "Codex"
        case "pi": "Pi"
        case "antigravity": "Antigravity"
        case "droid": "Factory Droid"
        case "qwen": "Qwen Code"
        case "kimi": "Kimi Code"
        default: agent
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
        case .agentTitle:
            return details.agentTitle.nonEmpty ?? parentAndFolderName
        }
    }

    enum CodingKeys: String, CodingKey {
        case agentSessionID, terminalSessionID, tmuxPane, terminalType, agent, projectPath
        case terminalTabName, terminalWindowName, tmuxSessionName, customName, note, state, startedAt
        case lastBecameIdle, lastBecameWorking, busyTimeToday
        case paneIndex, paneCount, gitBranch, gitRepoName, transcriptPath, remoteHost
    }

    // Excludes the volatile timing fields so .onChange(of: sessions) doesn't fire on
    // every hook event.
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.agentSessionID == rhs.agentSessionID &&
            lhs.terminalSessionID == rhs.terminalSessionID &&
            lhs.tmuxPane == rhs.tmuxPane &&
            lhs.terminalType == rhs.terminalType &&
            lhs.agent == rhs.agent &&
            lhs.projectPath == rhs.projectPath &&
            lhs.terminalTabName == rhs.terminalTabName &&
            lhs.terminalWindowName == rhs.terminalWindowName &&
            lhs.tmuxSessionName == rhs.tmuxSessionName &&
            lhs.customName == rhs.customName &&
            lhs.note == rhs.note &&
            lhs.disposition == rhs.disposition &&
            lhs.state == rhs.state &&
            lhs.startedAt == rhs.startedAt &&
            lhs.paneIndex == rhs.paneIndex &&
            lhs.paneCount == rhs.paneCount &&
            lhs.gitBranch == rhs.gitBranch &&
            lhs.gitRepoName == rhs.gitRepoName &&
            lhs.transcriptPath == rhs.transcriptPath &&
            lhs.remoteHost == rhs.remoteHost &&
            lhs.details.agentTitle == rhs.details.agentTitle
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

extension Session {
    var agentSessionIdentity: AgentSessionIdentity {
        AgentSessionIdentity(agent: agent, agentSessionID: agentSessionID)
    }

    var noteKey: SessionNoteKey? {
        let identity = agentSessionIdentity
        return identity.isPersistent ? identity : nil
    }

    mutating func replaceAgentSessionIdentity(with identity: AgentSessionIdentity) {
        agent = identity.agent
        agentSessionID = identity.agentSessionID
    }

    mutating func recordBindingTurns(bindingID: String?, detailsChange: DetailsChange?) {
        guard agentSessionIdentity.isPersistent, let bindingID, !bindingID.isEmpty,
              case let .replace(details)? = detailsChange else { return }
        let count = details.reportedTurns.flatMap { $0 >= 0 ? $0 : nil }
        let incoming = BindingTurnObservation(turns: count, observedAt: details.observedAt)
        bindingTurnObservations[bindingID] = bindingTurnObservations[bindingID]?.merging(incoming) ?? incoming
    }
}
