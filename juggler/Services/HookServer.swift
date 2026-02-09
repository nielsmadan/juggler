import Foundation
import Network

actor HookServer {
    static let shared = HookServer()

    private var listener: NWListener?
    private let port: UInt16 = 7483

    init() {}

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(integerLiteral: port)
        )

        listener = try NWListener(using: parameters)

        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Hook server listening on port \(self.port)")
            case let .failed(error):
                print("Hook server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())

        receiveHTTPRequest(connection) { request in
            Task {
                let response = await self.processRequest(request)
                let responseData = response.serialize()
                self.sendHTTPResponseData(connection, data: responseData)
            }
        }
    }

    private nonisolated func receiveHTTPRequest(
        _ connection: NWConnection,
        completion: @escaping @Sendable (HTTPRequest) -> Void
    ) {
        receiveFullRequest(connection, buffer: Data(), completion: completion)
    }

    private nonisolated func receiveFullRequest(
        _ connection: NWConnection,
        buffer: Data,
        completion: @escaping @Sendable (HTTPRequest) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            guard let data, error == nil else {
                // Try to parse whatever we have
                if !buffer.isEmpty, let request = HTTPRequest.parse(buffer) {
                    completion(request)
                } else {
                    connection.cancel()
                }
                return
            }

            var accumulated = buffer
            accumulated.append(data)

            if self.hasCompleteHTTPBody(accumulated) || isComplete {
                if let request = HTTPRequest.parse(accumulated) {
                    completion(request)
                } else {
                    connection.cancel()
                }
            } else {
                self.receiveFullRequest(connection, buffer: accumulated, completion: completion)
            }
        }
    }

    /// Check if accumulated data contains a complete HTTP request (headers + full body per Content-Length)
    nonisolated func hasCompleteHTTPBody(_ data: Data) -> Bool {
        let string = String(decoding: data, as: UTF8.self)

        // Need the header/body separator first
        guard let separatorRange = string.range(of: "\r\n\r\n") else {
            return false
        }

        let headerPart = string[string.startIndex ..< separatorRange.lowerBound]
        let bodyStartIndex = separatorRange.upperBound
        let currentBodyLength = string[bodyStartIndex...].utf8.count

        // Parse Content-Length from headers
        for line in headerPart.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            if let contentLength = Int(value) {
                return currentBodyLength >= contentLength
            }
        }

        // No Content-Length header — assume body is complete once we have the separator
        return true
    }

    private nonisolated func sendHTTPResponseData(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func decodeUnifiedPayload(_ body: String) -> UnifiedHookPayload? {
        try? JSONDecoder().decode(UnifiedHookPayload.self, from: Data(body.utf8))
    }

    private func processRequest(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.method == "POST" else {
            return HTTPResponse(status: 405, body: #"{"status":"error","message":"Method not allowed"}"#)
        }

        // Handle unified /hook endpoint
        guard request.path == "/hook" else {
            return HTTPResponse(status: 404, body: #"{"status":"error","message":"Not found"}"#)
        }

        guard let payload = decodeUnifiedPayload(request.body) else {
            await MainActor.run {
                logWarning(.hooks, "Invalid JSON in hook request: \(request.body.prefix(200))")
            }
            return HTTPResponse(status: 400, body: #"{"status":"error","message":"Invalid JSON"}"#)
        }

        await handleUnifiedHookEvent(payload)

        return HTTPResponse(status: 200, body: #"{"status":"ok"}"#)
    }

    private func handleUnifiedHookEvent(_ payload: UnifiedHookPayload) async {
        let terminalSessionID = payload.terminal?.sessionId ?? ""
        let claudeSessionID = payload.hookInput?.sessionId ?? ""
        let cwd = payload.terminal?.cwd ?? ""
        let gitBranch = payload.git?.branch
        let gitRepo = payload.git?.repo
        let transcriptPath = payload.hookInput?.transcriptPath
        let tmuxPane = payload.tmux?.pane
        let tmuxSessionName = payload.tmux?.sessionName

        await MainActor.run {
            logDebug(.hooks, "Hook received: \(payload.event) from \(payload.agent)")
        }

        let action = HookEventMapper.map(event: payload.event)

        switch action {
        case let .updateState(state):
            await MainActor.run {
                SessionManager.shared.addOrUpdateSession(
                    claudeSessionID: claudeSessionID,
                    terminalSessionID: terminalSessionID,
                    tmuxPane: tmuxPane,
                    tmuxSessionName: tmuxSessionName,
                    projectPath: cwd,
                    state: state,
                    event: payload.event,
                    gitBranch: gitBranch,
                    gitRepoName: gitRepo,
                    transcriptPath: transcriptPath
                )
                // Set focused session to composite ID so cycling knows which tmux pane is active
                let compositeID: String = if let pane = tmuxPane {
                    "\(terminalSessionID):\(pane)"
                } else {
                    terminalSessionID
                }
                SessionManager.shared.updateFocusedSession(terminalSessionID: compositeID)
            }
            await updateTerminalInfo(for: claudeSessionID, itermSessionID: terminalSessionID)

            // Send notifications for specific states
            let notifyID: String = if let pane = tmuxPane {
                "\(terminalSessionID):\(pane)"
            } else {
                terminalSessionID
            }
            switch state {
            case .idle:
                await sendNotificationIfEnabled(title: "Session Idle", sessionID: notifyID)
            case .permission:
                await sendNotificationIfEnabled(title: "Permission Required", sessionID: notifyID)
            default:
                break
            }

        case .removeSession:
            let removeID: String = if let pane = tmuxPane {
                "\(terminalSessionID):\(pane)"
            } else {
                terminalSessionID
            }
            await MainActor.run {
                SessionManager.shared.removeSession(sessionID: removeID)
            }

        case .ignore:
            await MainActor.run {
                logDebug(.hooks, "Ignoring unknown event: \(payload.event)")
            }
        }
    }

    private func sendNotificationIfEnabled(title: String, sessionID: String) async {
        let session = await MainActor.run {
            SessionManager.shared.sessions.first(where: { $0.id == sessionID })
        }
        guard let session else { return }

        let shouldNotify: Bool = switch title {
        case "Session Idle":
            UserDefaults.standard.bool(forKey: AppStorageKeys.notifyOnIdle)
        case "Permission Required":
            UserDefaults.standard.bool(forKey: AppStorageKeys.notifyOnPermission)
        default:
            false
        }

        if shouldNotify {
            await MainActor.run {
                NotificationManager.shared.sendNotification(
                    title: title,
                    body: session.displayName,
                    sessionID: sessionID
                )
            }
        }
    }

    private func updateTerminalInfo(for _: String, itermSessionID: String) async {
        guard !itermSessionID.isEmpty else { return }

        await MainActor.run {
            logDebug(.hooks, "updateTerminalInfo: calling getSessionInfo for \(itermSessionID)")
        }

        do {
            if let info = try await ITerm2Bridge.shared.getSessionInfo(sessionID: itermSessionID) {
                await MainActor.run {
                    logDebug(.hooks, "Got terminal info for \(itermSessionID): tab=\(info.tabName)")
                    SessionManager.shared.updateSessionTerminalInfo(
                        terminalSessionID: itermSessionID,
                        tabName: info.tabName,
                        windowName: info.windowName,
                        paneIndex: info.paneIndex,
                        paneCount: info.paneCount
                    )
                }
            } else {
                await MainActor.run {
                    logDebug(.hooks, "No terminal info found for \(itermSessionID)")
                }
            }
        } catch {
            await MainActor.run {
                logWarning(.hooks, "Failed to get terminal info: \(error)")
            }
        }
    }
}

// MARK: - HTTP Parsing

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let body: String

    nonisolated static func parse(_ data: Data) -> HTTPRequest? {
        let string = String(decoding: data, as: UTF8.self)

        let lines = string.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines.dropFirst(emptyLineIndex + 1)
            let body = bodyLines.joined(separator: "\r\n")
            return HTTPRequest(method: method, path: path, body: body)
        }

        return HTTPRequest(method: method, path: path, body: "")
    }
}

struct HTTPResponse: Sendable {
    let status: Int
    let body: String

    nonisolated func serialize() -> Data {
        let statusText = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        return Data(response.utf8)
    }
}

// MARK: - Unified Hook Payload

/// Unified payload format for all coding agent hooks
struct UnifiedHookPayload: Sendable {
    let agent: String
    let event: String
    let hookInput: HookInput?
    let terminal: TerminalInfo?
    let git: GitInfo?
    let tmux: TmuxInfo?

    struct HookInput: Sendable {
        let sessionId: String?
        let transcriptPath: String?
        let toolName: String?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case transcriptPath = "transcript_path"
            case toolName = "tool_name"
        }
    }

    struct TerminalInfo: Sendable {
        let sessionId: String?
        let cwd: String?
    }

    struct GitInfo: Sendable {
        let branch: String?
        let repo: String?
    }

    struct TmuxInfo: Sendable {
        let pane: String?
        let sessionName: String?
    }
}

extension UnifiedHookPayload: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decode(String.self, forKey: .agent)
        event = try container.decode(String.self, forKey: .event)
        hookInput = try container.decodeIfPresent(HookInput.self, forKey: .hookInput)
        terminal = try container.decodeIfPresent(TerminalInfo.self, forKey: .terminal)
        git = try container.decodeIfPresent(GitInfo.self, forKey: .git)
        tmux = try container.decodeIfPresent(TmuxInfo.self, forKey: .tmux)
    }

    enum CodingKeys: String, CodingKey {
        case agent, event, hookInput, terminal, git, tmux
    }
}

extension UnifiedHookPayload.HookInput: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
    }
}

extension UnifiedHookPayload.TerminalInfo: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd
    }
}

extension UnifiedHookPayload.GitInfo: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        repo = try container.decodeIfPresent(String.self, forKey: .repo)
    }

    enum CodingKeys: String, CodingKey {
        case branch, repo
    }
}

extension UnifiedHookPayload.TmuxInfo: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pane = try container.decodeIfPresent(String.self, forKey: .pane)
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
    }

    enum CodingKeys: String, CodingKey {
        case pane, sessionName
    }
}
