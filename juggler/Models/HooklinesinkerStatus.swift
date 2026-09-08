import Foundation

/// Hooklinesinker's protocol-v1 status event. Both the HTTP sink (`POST /hook`) and
/// `hooklinesinker sessions --json` speak this shape; `HookServer` maps it straight to a
/// `SessionState` without going through `HookEventMapper`, which now only serves the legacy
/// `UnifiedHookPayload` path.
struct HooklinesinkerStatus: Sendable {
    static let supportedProtocol = 1

    let `protocol`: Int
    let bindingId: String
    let agent: String
    let event: String
    let phase: HooklinesinkerPhase
    let running: Bool
    let observedAt: String
    let session: SessionIdentity
    let process: ProcessIdentity?
    let terminal: TerminalIdentity?
    let tmux: TmuxIdentity?
    let git: GitIdentity?
    let remoteHost: String?

    struct SessionIdentity: Sendable {
        let id: String
        let cwd: String
        let transcriptPath: String?
    }

    struct ProcessIdentity: Sendable {
        let pid: Int
        let startedAt: String
        let host: String
    }

    /// Note the asymmetry with the legacy payload: `cwd` lives on `session`, not here.
    struct TerminalIdentity: Sendable {
        let sessionId: String?
        let terminalType: String?
        let kittyListenOn: String?
        let kittyPid: String?
    }

    struct TmuxIdentity: Sendable {
        let pane: String?
        let sessionName: String?
    }

    struct GitIdentity: Sendable {
        let branch: String?
        let repo: String?
    }

    /// Hooklinesinker spells Claude Code `claude`; Juggler's `Session.agent` has always
    /// spelled it `claude-code`, and display names and stats keys are derived from it.
    var jugglerAgent: String {
        agent == "claude" ? "claude-code" : agent
    }

    var terminalSessionID: String {
        terminal?.sessionId ?? ""
    }

    var compositeSessionID: String {
        guard let pane = tmux?.pane, !pane.isEmpty else { return terminalSessionID }
        return "\(terminalSessionID):\(pane)"
    }

    var resolvedTerminalType: TerminalType {
        terminal?.terminalType.flatMap(TerminalType.init(rawValue:)) ?? .iterm2
    }
}

/// `unknown` is carried for diagnostics but never cycles a session — see `sessionState`.
enum HooklinesinkerPhase: String, Sendable {
    case idle
    case working
    case permission
    case compacting
    case unknown

    var sessionState: SessionState? {
        switch self {
        case .idle: .idle
        case .working: .working
        case .permission: .permission
        case .compacting: .compacting
        case .unknown: nil
        }
    }
}

extension HooklinesinkerPhase: Decodable {
    // A phase spelling from a newer producer degrades to `unknown` rather than failing the
    // whole decode, which would drop the event and its identity along with it.
    nonisolated init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HooklinesinkerPhase(rawValue: raw) ?? .unknown
    }
}

extension HooklinesinkerStatus: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        `protocol` = try container.decode(Int.self, forKey: .protocol)
        bindingId = try container.decode(String.self, forKey: .bindingId)
        agent = try container.decode(String.self, forKey: .agent)
        event = try container.decode(String.self, forKey: .event)
        phase = try container.decode(HooklinesinkerPhase.self, forKey: .phase)
        running = try container.decode(Bool.self, forKey: .running)
        observedAt = try container.decode(String.self, forKey: .observedAt)
        session = try container.decode(SessionIdentity.self, forKey: .session)
        process = try container.decodeIfPresent(ProcessIdentity.self, forKey: .process)
        terminal = try container.decodeIfPresent(TerminalIdentity.self, forKey: .terminal)
        tmux = try container.decodeIfPresent(TmuxIdentity.self, forKey: .tmux)
        git = try container.decodeIfPresent(GitIdentity.self, forKey: .git)
        remoteHost = try container.decodeIfPresent(String.self, forKey: .remoteHost)
    }

    enum CodingKeys: String, CodingKey {
        case `protocol`, bindingId, agent, event, phase, running, observedAt
        case session, process, terminal, tmux, git, remoteHost
    }
}

extension HooklinesinkerStatus.SessionIdentity: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cwd = try container.decode(String.self, forKey: .cwd)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
    }

    enum CodingKeys: String, CodingKey {
        case id, cwd, transcriptPath
    }
}

extension HooklinesinkerStatus.ProcessIdentity: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int.self, forKey: .pid)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        host = try container.decode(String.self, forKey: .host)
    }

    enum CodingKeys: String, CodingKey {
        case pid, startedAt, host
    }
}

extension HooklinesinkerStatus.TerminalIdentity: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        terminalType = try container.decodeIfPresent(String.self, forKey: .terminalType)
        kittyListenOn = try container.decodeIfPresent(String.self, forKey: .kittyListenOn)
        kittyPid = try container.decodeIfPresent(String.self, forKey: .kittyPid)
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, terminalType, kittyListenOn, kittyPid
    }
}

extension HooklinesinkerStatus.TmuxIdentity: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pane = try container.decodeIfPresent(String.self, forKey: .pane)
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
    }

    enum CodingKeys: String, CodingKey {
        case pane, sessionName
    }
}

extension HooklinesinkerStatus.GitIdentity: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        repo = try container.decodeIfPresent(String.self, forKey: .repo)
    }

    enum CodingKeys: String, CodingKey {
        case branch, repo
    }
}
