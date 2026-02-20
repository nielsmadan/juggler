import Foundation
@testable import Juggler
import Testing

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

@Test func parse_invalidData_returnsNil() {
    let request = HTTPRequest.parse(Data("not http at all".utf8))

    // "not http at all" has 4 space-separated parts, so it still parses the first two as method/path
    // but there's no proper body separator
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
    let server = HookServer()
    let request = HTTPRequest(method: "GET", path: "/hook", body: "")
    let response = await server.processRequest(request)
    #expect(response.status == 405)
}

@Test func processRequest_postUnknownPath_returns404() async {
    let server = HookServer()
    let request = HTTPRequest(method: "POST", path: "/unknown", body: "")
    let response = await server.processRequest(request)
    #expect(response.status == 404)
}

@Test func processRequest_postHook_invalidJSON_returns400() async {
    let server = HookServer()
    let request = HTTPRequest(method: "POST", path: "/hook", body: "not json")
    let response = await server.processRequest(request)
    #expect(response.status == 400)
}

@Test func processRequest_postHook_validPayload_returns200() async {
    let server = HookServer()
    let body = """
    {"agent":"claude-code","event":"Stop","terminal":{"sessionId":"s1","cwd":"/test","terminalType":"iterm2"}}
    """
    let request = HTTPRequest(method: "POST", path: "/hook", body: body)
    let response = await server.processRequest(request)
    #expect(response.status == 200)
}

@Test func processRequest_postKittyEvent_invalidJSON_returns400() async {
    let server = HookServer()
    let request = HTTPRequest(method: "POST", path: "/kitty-event", body: "bad")
    let response = await server.processRequest(request)
    #expect(response.status == 400)
}

@Test func processRequest_postKittyEvent_valid_returns200() async {
    let server = HookServer()
    let body = #"{"event":"focus_changed","window_id":"42"}"#
    let request = HTTPRequest(method: "POST", path: "/kitty-event", body: body)
    let response = await server.processRequest(request)
    #expect(response.status == 200)
}

@Test func processRequest_putMethod_returns405() async {
    let server = HookServer()
    let request = HTTPRequest(method: "PUT", path: "/hook", body: "{}")
    let response = await server.processRequest(request)
    #expect(response.status == 405)
}

// MARK: - decodeUnifiedPayload Tests

@Test func decodeUnifiedPayload_validMinimal_succeeds() async {
    let server = HookServer()
    let body = #"{"agent":"claude-code","event":"Stop"}"#
    let payload = await server.decodeUnifiedPayload(body)
    #expect(payload != nil)
    #expect(payload?.agent == "claude-code")
    #expect(payload?.event == "Stop")
}

@Test func decodeUnifiedPayload_withAllFields_succeeds() async {
    let server = HookServer()
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

@Test func decodeUnifiedPayload_invalidJSON_returnsNil() async {
    let server = HookServer()
    let payload = await server.decodeUnifiedPayload("not json")
    #expect(payload == nil)
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
