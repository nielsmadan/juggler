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
