import Foundation
@testable import Juggler
import Testing

private enum MockRegistryError: Error, Equatable, Sendable {
    case startFailed
}

// MARK: - TerminalBridgeRegistry Tests

/// A minimal mock bridge for testing registry behavior
private actor MockBridge: TerminalBridge {
    var started = false
    var stopped = false
    var startError: MockRegistryError?

    func start() async throws {
        if let startError {
            throw startError
        }
        started = true
    }

    func stop() async {
        stopped = true
    }

    func activate(sessionID _: String) async throws {}
    func highlight(sessionID _: String, tabConfig _: HighlightConfig?, paneConfig _: HighlightConfig?) async throws {}
    func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? { nil }

    func setStartError(_ error: MockRegistryError?) {
        startError = error
    }

    func didStart() -> Bool {
        started
    }

    func didStop() -> Bool {
        stopped
    }
}

@Test func registry_registerAndLookup() async {
    let registry = TerminalBridgeRegistry()
    let mock = MockBridge()

    await registry.register(mock, for: .kitty)
    let bridge = await registry.bridge(for: .kitty)

    #expect(bridge != nil)
}

@Test func registry_missingBridge_returnsNil() async {
    let registry = TerminalBridgeRegistry()

    let bridge = await registry.bridge(for: .ghostty)

    #expect(bridge == nil)
}

@Test func registry_start_registeredBridge_callsStart() async throws {
    let registry = TerminalBridgeRegistry()
    let mock = MockBridge()

    await registry.register(mock, for: .kitty)
    try await registry.start(.kitty)

    let started = await mock.didStart()
    #expect(started == true)
}

@Test func registry_start_missingBridge_isNoOp() async throws {
    let registry = TerminalBridgeRegistry()

    try await registry.start(.wezterm)

    let bridge = await registry.bridge(for: .wezterm)
    #expect(bridge == nil)
}

@Test func registry_start_bridgeError_propagates() async {
    let registry = TerminalBridgeRegistry()
    let mock = MockBridge()
    await mock.setStartError(.startFailed)
    await registry.register(mock, for: .kitty)

    do {
        try await registry.start(.kitty)
        Issue.record("Expected start(.kitty) to throw")
    } catch let error as MockRegistryError {
        #expect(error == .startFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let started = await mock.didStart()
    #expect(started == false)
}

@Test func registry_stopAll_stopsRegisteredBridges() async {
    let registry = TerminalBridgeRegistry()
    let kitty = MockBridge()
    let iterm = MockBridge()

    await registry.register(kitty, for: .kitty)
    await registry.register(iterm, for: .iterm2)
    await registry.stopAll()

    let kittyStopped = await kitty.didStop()
    let itermStopped = await iterm.didStop()
    #expect(kittyStopped == true)
    #expect(itermStopped == true)
}
