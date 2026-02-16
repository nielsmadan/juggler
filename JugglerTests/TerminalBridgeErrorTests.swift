import Foundation
@testable import Juggler
import Testing

@Test func terminalBridgeError_daemonNotRunning() {
    let error = TerminalBridgeError.daemonNotRunning
    #expect(error.errorDescription == "Terminal daemon is not running")
}

@Test func terminalBridgeError_connectionFailed() {
    let error = TerminalBridgeError.connectionFailed
    #expect(error.errorDescription == "Failed to connect to terminal daemon")
}

@Test func terminalBridgeError_connectionTimeout() {
    let error = TerminalBridgeError.connectionTimeout
    #expect(error.errorDescription == "Connection to daemon timed out")
}

@Test func terminalBridgeError_commandTimeout() {
    let error = TerminalBridgeError.commandTimeout
    #expect(error.errorDescription == "Command timed out")
}

@Test func terminalBridgeError_commandFailed() {
    let error = TerminalBridgeError.commandFailed("something broke")
    #expect(error.errorDescription == "Command failed: something broke")
}

@Test func terminalBridgeError_invalidResponse() {
    let error = TerminalBridgeError.invalidResponse
    #expect(error.errorDescription == "Invalid response from daemon")
}

@Test func terminalBridgeError_authenticationFailed() {
    let error = TerminalBridgeError.authenticationFailed("bad token")
    #expect(error.errorDescription == "Authentication failed: bad token")
}

@Test func terminalBridgeError_sessionNotFound() {
    let error = TerminalBridgeError.sessionNotFound("sess-123")
    #expect(error.errorDescription == "Session not found: sess-123")
}

@Test func terminalBridgeError_bridgeNotAvailable() {
    let error = TerminalBridgeError.bridgeNotAvailable(.kitty)
    #expect(error.errorDescription == "No bridge available for Kitty")
}
