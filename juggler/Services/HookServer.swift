import Foundation
import Network

actor HookServer {
    static let shared = HookServer()

    private var listener: NWListener?
    private var eventProcessingTask: Task<Void, Never>?
    private var pendingActions: [HookServerRequestAction] = []
    private var terminalRefreshTasks: [String: Task<Void, Never>] = [:]
    private var pendingTerminalRefreshes: [String: TerminalRefreshRequest] = [:]
    private var workGeneration = 0
    private var port: UInt16 = 7483
    private let maxRequestSize = 1_048_576
    private let maxPendingActions = 256
    private let maxRetainedInvalidBodySize = 200
    private let sessionManager: SessionManager
    private let terminalBridgeRegistry: TerminalBridgeRegistry
    private let willProcessQueuedAction: (@Sendable () async -> Void)?

    init(
        sessionManager: SessionManager? = nil,
        terminalBridgeRegistry: TerminalBridgeRegistry = .shared,
        willProcessQueuedAction: (@Sendable () async -> Void)? = nil
    ) {
        self.sessionManager = sessionManager ?? .shared
        self.terminalBridgeRegistry = terminalBridgeRegistry
        self.willProcessQueuedAction = willProcessQueuedAction
    }

    func start() async throws {
        port = TestInstanceConfig.hookPort()
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

        listener?.stateUpdateHandler = { [port] state in
            switch state {
            case .ready:
                Task { await MainActor.run { logInfo(.hooks, "Hook server listening on port \(port)") } }
            case let .failed(error):
                Task { await MainActor.run { logError(.hooks, "Hook server failed: \(error)") } }
            default:
                break
            }
        }

        listener?.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
        workGeneration += 1
        eventProcessingTask?.cancel()
        eventProcessingTask = nil
        pendingActions.removeAll()
        for task in terminalRefreshTasks.values {
            task.cancel()
        }
        terminalRefreshTasks.removeAll()
        pendingTerminalRefreshes.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())

        receiveHTTPRequest(connection) { request in
            Task {
                await self.acknowledge(request, on: connection)
            }
        }
    }

    private func acknowledge(_ request: HTTPRequest, on connection: NWConnection) async {
        await acknowledge(request) { [weak self] response in
            self?.sendHTTPResponseData(connection, data: response.serialize())
        }
    }

    func acknowledge(
        _ request: HTTPRequest,
        sendResponse: @escaping @Sendable (HTTPResponse) async -> Void
    ) async {
        let routedRequest = routeRequest(request)
        await sendResponse(routedRequest.response)
        await enqueue(routedRequest.action)
    }

    private func enqueue(_ action: HookServerRequestAction) async {
        if case .none = action { return }

        if pendingActions.count >= maxPendingActions {
            pendingActions.removeFirst()
            await MainActor.run {
                logWarning(.hooks, "Hook event queue full; dropped oldest pending event")
            }
        }
        pendingActions.append(action)
        guard eventProcessingTask == nil else { return }

        let generation = workGeneration
        eventProcessingTask = Task { [weak self] in
            await self?.processQueuedActions(generation: generation)
        }
    }

    private func processQueuedActions(generation: Int) async {
        while generation == workGeneration, !Task.isCancelled, !pendingActions.isEmpty {
            let action = pendingActions.removeFirst()
            await willProcessQueuedAction?()
            guard generation == workGeneration, !Task.isCancelled else { break }
            await processRequestAction(action)
        }
        if generation == workGeneration {
            eventProcessingTask = nil
        }
    }

    func waitForQueuedRequests() async {
        let task = eventProcessingTask
        await task?.value
    }

    func waitForTerminalRefreshes() async {
        while !terminalRefreshTasks.isEmpty {
            let tasks = Array(terminalRefreshTasks.values)
            for task in tasks {
                await task.value
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
                if !buffer.isEmpty, let request = HTTPRequest.parse(buffer) {
                    completion(request)
                } else {
                    connection.cancel()
                }
                return
            }

            var accumulated = buffer
            accumulated.append(data)

            guard accumulated.count <= self.maxRequestSize else {
                connection.cancel()
                return
            }

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

    nonisolated func hasCompleteHTTPBody(_ data: Data) -> Bool {
        let string = String(bytes: data, encoding: .utf8) ?? ""

        guard let separatorRange = string.range(of: "\r\n\r\n") else {
            return false
        }

        let headerPart = string[string.startIndex ..< separatorRange.lowerBound]
        let bodyStartIndex = separatorRange.upperBound
        let currentBodyLength = string[bodyStartIndex...].utf8.count

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

    func decodeUnifiedPayload(_ body: String) -> UnifiedHookPayload? {
        try? JSONDecoder().decode(UnifiedHookPayload.self, from: Data(body.utf8))
    }

    func processRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let routedRequest = routeRequest(request)
        await processRequestAction(routedRequest.action)
        return routedRequest.response
    }

    func routeRequest(_ request: HTTPRequest) -> RoutedHTTPRequest {
        guard request.method == "POST" else {
            return RoutedHTTPRequest(
                response: HTTPResponse(
                    status: 405,
                    body: #"{"status":"error","message":"Method not allowed"}"#
                ),
                action: .none
            )
        }

        switch request.path {
        case "/hook":
            guard let payload = decodeUnifiedPayload(request.body) else {
                return RoutedHTTPRequest(
                    response: HTTPResponse(
                        status: 400,
                        body: #"{"status":"error","message":"Invalid JSON"}"#
                    ),
                    action: .invalidHook(String(request.body.prefix(maxRetainedInvalidBodySize)))
                )
            }

            return RoutedHTTPRequest(
                response: HTTPResponse(status: 200, body: #"{"status":"ok"}"#),
                action: .hook(payload)
            )

        case "/kitty-event":
            guard let eventPayload = try? JSONDecoder().decode(KittyEventPayload.self, from: Data(request.body.utf8))
            else {
                return RoutedHTTPRequest(
                    response: HTTPResponse(
                        status: 400,
                        body: #"{"status":"error","message":"Invalid JSON"}"#
                    ),
                    action: .invalidKittyEvent(String(request.body.prefix(maxRetainedInvalidBodySize)))
                )
            }

            return RoutedHTTPRequest(
                response: HTTPResponse(status: 200, body: #"{"status":"ok"}"#),
                action: .kittyEvent(eventPayload)
            )

        default:
            return RoutedHTTPRequest(
                response: HTTPResponse(status: 404, body: #"{"status":"error","message":"Not found"}"#),
                action: .none
            )
        }
    }

    private func processRequestAction(_ action: HookServerRequestAction) async {
        switch action {
        case let .hook(payload):
            await handleUnifiedHookEvent(payload)
        case let .kittyEvent(payload):
            await handleKittyEvent(payload)
        case let .invalidHook(body):
            await MainActor.run {
                logWarning(.hooks, "Invalid JSON in hook request: \(body.prefix(200))")
            }
        case let .invalidKittyEvent(body):
            await MainActor.run {
                logWarning(.kitty, "Invalid JSON in kitty-event request: \(body.prefix(200))")
            }
        case .none:
            break
        }
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
        let remoteHost = payload.remoteHost
        let compositeID = tmuxPane.map { "\(terminalSessionID):\($0)" } ?? terminalSessionID

        // No terminal session ID means no activation address: the row could never be
        // activated or auto-removed (the iTerm2 daemon asserts on an empty id).
        guard !terminalSessionID.isEmpty else {
            await MainActor.run {
                logWarning(
                    .hooks,
                    "Dropping hook event with empty terminal session ID "
                        + "(agent=\(payload.agent), event=\(payload.event), cwd=\(cwd))"
                )
            }
            return
        }

        let terminalType: TerminalType = if let typeStr = payload.terminal?.terminalType,
                                            let type = TerminalType(rawValue: typeStr) {
            type
        } else {
            .iterm2
        }

        await MainActor.run {
            logDebug(.hooks, "Hook received: \(payload.event) from \(payload.agent) (\(terminalType.displayName))")
        }

        let action = HookEventMapper.map(
            event: payload.event,
            agent: payload.agent,
            toolName: payload.hookInput?.toolName
        )

        switch action {
        case let .updateState(state):
            await MainActor.run {
                self.sessionManager.addOrUpdateSession(
                    claudeSessionID: claudeSessionID,
                    terminalSessionID: terminalSessionID,
                    tmuxPane: tmuxPane,
                    tmuxSessionName: tmuxSessionName,
                    terminalType: terminalType,
                    agent: payload.agent,
                    projectPath: cwd,
                    state: state,
                    event: payload.event,
                    gitBranch: gitBranch,
                    gitRepoName: gitRepo,
                    transcriptPath: transcriptPath,
                    remoteHost: remoteHost
                )
            }
            switch state {
            case .idle:
                await sendNotificationIfEnabled(title: "Session Idle", sessionID: compositeID)
            case .permission:
                await sendNotificationIfEnabled(title: "Permission Required", sessionID: compositeID)
            default:
                break
            }

            scheduleTerminalRefresh(
                terminalSessionID: terminalSessionID,
                terminalType: terminalType,
                remoteHost: remoteHost,
                listenSocket: payload.terminal?.kittyListenOn
            )

        case .removeSession:
            await removeSessionIfCurrent(
                compositeID: compositeID,
                agentSessionID: claudeSessionID,
                event: payload.event
            )

        case .ignore:
            await MainActor.run {
                logDebug(.hooks, "Ignoring unknown event: \(payload.event)")
            }
        }
    }

    private func prepareTerminalAddressing(
        sessionID: String,
        terminalType: TerminalType,
        remoteHost: String?,
        listenSocket: String?
    ) async {
        guard let bridge = await terminalBridgeRegistry.bridge(for: terminalType) else { return }
        await bridge.prepareAddressing(
            sessionID: sessionID,
            context: HookAddressingContext(
                isRemote: !(remoteHost?.isEmpty ?? true),
                listenSocket: listenSocket
            )
        )
    }

    private func scheduleTerminalRefresh(
        terminalSessionID: String,
        terminalType: TerminalType,
        remoteHost: String?,
        listenSocket: String?,
        discoverKittySocket: Bool = false
    ) {
        let key = "\(terminalType.rawValue):\(terminalSessionID)"
        pendingTerminalRefreshes[key] = TerminalRefreshRequest(
            terminalSessionID: terminalSessionID,
            terminalType: terminalType,
            remoteHost: remoteHost,
            listenSocket: listenSocket,
            discoverKittySocket: discoverKittySocket
        )
        guard terminalRefreshTasks[key] == nil else { return }

        let generation = workGeneration
        terminalRefreshTasks[key] = Task { [weak self] in
            await self?.processTerminalRefreshes(for: key, generation: generation)
        }
    }

    private func processTerminalRefreshes(for key: String, generation: Int) async {
        while generation == workGeneration,
              !Task.isCancelled,
              let refresh = pendingTerminalRefreshes.removeValue(forKey: key) {
            if refresh.discoverKittySocket {
                await KittyBridge.shared.registerLocalSocket(forWindowID: refresh.terminalSessionID)
            } else {
                await prepareTerminalAddressing(
                    sessionID: refresh.terminalSessionID,
                    terminalType: refresh.terminalType,
                    remoteHost: refresh.remoteHost,
                    listenSocket: refresh.listenSocket
                )
            }
            guard generation == workGeneration, !Task.isCancelled else { break }

            if pendingTerminalRefreshes[key] == nil {
                await updateTerminalInfo(
                    terminalSessionID: refresh.terminalSessionID,
                    terminalType: refresh.terminalType
                )
            }
        }

        if generation == workGeneration {
            terminalRefreshTasks[key] = nil
        }
    }

    /// A Codex thread abandoned via `/new` keeps firing its own SessionEnd at idle-unload, long
    /// after a newer thread took over the pane. Sessions are keyed by pane, so removing
    /// unconditionally would delete the live row. Only skip when both ids are known and disagree —
    /// agents that send no session id keep the unconditional behaviour.
    @MainActor
    private func removeSessionIfCurrent(compositeID: String, agentSessionID: String, event: String) {
        let current = sessionManager.sessions.first { $0.id == compositeID }
        if let current, !agentSessionID.isEmpty, !current.claudeSessionID.isEmpty,
           current.claudeSessionID != agentSessionID {
            logDebug(
                .hooks,
                "Ignoring \(event) from stale session \(agentSessionID) "
                    + "(pane holds \(current.claudeSessionID))"
            )
            return
        }
        sessionManager.removeSession(sessionID: compositeID)
    }

    private func sendNotificationIfEnabled(title: String, sessionID: String) async {
        let session = await MainActor.run {
            self.sessionManager.sessions.first(where: { $0.id == sessionID })
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
                    body: session.title(for: SessionTitleMode(
                        rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.sessionTitleMode) ?? ""
                    ) ?? .default),
                    sessionID: sessionID
                )
            }
        }
    }

    private func updateTerminalInfo(terminalSessionID: String, terminalType: TerminalType) async {
        guard !terminalSessionID.isEmpty else { return }

        await MainActor.run {
            logDebug(.hooks, "updateTerminalInfo: calling getSessionInfo for \(terminalSessionID)")
        }

        guard let bridge = await terminalBridgeRegistry.bridge(for: terminalType) else {
            await MainActor.run {
                logDebug(.hooks, "No bridge available for \(terminalType.displayName)")
            }
            return
        }

        do {
            if let info = try await bridge.getSessionInfo(sessionID: terminalSessionID) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    logDebug(.hooks, "Got terminal info for \(terminalSessionID): tab=\(info.tabName)")
                    self.sessionManager.updateSessionTerminalInfo(
                        terminalSessionID: terminalSessionID,
                        tabName: info.tabName,
                        windowName: info.windowName,
                        paneIndex: info.paneIndex,
                        paneCount: info.paneCount
                    )
                }
            } else {
                await MainActor.run {
                    logDebug(.hooks, "No terminal info found for \(terminalSessionID)")
                }
            }
        } catch {
            await MainActor.run {
                logWarning(.hooks, "Failed to get terminal info: \(error)")
            }
        }
    }

    private func handleKittyEvent(_ payload: KittyEventPayload) async {
        await MainActor.run {
            logDebug(.kitty, "Kitty event: \(payload.event) window=\(payload.windowID)")
        }

        switch payload.event {
        case "focus_changed":
            await MainActor.run {
                self.sessionManager.updateFocusedSession(
                    terminalSessionID: payload.windowID,
                    focusTerminalType: .kitty
                )
            }
            scheduleTerminalRefresh(
                terminalSessionID: payload.windowID,
                terminalType: .kitty,
                remoteHost: nil,
                listenSocket: nil,
                discoverKittySocket: true
            )
        case "session_terminated":
            await MainActor.run {
                self.sessionManager.removeSessionsByTerminalID(payload.windowID)
            }
        default:
            await MainActor.run {
                logDebug(.kitty, "Unknown kitty event: \(payload.event)")
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
        guard let string = String(bytes: data, encoding: .utf8) else { return nil }

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

struct RoutedHTTPRequest: Sendable {
    let response: HTTPResponse
    let action: HookServerRequestAction
}

enum HookServerRequestAction: Sendable {
    case hook(UnifiedHookPayload)
    case kittyEvent(KittyEventPayload)
    case invalidHook(String)
    case invalidKittyEvent(String)
    case none
}

private struct TerminalRefreshRequest: Sendable {
    let terminalSessionID: String
    let terminalType: TerminalType
    let remoteHost: String?
    let listenSocket: String?
    let discoverKittySocket: Bool
}

// MARK: - Unified Hook Payload

struct UnifiedHookPayload: Sendable {
    let agent: String
    let event: String
    let hookInput: HookInput?
    let terminal: TerminalInfo?
    let git: GitInfo?
    let tmux: TmuxInfo?
    let remoteHost: String?

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
        let terminalType: String?
        let kittyListenOn: String?
        let kittyPid: String?
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
        remoteHost = try container.decodeIfPresent(String.self, forKey: .remoteHost)
    }

    enum CodingKeys: String, CodingKey {
        case agent, event, hookInput, terminal, git, tmux, remoteHost
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
        terminalType = try container.decodeIfPresent(String.self, forKey: .terminalType)
        kittyListenOn = try container.decodeIfPresent(String.self, forKey: .kittyListenOn)
        kittyPid = try container.decodeIfPresent(String.self, forKey: .kittyPid)
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, terminalType, kittyListenOn, kittyPid
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

// MARK: - Kitty Event Payload

struct KittyEventPayload: Sendable {
    let event: String
    let windowID: String

    enum CodingKeys: String, CodingKey {
        case event
        case windowID = "window_id"
    }
}

extension KittyEventPayload: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        windowID = try container.decode(String.self, forKey: .windowID)
    }
}
