//
//  ITerm2BridgeTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

// MARK: - DaemonRequest Encoding Tests

@Test func daemonRequest_encodesPingCommand() throws {
    let request = DaemonRequest(command: "ping")
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["command"] as? String == "ping")
    #expect(json?["session_id"] == nil)
}

@Test func daemonRequest_encodesActivateWithSessionID() throws {
    let request = DaemonRequest(command: "activate", sessionID: "w0t0p0:abc")
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["command"] as? String == "activate")
    #expect(json?["session_id"] as? String == "w0t0p0:abc")
}

@Test func daemonRequest_encodesHighlightWithConfigs() throws {
    let tab = HighlightConfig(enabled: true, color: [255, 0, 0], duration: 2.0)
    let request = DaemonRequest(command: "highlight", sessionID: "s1", tab: tab)
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["tab"] != nil)
}

// MARK: - DaemonResponse Decoding Tests

@Test func daemonResponse_decodesOkStatus() throws {
    let json = #"{"status":"ok"}"#
    let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
    #expect(response.status == "ok")
    #expect(response.message == nil)
}

@Test func daemonResponse_decodesErrorWithMessage() throws {
    let json = #"{"status":"error","message":"not found"}"#
    let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
    #expect(response.status == "error")
    #expect(response.message == "not found")
}

@Test func daemonResponse_decodesSessionInfo() throws {
    let json = #"{"status":"ok","tab_name":"Tab 1","window_name":"Window","pane_index":0,"pane_count":2}"#
    let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
    #expect(response.tabName == "Tab 1")
    #expect(response.windowName == "Window")
    #expect(response.paneIndex == 0)
    #expect(response.paneCount == 2)
}

// MARK: - DaemonEvent Decoding Tests

@Test func daemonEvent_decodesFocusChanged() throws {
    let json = #"{"event":"focus_changed","session_id":"w0t0p0:abc"}"#
    let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    #expect(event.event == "focus_changed")
    #expect(event.sessionID == "w0t0p0:abc")
}

@Test func daemonEvent_decodesTerminalInfo() throws {
    let json =
        #"{"event":"terminal_info","session_id":"s1","tab_name":"Tab","window_name":"Win","pane_index":1,"pane_count":3}"#
    let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    #expect(event.event == "terminal_info")
    #expect(event.tabName == "Tab")
    #expect(event.windowName == "Win")
    #expect(event.paneIndex == 1)
    #expect(event.paneCount == 3)
}

@Test func daemonEvent_decodesMinimalEvent() throws {
    let json = #"{"event":"session_terminated"}"#
    let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    #expect(event.event == "session_terminated")
    #expect(event.sessionID == nil)
}

// MARK: - shouldAttemptRecovery Tests

@Test func shouldAttemptRecovery_daemonNotRunning_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.daemonNotRunning)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_connectionFailed_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.connectionFailed)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_commandTimeout_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.commandTimeout)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_invalidResponse_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.invalidResponse)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_commandFailed_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.commandFailed("test"))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_authFailed_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.authenticationFailed("test"))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_sessionNotFound_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.sessionNotFound("s1"))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_bridgeNotAvailable_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.bridgeNotAvailable(.iterm2))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_ioError_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let error = NSError(domain: "test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Input/output error"])
    let result = await bridge.shouldAttemptRecovery(error)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_brokenPipe_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let error = NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Broken pipe"])
    let result = await bridge.shouldAttemptRecovery(error)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_randomError_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let error = NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something else"])
    let result = await bridge.shouldAttemptRecovery(error)
    #expect(result == false)
}
