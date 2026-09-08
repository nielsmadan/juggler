import Foundation
@testable import Juggler
import Testing

@Suite("HookServer")
struct HookServerTests {
    private actor RequestOrderRecorder {
        private var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }

        func recordedEvents() -> [String] {
            events
        }
    }

    private actor BlockingTerminalBridge: TerminalBridge {
        private var prepareCallCount = 0
        private var infoCallCount = 0
        private var prepareStarted = false
        private var prepareStartWaiters: [CheckedContinuation<Void, Never>] = []
        private var prepareContinuation: CheckedContinuation<Void, Never>?

        func start() async throws {}
        func stop() async {}
        func activate(sessionID _: String) async throws {}
        func highlight(
            sessionID _: String,
            tabConfig _: HighlightConfig?,
            paneConfig _: HighlightConfig?
        ) async throws {}

        func prepareAddressing(sessionID _: String, context _: HookAddressingContext) async {
            prepareCallCount += 1
            guard prepareCallCount == 1 else { return }
            prepareStarted = true
            for waiter in prepareStartWaiters {
                waiter.resume()
            }
            prepareStartWaiters.removeAll()
            await withCheckedContinuation { continuation in
                prepareContinuation = continuation
            }
        }

        func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? {
            infoCallCount += 1
            return nil
        }

        func waitUntilPrepareStarts() async {
            if prepareStarted { return }
            await withCheckedContinuation { continuation in
                prepareStartWaiters.append(continuation)
            }
        }

        func releasePrepare() {
            prepareContinuation?.resume()
            prepareContinuation = nil
        }

        func callCounts() -> (prepare: Int, info: Int) {
            (prepareCallCount, infoCallCount)
        }
    }

    // MARK: - HTTPRequest.parse Tests

    @Test func parse_validGETRequest() {
        let raw = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = HTTPRequest.parse(Data(raw.utf8))

        #expect(request != nil)
        #expect(request?.method == "GET")
        #expect(request?.path == "/status")
        #expect(request?.body == "")
    }

    @Test func parse_validPOSTWithBody() {
        let raw = "POST /hook HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"event\":\"Stop\"}"
        let request = HTTPRequest.parse(Data(raw.utf8))

        #expect(request != nil)
        #expect(request?.method == "POST")
        #expect(request?.path == "/hook")
        #expect(request?.body == "{\"event\":\"Stop\"}")
    }

    @Test func parse_emptyBody() {
        let raw = "POST /hook HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = HTTPRequest.parse(Data(raw.utf8))

        #expect(request != nil)
        #expect(request?.body == "")
    }

    @Test func parse_invalidData_parsesWithEmptyBody() {
        let request = HTTPRequest.parse(Data("not http at all".utf8))

        // Space-separated, so the first two words parse as method/path; there is no body separator.
        #expect(request?.body == "")
    }

    @Test func parse_emptyData_returnsNil() {
        let request = HTTPRequest.parse(Data())

        #expect(request == nil)
    }

    // MARK: - HTTPResponse.serialize Tests

    @Test func serialize_200OK() {
        let response = HTTPResponse(status: 200, body: "{\"status\":\"ok\"}")
        let data = response.serialize()
        let string = String(decoding: data, as: UTF8.self)

        #expect(string.contains("HTTP/1.1 200 OK"))
        #expect(string.contains("Content-Type: application/json"))
        #expect(string.contains("{\"status\":\"ok\"}"))
    }

    @Test func serialize_404NotFound() {
        let response = HTTPResponse(status: 404, body: "{}")
        let data = response.serialize()
        let string = String(decoding: data, as: UTF8.self)

        #expect(string.contains("HTTP/1.1 404 Not Found"))
    }

    @Test func serialize_405MethodNotAllowed() {
        let response = HTTPResponse(status: 405, body: "{}")
        let data = response.serialize()
        let string = String(decoding: data, as: UTF8.self)

        #expect(string.contains("HTTP/1.1 405 Method Not Allowed"))
    }

    @Test func serialize_bodyContentLengthMatchesUTF8() {
        let body = "{\"message\":\"hello world\"}"
        let response = HTTPResponse(status: 200, body: body)
        let data = response.serialize()
        let string = String(decoding: data, as: UTF8.self)

        #expect(string.contains("Content-Length: \(body.utf8.count)"))
    }

    // MARK: - hasCompleteHTTPBody Tests

    @Test func hasCompleteHTTPBody_noHeaderSeparator_returnsFalse() async {
        let server = HookServer()
        let data = Data("GET /status HTTP/1.1\r\nHost: localhost".utf8)

        #expect(server.hasCompleteHTTPBody(data) == false)
    }

    @Test func hasCompleteHTTPBody_noContentLength_returnsTrue() async {
        let server = HookServer()
        let data = Data("GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)

        #expect(server.hasCompleteHTTPBody(data) == true)
    }

    @Test func hasCompleteHTTPBody_bodyMatchesContentLength_returnsTrue() async {
        let server = HookServer()
        let body = "{\"ok\":true}"
        let raw = "POST /hook HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"

        #expect(server.hasCompleteHTTPBody(Data(raw.utf8)) == true)
    }

    @Test func hasCompleteHTTPBody_bodyTooShort_returnsFalse() async {
        let server = HookServer()
        let raw = "POST /hook HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort"

        #expect(server.hasCompleteHTTPBody(Data(raw.utf8)) == false)
    }

    @Test func hasCompleteHTTPBody_bodyLongerThanContentLength_returnsTrue() async {
        let server = HookServer()
        let raw = "POST /hook HTTP/1.1\r\nContent-Length: 2\r\n\r\nextra data here"

        #expect(server.hasCompleteHTTPBody(Data(raw.utf8)) == true)
    }

    // MARK: - UnifiedHookPayload Decoding Tests

    @Test func decodePayload_fullPayload() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "SessionStart",
            "hookInput": {
                "session_id": "s123",
                "transcript_path": "/tmp/transcript.jsonl",
                "tool_name": "bash"
            },
            "terminal": {
                "sessionId": "w0t0p0:uuid",
                "cwd": "/Users/test/project"
            },
            "git": {
                "branch": "main",
                "repo": "my-repo"
            },
            "tmux": {
                "pane": "%1",
                "sessionName": "dev"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.agent == "claude-code")
        #expect(payload.event == "SessionStart")
        #expect(payload.hookInput?.sessionId == "s123")
        #expect(payload.hookInput?.transcriptPath == "/tmp/transcript.jsonl")
        #expect(payload.hookInput?.toolName == "bash")
        #expect(payload.terminal?.sessionId == "w0t0p0:uuid")
        #expect(payload.terminal?.cwd == "/Users/test/project")
        #expect(payload.git?.branch == "main")
        #expect(payload.git?.repo == "my-repo")
        #expect(payload.tmux?.pane == "%1")
        #expect(payload.tmux?.sessionName == "dev")
    }

    @Test func decodePayload_minimalPayload() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "Stop"
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.agent == "claude-code")
        #expect(payload.event == "Stop")
        #expect(payload.hookInput == nil)
        #expect(payload.terminal == nil)
        #expect(payload.git == nil)
        #expect(payload.tmux == nil)
    }

    @Test func decodePayload_missingRequiredField_throws() {
        let json = """
        {
            "agent": "claude-code"
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))
        }
    }

    @Test func decodePayload_hookInput_snakeCaseKeys() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "PreToolUse",
            "hookInput": {
                "session_id": "abc-123",
                "transcript_path": "~/path/to/transcript.jsonl"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.hookInput?.sessionId == "abc-123")
        #expect(payload.hookInput?.transcriptPath == "~/path/to/transcript.jsonl")
    }

    // MARK: - Terminal Type Payload Tests

    @Test func decodePayload_kittyTerminalType() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "SessionStart",
            "terminal": {
                "sessionId": "42",
                "cwd": "/Users/test",
                "terminalType": "kitty",
                "kittyListenOn": "unix:/tmp/kitty-12345",
                "kittyPid": "12345"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.terminal?.terminalType == "kitty")
        #expect(payload.terminal?.kittyListenOn == "unix:/tmp/kitty-12345")
        #expect(payload.terminal?.kittyPid == "12345")
        #expect(payload.terminal?.sessionId == "42")
    }

    @Test func decodePayload_wezTermTerminalType() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "SessionStart",
            "terminal": {
                "sessionId": "7",
                "cwd": "/Users/test",
                "terminalType": "wezterm"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.terminal?.terminalType == "wezterm")
        #expect(payload.terminal?.sessionId == "7")
        // The raw string must resolve to the enum case HookServer routes on.
        #expect(TerminalType(rawValue: payload.terminal?.terminalType ?? "") == .wezterm)
    }

    @Test func decodePayload_noTerminalType_defaultsToNil() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "Stop",
            "terminal": {
                "sessionId": "w0t0p0:uuid",
                "cwd": "/tmp"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.terminal?.terminalType == nil)
        #expect(payload.terminal?.kittyListenOn == nil)
        #expect(payload.terminal?.kittyPid == nil)
    }

    // MARK: - KittyEventPayload Tests

    @Test func decodeKittyEventPayload_focusChanged() throws {
        let json = """
        {
            "event": "focus_changed",
            "window_id": "42"
        }
        """

        let payload = try JSONDecoder().decode(KittyEventPayload.self, from: Data(json.utf8))

        #expect(payload.event == "focus_changed")
        #expect(payload.windowID == "42")
    }

    @Test func decodeKittyEventPayload_sessionTerminated() throws {
        let json = """
        {
            "event": "session_terminated",
            "window_id": "99"
        }
        """

        let payload = try JSONDecoder().decode(KittyEventPayload.self, from: Data(json.utf8))

        #expect(payload.event == "session_terminated")
        #expect(payload.windowID == "99")
    }

    // MARK: - HookEventMapper Agent-Aware Tests

    @Test func mapOpenCode_sessionCreated_mapsToIdle() {
        let action = HookEventMapper.map(event: "session.created", agent: "opencode")
        #expect(action == .updateState(.idle))
    }

    @Test func mapOpenCode_sessionStatusIdle_mapsToIdle() {
        let action = HookEventMapper.map(event: "session.status.idle", agent: "opencode")
        #expect(action == .updateState(.idle))
    }

    @Test func mapOpenCode_sessionStatusBusy_mapsToWorking() {
        let action = HookEventMapper.map(event: "session.status.busy", agent: "opencode")
        #expect(action == .updateState(.working))
    }

    @Test func mapOpenCode_sessionStatusRetry_mapsToWorking() {
        let action = HookEventMapper.map(event: "session.status.retry", agent: "opencode")
        #expect(action == .updateState(.working))
    }

    @Test func mapOpenCode_permissionAsked_mapsToPermission() {
        let action = HookEventMapper.map(event: "permission.asked", agent: "opencode")
        #expect(action == .updateState(.permission))
    }

    @Test func mapOpenCode_sessionCompacted_mapsToCompacting() {
        let action = HookEventMapper.map(event: "session.compacted", agent: "opencode")
        #expect(action == .updateState(.compacting))
    }

    @Test func mapOpenCode_sessionDeleted_mapsToRemoveSession() {
        let action = HookEventMapper.map(event: "session.deleted", agent: "opencode")
        #expect(action == .removeSession)
    }

    @Test func mapOpenCode_serverDisposed_mapsToRemoveSession() {
        let action = HookEventMapper.map(event: "server.instance.disposed", agent: "opencode")
        #expect(action == .removeSession)
    }

    @Test func mapOpenCode_unknownEvent_mapsToIgnore() {
        let action = HookEventMapper.map(event: "lsp.updated", agent: "opencode")
        #expect(action == .ignore)
    }

    @Test func mapClaudeCode_defaultAgent_unchanged() {
        let action = HookEventMapper.map(event: "Stop")
        #expect(action == .updateState(.idle))
    }

    // MARK: - HTTPResponse Status Text Tests

    @Test func serialize_400BadRequest() {
        let response = HTTPResponse(status: 400, body: "{}")
        let string = String(decoding: response.serialize(), as: UTF8.self)

        #expect(string.contains("HTTP/1.1 400 Bad Request"))
    }

    @Test func serialize_500_usesDefaultErrorText() {
        let response = HTTPResponse(status: 500, body: "{}")
        let string = String(decoding: response.serialize(), as: UTF8.self)

        #expect(string.contains("HTTP/1.1 500 Error"))
    }

    @Test func serialize_unknownStatusCode_usesError() {
        let response = HTTPResponse(status: 418, body: "{}")
        let string = String(decoding: response.serialize(), as: UTF8.self)

        #expect(string.contains("HTTP/1.1 418 Error"))
    }

    // MARK: - Additional Payload Edge Cases

    @Test func decodePayload_emptyStrings() throws {
        let json = """
        {
            "agent": "",
            "event": "",
            "terminal": {
                "sessionId": "",
                "cwd": ""
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.agent == "")
        #expect(payload.event == "")
        #expect(payload.terminal?.sessionId == "")
        #expect(payload.terminal?.cwd == "")
    }

    @Test func decodePayload_gitWithoutBranch() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "Stop",
            "git": {
                "repo": "my-repo"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.git?.repo == "my-repo")
        #expect(payload.git?.branch == nil)
    }

    @Test func decodePayload_tmuxWithoutSessionName() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "Stop",
            "tmux": {
                "pane": "%3"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))

        #expect(payload.tmux?.pane == "%3")
        #expect(payload.tmux?.sessionName == nil)
    }

    // MARK: - HTTPRequest.parse Additional Tests

    @Test func parse_multipleHeaders() {
        let raw =
            "POST /hook HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}"
        let request = HTTPRequest.parse(Data(raw.utf8))

        #expect(request != nil)
        #expect(request?.method == "POST")
        #expect(request?.path == "/hook")
        #expect(request?.body == "{\"ok\":true}")
    }

    @Test func parse_bodyWithNewlines() {
        let body = "{\"msg\":\"line1\\nline2\"}"
        let raw = "POST /hook HTTP/1.1\r\nHost: localhost\r\n\r\n\(body)"
        let request = HTTPRequest.parse(Data(raw.utf8))

        #expect(request?.body == body)
    }

    @Test func parse_longPath() {
        let raw = "GET /very/long/path/to/resource HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = HTTPRequest.parse(Data(raw.utf8))

        #expect(request?.path == "/very/long/path/to/resource")
    }

    // MARK: - HTTPResponse Content-Length Tests

    @Test func serialize_contentLengthMatchesUnicodeBody() {
        let body = "{\"name\":\"日本語\"}"
        let response = HTTPResponse(status: 200, body: body)
        let data = response.serialize()
        let string = String(decoding: data, as: UTF8.self)

        #expect(string.contains("Content-Length: \(body.utf8.count)"))
    }

    @Test func serialize_emptyBody() {
        let response = HTTPResponse(status: 200, body: "")
        let data = response.serialize()
        let string = String(decoding: data, as: UTF8.self)

        #expect(string.contains("Content-Length: 0"))
        #expect(string.contains("HTTP/1.1 200 OK"))
    }

    // MARK: - HookEventMapper additional Tests

    @Test func mapOpenCode_allRemoveEvents() {
        #expect(HookEventMapper.map(event: "session.deleted", agent: "opencode") == .removeSession)
        #expect(HookEventMapper.map(event: "server.instance.disposed", agent: "opencode") == .removeSession)
    }

    @Test func mapOpenCode_allWorkingEvents() {
        #expect(HookEventMapper.map(event: "session.status.busy", agent: "opencode") == .updateState(.working))
        #expect(HookEventMapper.map(event: "session.status.retry", agent: "opencode") == .updateState(.working))
    }

    // MARK: - processRequest Route Tests

    @Test func processRequest_getNonPost_returns405() async {
        let server = HookServer(sessionManager: SessionManager())
        let request = HTTPRequest(method: "GET", path: "/hook", body: "")
        let response = await server.processRequest(request)
        #expect(response.status == 405)
    }

    @Test func processRequest_postUnknownPath_returns404() async {
        let server = HookServer(sessionManager: SessionManager())
        let request = HTTPRequest(method: "POST", path: "/unknown", body: "")
        let response = await server.processRequest(request)
        #expect(response.status == 404)
    }

    @Test func processRequest_postHook_invalidJSON_returns400() async {
        let server = HookServer(sessionManager: SessionManager())
        let request = HTTPRequest(method: "POST", path: "/hook", body: "not json")
        let response = await server.processRequest(request)
        #expect(response.status == 400)
    }

    @Test @MainActor func processRequest_postHook_validPayload_returns200() async {
        let server = HookServer(sessionManager: SessionManager())
        let body = """
        {"agent":"claude-code","event":"Stop","terminal":{"sessionId":"s1","cwd":"/test","terminalType":"iterm2"}}
        """
        let request = HTTPRequest(method: "POST", path: "/hook", body: body)
        let response = await server.processRequest(request)
        #expect(response.status == 200)
    }

    @Test @MainActor func acknowledge_validHook_sendsResponseBeforeProcessing() async {
        let manager = SessionManager()
        let recorder = RequestOrderRecorder()
        let server = HookServer(
            sessionManager: manager,
            willProcessQueuedAction: { await recorder.record("process") }
        )
        let body = """
        {"agent":"claude-code","event":"SessionStart",\
        "terminal":{"sessionId":"s1","cwd":"/test","terminalType":"iterm2"}}
        """

        await server.acknowledge(HTTPRequest(method: "POST", path: "/hook", body: body)) { response in
            await recorder.record("response-\(response.status)")
        }
        await server.waitForQueuedRequests()

        #expect(await recorder.recordedEvents() == ["response-200", "process"])
        #expect(manager.sessions.count == 1)
    }

    @Test @MainActor func acknowledge_multipleHooks_processesEveryRequestInOrder() async {
        let manager = SessionManager()
        let recorder = RequestOrderRecorder()
        let server = HookServer(
            sessionManager: manager,
            willProcessQueuedAction: { await recorder.record("process") }
        )
        let events = ["SessionStart", "PreToolUse", "Stop"]

        for event in events {
            let body = """
            {"agent":"claude-code","event":"\(event)",\
            "terminal":{"sessionId":"s1","cwd":"/test","terminalType":"iterm2"}}
            """
            await server.acknowledge(HTTPRequest(method: "POST", path: "/hook", body: body)) { _ in }
        }
        await server.waitForQueuedRequests()

        #expect(await recorder.recordedEvents() == ["process", "process", "process"])
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == .idle)
    }

    @Test @MainActor func slowTerminalRefresh_doesNotBlockStateAndCoalescesRepeatedEvents() async {
        let manager = SessionManager()
        let registry = TerminalBridgeRegistry()
        let bridge = BlockingTerminalBridge()
        await registry.register(bridge, for: .kitty)
        let server = HookServer(sessionManager: manager, terminalBridgeRegistry: registry)
        let kittyBody = """
        {"agent":"claude-code","event":"SessionStart","remoteHost":"user@host",\
        "terminal":{"sessionId":"kitty-1","cwd":"/test","terminalType":"kitty"}}
        """

        await server.acknowledge(HTTPRequest(method: "POST", path: "/hook", body: kittyBody)) { _ in }
        await bridge.waitUntilPrepareStarts()

        for _ in 0 ..< 10 {
            await server.acknowledge(HTTPRequest(method: "POST", path: "/hook", body: kittyBody)) { _ in }
        }
        let itermBody = """
        {"agent":"codex","event":"SessionStart",\
        "terminal":{"sessionId":"iterm-1","cwd":"/test","terminalType":"iterm2"}}
        """
        await server.acknowledge(HTTPRequest(method: "POST", path: "/hook", body: itermBody)) { _ in }
        await server.waitForQueuedRequests()

        #expect(manager.sessions.contains { $0.terminalSessionID == "kitty-1" })
        #expect(manager.sessions.contains { $0.terminalSessionID == "iterm-1" })

        await bridge.releasePrepare()
        await server.waitForTerminalRefreshes()
        let counts = await bridge.callCounts()
        #expect(counts.prepare == 2)
        #expect(counts.info == 1)
    }

    @Test @MainActor func processRequest_postHook_createsSessionInManager() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"},\
        "git":{"branch":"main","repo":"juggler"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].claudeSessionID == "claude-1")
        #expect(manager.sessions[0].terminalSessionID == "s1")
        #expect(manager.sessions[0].projectPath == "/test/project")
        #expect(manager.sessions[0].gitBranch == "main")
        #expect(manager.sessions[0].gitRepoName == "juggler")
        #expect(manager.sessions[0].state == .idle)
    }

    @Test @MainActor func processRequest_postHook_updatesExistingSessionState() async {
        let manager = SessionManager()
        manager.addOrUpdateSession(
            claudeSessionID: "claude-1",
            terminalSessionID: "s1",
            projectPath: "/test/project",
            state: .idle
        )
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"PreToolUse","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == .working)
    }

    @Test @MainActor func processRequest_codexRequestUserInput_marksSessionIdle() async {
        let manager = SessionManager()
        manager.addOrUpdateSession(
            claudeSessionID: "thread-1",
            terminalSessionID: "s1",
            agent: "codex",
            projectPath: "/test/project",
            state: .working
        )
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"codex","event":"PreToolUse","hookInput":{"session_id":"thread-1",\
        "tool_name":"request_user_input"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == .idle)
    }

    @Test @MainActor func processRequest_postHook_unknownEvent_isIgnored() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SomethingUnexpected","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func processRequest_postHook_invalidTerminalType_defaultsToITerm2() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"unknown-terminal"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalType == .iterm2)
    }

    @Test @MainActor func processRequest_postHook_kittyWithoutSocket_stillCreatesSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"kitty-window","cwd":"/test/project","terminalType":"kitty"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalType == .kitty)
        #expect(manager.sessions[0].terminalSessionID == "kitty-window")
    }

    @Test @MainActor func processRequest_postHook_removeEvent_removesCompositeTmuxSession() async {
        let manager = SessionManager()
        manager.addOrUpdateSession(
            claudeSessionID: "claude-1",
            terminalSessionID: "s1",
            tmuxPane: "%1",
            projectPath: "/test/project",
            state: .idle
        )
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionEnd","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"},\
        "tmux":{"pane":"%1","sessionName":"dev"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.isEmpty)
    }

    @Test func processRequest_postKittyEvent_invalidJSON_returns400() async {
        let server = HookServer(sessionManager: SessionManager())
        let request = HTTPRequest(method: "POST", path: "/kitty-event", body: "bad")
        let response = await server.processRequest(request)
        #expect(response.status == 400)
    }

    @Test @MainActor func processRequest_postKittyEvent_valid_returns200() async {
        let server = HookServer(sessionManager: SessionManager())
        let body = #"{"event":"focus_changed","window_id":"42"}"#
        let request = HTTPRequest(method: "POST", path: "/kitty-event", body: body)
        let response = await server.processRequest(request)
        #expect(response.status == 200)
    }

    @Test @MainActor func processRequest_postKittyEvent_focusChanged_updatesFocusedSession() async {
        let manager = SessionManager()
        manager.testSetSessions([makeSession("42")])
        let server = HookServer(sessionManager: manager)

        let response = await server.processRequest(
            HTTPRequest(method: "POST", path: "/kitty-event", body: #"{"event":"focus_changed","window_id":"42"}"#)
        )

        #expect(response.status == 200)
        #expect(manager.focusedSessionID == "42")
    }

    @Test @MainActor func processRequest_postKittyEvent_sessionTerminated_removesMatchingSessions() async {
        let manager = SessionManager()
        manager.testSetSessions([
            makeSession("42"),
            makeSession("99")
        ])
        let server = HookServer(sessionManager: manager)

        let response = await server.processRequest(
            HTTPRequest(
                method: "POST",
                path: "/kitty-event",
                body: #"{"event":"session_terminated","window_id":"42"}"#
            )
        )

        #expect(response.status == 200)
        #expect(manager.sessions.map(\.terminalSessionID) == ["99"])
    }

    @Test @MainActor func processRequest_postKittyEvent_unknownEvent_isNoOp() async {
        let manager = SessionManager()
        manager.testSetSessions([makeSession("42")])
        manager.updateFocusedSession(terminalSessionID: "42")
        let server = HookServer(sessionManager: manager)

        let response = await server.processRequest(
            HTTPRequest(method: "POST", path: "/kitty-event", body: #"{"event":"future_event","window_id":"99"}"#)
        )

        #expect(response.status == 200)
        #expect(manager.sessions.map(\.terminalSessionID) == ["42"])
        #expect(manager.focusedSessionID == "42")
    }

    @Test func processRequest_putMethod_returns405() async {
        let server = HookServer(sessionManager: SessionManager())
        let request = HTTPRequest(method: "PUT", path: "/hook", body: "{}")
        let response = await server.processRequest(request)
        #expect(response.status == 405)
    }

    // MARK: - decodeUnifiedPayload Tests

    @Test func decodeUnifiedPayload_validMinimal_succeeds() async {
        let server = HookServer(sessionManager: SessionManager())
        let body = #"{"agent":"claude-code","event":"Stop"}"#
        let payload = await server.decodeUnifiedPayload(body)
        #expect(payload != nil)
        #expect(payload?.agent == "claude-code")
        #expect(payload?.event == "Stop")
    }

    @Test func decodeUnifiedPayload_withAllFields_succeeds() async {
        let server = HookServer(sessionManager: SessionManager())
        let body = """
        {"agent":"opencode","event":"session.created","hookInput":{"session_id":"abc","transcript_path":"/tmp/t.jsonl"},\
        "terminal":{"sessionId":"s1","cwd":"/test","terminalType":"kitty","kittyListenOn":"unix:/tmp/kitty",\
        "kittyPid":"123"},"git":{"branch":"main","repo":"myrepo"},"tmux":{"pane":"%1","sessionName":"dev"}}
        """
        let payload = await server.decodeUnifiedPayload(body)
        #expect(payload != nil)
        #expect(payload?.agent == "opencode")
        #expect(payload?.hookInput?.sessionId == "abc")
        #expect(payload?.terminal?.kittyListenOn == "unix:/tmp/kitty")
        #expect(payload?.git?.branch == "main")
        #expect(payload?.tmux?.pane == "%1")
        #expect(payload?.tmux?.sessionName == "dev")
    }

    // Pins the payload shape the Pi `juggler-pi.ts` extension emits against the server's decoder.
    @Test func decodeUnifiedPayload_piPayload_succeeds() async {
        let server = HookServer(sessionManager: SessionManager())
        let body = """
        {"agent":"pi","event":"agent_start","hookInput":{"session_id":"pi-sess-1"},\
        "terminal":{"sessionId":"w0t0p0:xyz","cwd":"/test","terminalType":"iterm2"},\
        "git":{"branch":"main","repo":"juggler"},"tmux":{"pane":"%1"}}
        """
        let payload = await server.decodeUnifiedPayload(body)
        #expect(payload != nil)
        #expect(payload?.agent == "pi")
        #expect(payload?.event == "agent_start")
        #expect(payload?.hookInput?.sessionId == "pi-sess-1")
        #expect(payload?.terminal?.terminalType == "iterm2")
        #expect(payload?.git?.repo == "juggler")
        #expect(payload?.tmux?.pane == "%1")
    }

    @Test func decodeUnifiedPayload_invalidJSON_returnsNil() async {
        let server = HookServer(sessionManager: SessionManager())
        let payload = await server.decodeUnifiedPayload("not json")
        #expect(payload == nil)
    }

    // Pins the payload shape `codex-notify.sh` emits against the server's decoder.
    @Test func decodeUnifiedPayload_codexPayload_succeeds() async {
        let server = HookServer(sessionManager: SessionManager())
        let body = """
        {"agent":"codex","event":"PreToolUse","hookInput":{"session_id":"thread-1",\
        "transcript_path":"/tmp/rollout.jsonl","tool_name":"Bash"},\
        "terminal":{"sessionId":"w0t0p0:abc","cwd":"/test","terminalType":"iterm2"},\
        "git":{"branch":"main","repo":"juggler"},"tmux":{"pane":"%1"}}
        """
        let payload = await server.decodeUnifiedPayload(body)
        #expect(payload != nil)
        #expect(payload?.agent == "codex")
        #expect(payload?.event == "PreToolUse")
        #expect(payload?.hookInput?.sessionId == "thread-1")
        #expect(payload?.hookInput?.toolName == "Bash")
        #expect(payload?.terminal?.terminalType == "iterm2")
        #expect(payload?.git?.repo == "juggler")
        #expect(payload?.tmux?.pane == "%1")
    }

    @Test func mapClaudeCode_allEvents() {
        #expect(HookEventMapper.map(event: "SessionStart") == .updateState(.idle))
        #expect(HookEventMapper.map(event: "Stop") == .updateState(.idle))
        #expect(HookEventMapper.map(event: "PreToolUse") == .updateState(.working))
        #expect(HookEventMapper.map(event: "PostToolUse") == .updateState(.working))
        #expect(HookEventMapper.map(event: "UserPromptSubmit") == .updateState(.working))
        #expect(HookEventMapper.map(event: "PreCompact") == .updateState(.compacting))
        #expect(HookEventMapper.map(event: "PermissionRequest") == .updateState(.permission))
        #expect(HookEventMapper.map(event: "SessionEnd") == .removeSession)
    }

    // MARK: - KittyEventPayload Additional Tests

    @Test func decodeKittyEventPayload_unknownEvent() throws {
        let json = """
        {
            "event": "some_future_event",
            "window_id": "1"
        }
        """

        let payload = try JSONDecoder().decode(KittyEventPayload.self, from: Data(json.utf8))
        #expect(payload.event == "some_future_event")
        #expect(payload.windowID == "1")
    }

    // MARK: - UnifiedHookPayload terminal fields Tests

    @Test func decodePayload_allTerminalFields() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "SessionStart",
            "terminal": {
                "sessionId": "42",
                "cwd": "/home/user",
                "terminalType": "kitty",
                "kittyListenOn": "unix:/tmp/kitty.sock",
                "kittyPid": "9999"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))
        #expect(payload.terminal?.sessionId == "42")
        #expect(payload.terminal?.cwd == "/home/user")
        #expect(payload.terminal?.terminalType == "kitty")
        #expect(payload.terminal?.kittyListenOn == "unix:/tmp/kitty.sock")
        #expect(payload.terminal?.kittyPid == "9999")
    }

    @Test func decodePayload_hookInputAllFields() throws {
        let json = """
        {
            "agent": "claude-code",
            "event": "PreToolUse",
            "hookInput": {
                "session_id": "sess-001",
                "transcript_path": "/path/to/transcript.jsonl",
                "tool_name": "write_file"
            }
        }
        """

        let payload = try JSONDecoder().decode(UnifiedHookPayload.self, from: Data(json.utf8))
        #expect(payload.hookInput?.sessionId == "sess-001")
        #expect(payload.hookInput?.transcriptPath == "/path/to/transcript.jsonl")
        #expect(payload.hookInput?.toolName == "write_file")
    }

    // MARK: - processRequest error & missing-field branches

    @Test @MainActor func processRequest_postHook_missingTerminalSessionID_isDropped() async {
        // A missing terminal.sessionId has no activation address, so the event is dropped
        // and no session is created — creating one minted a phantom row that could never
        // be activated or removed. Still 200.
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func processRequest_postHook_emptyTerminalSessionID_warnsOncePerSource() async {
        LogManager.shared.clear()
        defer { LogManager.shared.clear() }
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let cwd = "/test/dedupe-\(UUID().uuidString)"
        let otherCwd = "/test/dedupe-\(UUID().uuidString)"
        func body(agent: String, event: String, cwd: String) -> String {
            """
            {"agent":"\(agent)","event":"\(event)","hookInput":{"session_id":"s-1"},\
            "terminal":{"cwd":"\(cwd)","terminalType":"iterm2"}}
            """
        }
        func post(agent: String = "claude-code", event: String, cwd: String) async -> Int {
            await server.processRequest(
                HTTPRequest(method: "POST", path: "/hook", body: body(agent: agent, event: event, cwd: cwd))
            ).status
        }
        func warnings(for cwd: String) -> [LogEntry] {
            LogManager.shared.entries.filter {
                $0.level == .warning && $0.category == .hooks && $0.message.contains(cwd)
            }
        }

        // Four different event types, so suppression is proven to span events, not just repeats.
        for event in ["SessionStart", "PreToolUse", "PostToolUse", "Stop"] {
            #expect(await post(event: event, cwd: cwd) == 200)
        }
        #expect(await post(event: "SessionStart", cwd: otherCwd) == 200)
        // Same cwd, different agent: the agent half of the dedupe key must split these.
        #expect(await post(agent: "codex", event: "SessionStart", cwd: cwd) == 200)

        #expect(warnings(for: cwd).count == 2)
        #expect(warnings(for: otherCwd).count == 1)
        #expect(warnings(for: otherCwd).first?.message.contains("remote=none") == true)
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func processRequest_postHook_emptySessionIDWithControlCharacters_isSanitized() async {
        LogManager.shared.clear()
        defer { LogManager.shared.clear() }
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let marker = UUID().uuidString
        let body = """
        {"agent":"claude-code","event":"SessionStart",\
        "terminal":{"cwd":"/test/\(marker)\\n[FORGED] [ERROR] [hooks] fake","terminalType":"iterm2"}}
        """

        #expect(await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body)).status == 200)

        let entry = LogManager.shared.entries.first { $0.message.contains(marker) }
        #expect(entry != nil)
        #expect(entry?.message.contains("\n") == false)
    }

    @Test @MainActor func processRequest_postHook_missingAgent_returns400() async {
        // Surprise: `agent` is required by the decoder (not optional), so a missing agent
        // does NOT default to "claude-code" — the payload fails to decode and returns 400.
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 400)
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func processRequest_postHook_kittyTerminalWithoutSocket_stillCreatesSession_noBridgeSideEffect()
        async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"kitty-win-1","cwd":"/test/project","terminalType":"kitty"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalType == .kitty)
        #expect(manager.sessions[0].terminalSessionID == "kitty-win-1")
    }

    @Test @MainActor func processRequest_postHook_kittyTerminalWithMalformedSocket_ignored() async {
        // Malformed socket — has "unix:" prefix but no "kitty" substring, so the bridge
        // registration guard fails. Session is still created, no crash.
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"kitty-win-2","cwd":"/test/project","terminalType":"kitty",\
        "kittyListenOn":"unix:/tmp/not-a-valid-socket"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalType == .kitty)
        #expect(manager.sessions[0].terminalSessionID == "kitty-win-2")
    }

    @Test @MainActor func processRequest_postHook_emptyHookInput_treatedAsAbsent() async {
        // hookInput: {} decodes to a non-nil HookInput with all nil fields, so claudeSessionID
        // ends up as "" — equivalent to the missing-hookInput case for session creation.
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].claudeSessionID == "")
        #expect(manager.sessions[0].terminalSessionID == "s1")
    }

    @Test @MainActor func processRequest_postHook_missingGitFields_createsSessionWithoutBranch() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].gitBranch == nil)
        #expect(manager.sessions[0].gitRepoName == nil)
    }

    @Test @MainActor func processRequest_postHook_incompleteTmuxFields_paneOnly_handledSensibly() async {
        // Only tmux.pane is present (no sessionName). Production accepts partial tmux info:
        // the pane is used to build a composite session ID "s1:%7" and sessionName stays nil.
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"},\
        "tmux":{"pane":"%7"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].tmuxPane == "%7")
        #expect(manager.sessions[0].tmuxSessionName == nil)
        #expect(manager.sessions[0].id == "s1:%7")
    }
}

/// Protocol-v1 status ingress. `/hook` is shared with the legacy `UnifiedHookPayload` route,
/// discriminated by the JSON `protocol` field, and never consults `HookEventMapper`.
@Suite("HookServer — protocol-v1 status")
struct HookServerStatusTests {
    @Test func statusPayloadDecodesProtocolOne() throws {
        let payload = try JSONDecoder().decode(
            HooklinesinkerStatus.self,
            from: Data(TestFixtures.workingStatus.utf8)
        )
        #expect(payload.protocol == 1)
        #expect(payload.phase == .working)
        #expect(payload.session.id == "native-session")
        #expect(payload.terminal?.sessionId == "terminal-session")
    }

    /// Pins every field of the wire contract this build reads, including the identity fields
    /// only diagnostics consume today — a rename on either side must fail here, not silently
    /// decode to nil.
    @Test func statusPayloadDecodesTheFullWireContract() throws {
        let body = """
        {"protocol":1,"bindingId":"b-1","agent":"codex","event":"PreToolUse","phase":"permission",\
        "running":true,"observedAt":"2026-09-04T12:00:00Z",\
        "session":{"id":"thread-1","cwd":"/work/repo","transcriptPath":"/tmp/t.jsonl"},\
        "process":{"pid":4242,"startedAt":"2026-09-04T11:00:00Z","host":"test-host"},\
        "terminal":{"sessionId":"s1","terminalType":"kitty","kittyListenOn":"unix:/tmp/kitty-1",\
        "kittyPid":"12345"},"tmux":{"pane":"%1","sessionName":"dev"},\
        "git":{"branch":"main","repo":"juggler"},"remoteHost":"build-box"}
        """
        let payload = try JSONDecoder().decode(HooklinesinkerStatus.self, from: Data(body.utf8))

        #expect(payload.bindingId == "b-1")
        #expect(payload.agent == "codex")
        #expect(payload.event == "PreToolUse")
        #expect(payload.phase == .permission)
        #expect(payload.running)
        #expect(payload.observedAt == "2026-09-04T12:00:00Z")
        #expect(payload.session.transcriptPath == "/tmp/t.jsonl")
        #expect(payload.process?.pid == 4242)
        #expect(payload.process?.startedAt == "2026-09-04T11:00:00Z")
        #expect(payload.process?.host == "test-host")
        #expect(payload.terminal?.kittyListenOn == "unix:/tmp/kitty-1")
        #expect(payload.terminal?.kittyPid == "12345")
        #expect(payload.tmux?.sessionName == "dev")
        #expect(payload.git?.branch == "main")
        #expect(payload.git?.repo == "juggler")
        #expect(payload.remoteHost == "build-box")
        #expect(payload.compositeSessionID == "s1:%1")
        #expect(payload.resolvedTerminalType == .kitty)
    }

    @Test func statusPayloadCarriesCwdOnSessionNotTerminal() throws {
        let payload = try JSONDecoder().decode(
            HooklinesinkerStatus.self,
            from: Data(TestFixtures.statusJSON(cwd: "/work/repo").utf8)
        )
        #expect(payload.session.cwd == "/work/repo")
    }

    @Test func unknownPhaseSpellingDecodesAsUnknown() throws {
        let payload = try JSONDecoder().decode(
            HooklinesinkerStatus.self,
            from: Data(TestFixtures.statusJSON(phase: "hibernating").utf8)
        )
        #expect(payload.phase == .unknown)
        #expect(payload.phase.sessionState == nil)
    }

    @Test func legacyPayloadIsNotMistakenForStatus() async {
        let server = HookServer(sessionManager: SessionManager())
        let legacy = """
        {"agent":"claude-code","event":"SessionStart","hookInput":{"session_id":"claude-1"},\
        "terminal":{"sessionId":"s1","cwd":"/test/project","terminalType":"iterm2"}}
        """
        #expect(await server.decodeStatusPayload(legacy) == nil)
        #expect(await server.decodeUnifiedPayload(legacy) != nil)
    }

    @Test func statusPayloadRoutesToStatusActionNotLegacyHook() async {
        let server = HookServer(sessionManager: SessionManager())
        let routed = await server.routeRequest(
            HTTPRequest(method: "POST", path: "/hook", body: TestFixtures.workingStatus)
        )

        #expect(routed.response.status == 200)
        if case .status = routed.action {
            // Reached the v1 handler.
        } else {
            Issue.record("protocol-v1 body routed to \(routed.action) instead of .status")
        }
    }

    @Test(arguments: ["2", "null", "true", "\"1\""])
    @MainActor func unsupportedStatusProtocolLeavesExistingSessionUnchanged(protocolValue: String) async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        _ = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: TestFixtures.workingStatus))
        let body = TestFixtures.statusJSON(agent: "codex", event: "Stop")
            .replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":\(protocolValue)")

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 400)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == .working)
        #expect(manager.sessions[0].claudeSessionID == "native-session")
        #expect(manager.sessions[0].projectPath == "/test/project")
    }

    @Test @MainActor func malformedStatusCannotFallBackToLegacyHook() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = """
        {"protocol":1,"agent":"codex","event":"Stop",\
        "terminal":{"sessionId":"s1","cwd":"/test/project"}}
        """

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 400)
        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func statusCreatesSessionWithCompositeIdentity() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let body = TestFixtures.statusJSON(
            phase: "working",
            terminalSessionID: "s1",
            tmuxPane: "%1",
            tmuxSessionName: "dev",
            gitBranch: "main",
            gitRepo: "juggler"
        )

        let response = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))

        #expect(response.status == 200)
        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "s1:%1")
        #expect(manager.sessions[0].terminalSessionID == "s1")
        #expect(manager.sessions[0].tmuxPane == "%1")
        #expect(manager.sessions[0].tmuxSessionName == "dev")
        #expect(manager.sessions[0].claudeSessionID == "native-session")
        #expect(manager.sessions[0].projectPath == "/test/project")
        #expect(manager.sessions[0].gitBranch == "main")
        #expect(manager.sessions[0].gitRepoName == "juggler")
        #expect(manager.sessions[0].state == .working)
    }

    @Test @MainActor func claudeAgentKeepsJugglersOwnSpelling() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await server.handleStatusForTesting(TestFixtures.statusJSON(agent: "claude"))

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].agent == "claude-code")
        #expect(manager.sessions[0].agentShortName == "CC")
    }

    @Test(arguments: [
        ("droid", "DR"),
        ("qwen", "QW"),
        ("kimi", "KM")
    ])
    @MainActor
    func newAgentsPassThroughUnchanged(wireAgent: String, shortName: String) async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await server.handleStatusForTesting(TestFixtures.statusJSON(agent: wireAgent))

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].agent == wireAgent)
        #expect(manager.sessions[0].agentShortName == shortName)
    }

    @Test(arguments: [
        ("idle", SessionState.idle),
        ("working", SessionState.working),
        ("permission", SessionState.permission),
        ("compacting", SessionState.compacting)
    ])
    @MainActor
    func everyPhaseMapsDirectlyToASessionState(phase: String, expected: SessionState) async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await server.handleStatusForTesting(TestFixtures.statusJSON(phase: phase))

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == expected)
    }

    @Test @MainActor func unknownPhaseDoesNotCycleAnExistingSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(TestFixtures.statusJSON(phase: "working"))

        await server.handleStatusForTesting(TestFixtures.statusJSON(event: "Odd", phase: "hibernating"))

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == .working)
    }

    @Test @MainActor func endedStatusRemovesExistingSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(TestFixtures.workingStatus)
        #expect(manager.sessions.count == 1)

        await server.handleStatusForTesting(TestFixtures.endedStatus)

        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func endedStatusFromASupersededThreadLeavesTheLiveRow() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(
            TestFixtures.statusJSON(bindingId: "b-new", sessionID: "thread-2", terminalSessionID: "s1")
        )

        await server.handleStatusForTesting(
            TestFixtures.statusJSON(
                bindingId: "b-old",
                event: "SessionEnd",
                running: false,
                sessionID: "thread-1",
                terminalSessionID: "s1"
            )
        )

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].claudeSessionID == "thread-2")
    }

    @Test @MainActor func statusWithoutATerminalSessionIDIsDropped() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await server.handleStatusForTesting(TestFixtures.statusJSON(terminalSessionID: nil))

        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func kittyTerminalTypeSurvivesTheRoundTrip() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)

        await server.handleStatusForTesting(
            TestFixtures.statusJSON(terminalSessionID: "kitty-window", terminalType: "kitty")
        )

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].terminalType == .kitty)
    }

    // MARK: - Hydration

    @Test @MainActor func hydrationRestoresRunningSessions() async throws {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let statuses = try Self.decodeAll([
            TestFixtures.statusJSON(bindingId: "b1", phase: "idle", terminalSessionID: "s1"),
            TestFixtures.statusJSON(bindingId: "b2", phase: "working", terminalSessionID: "s2")
        ])

        await server.hydrate(statuses)

        #expect(manager.sessions.count == 2)
        #expect(manager.sessions.contains { $0.id == "s1" && $0.state == .idle })
        #expect(manager.sessions.contains { $0.id == "s2" && $0.state == .working })
    }

    @Test @MainActor func hydrationKeepsBothTerminalBindingsOfOneNativeSession() async throws {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        // One agent session (`native-session`) attached to two panes: distinct bindings,
        // distinct composite ids, two rows.
        let statuses = try Self.decodeAll([
            TestFixtures.statusJSON(
                bindingId: "b1", sessionID: "native-session", terminalSessionID: "s1", tmuxPane: "%1"
            ),
            TestFixtures.statusJSON(
                bindingId: "b2", sessionID: "native-session", terminalSessionID: "s1", tmuxPane: "%2"
            )
        ])

        await server.hydrate(statuses)

        #expect(manager.sessions.count == 2)
        #expect(manager.sessions.map(\.id).sorted() == ["s1:%1", "s1:%2"])
    }

    @Test @MainActor func hydrationSkipsBindingsAlreadySeenLive() async throws {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        // The live event wins the race and reports `working`.
        await server.handleStatusForTesting(
            TestFixtures.statusJSON(bindingId: "b1", phase: "working", terminalSessionID: "s1")
        )
        // The stored snapshot for the same binding is older and says `idle`.
        let stale = try Self.decodeAll([
            TestFixtures.statusJSON(bindingId: "b1", phase: "idle", terminalSessionID: "s1")
        ])

        await server.hydrate(stale)

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].state == .working)
    }

    // The snapshot is read once at startup; a session that ends between the read and the replay
    // must not be resurrected by its own stale record.
    @Test @MainActor func hydrationSkipsBindingsThatEndedLiveAfterTheSnapshot() async throws {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let snapshot = try Self.decodeAll([
            TestFixtures.statusJSON(bindingId: "b1", phase: "working", terminalSessionID: "s1")
        ])
        await server.handleStatusForTesting(TestFixtures.statusJSON(
            bindingId: "b1", event: "SessionEnd", running: false, terminalSessionID: "s1"
        ))

        await server.hydrate(snapshot)

        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func hydrationIgnoresRecordsThatAreNoLongerRunning() async throws {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        let statuses = try Self.decodeAll([
            TestFixtures.statusJSON(bindingId: "b1", running: false, terminalSessionID: "s1")
        ])

        await server.hydrate(statuses)

        #expect(manager.sessions.isEmpty)
    }

    private static func decodeAll(_ bodies: [String]) throws -> [HooklinesinkerStatus] {
        try bodies.map { try JSONDecoder().decode(HooklinesinkerStatus.self, from: Data($0.utf8)) }
    }
}
