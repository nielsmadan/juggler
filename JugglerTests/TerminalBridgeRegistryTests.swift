import Foundation
@testable import Juggler
import Testing

// MARK: - TerminalBridgeRegistry Tests

/// A minimal mock bridge for testing registry behavior
private actor MockBridge: TerminalBridge {
    var started = false
    var stopped = false

    func start() async throws {
        started = true
    }

    func stop() async {
        stopped = true
    }

    func activate(sessionID _: String) async throws {}
    func highlight(sessionID _: String, tabConfig _: HighlightConfig?, paneConfig _: HighlightConfig?) async throws {}
    func resetHighlight(sessionID _: String) async throws {}
    func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? { nil }
}

@Test func registry_registerAndLookup() async {
    let registry = TerminalBridgeRegistry.shared
    let mock = MockBridge()

    await registry.register(mock, for: .kitty)
    let bridge = await registry.bridge(for: .kitty)

    #expect(bridge != nil)
}

@Test func registry_missingBridge_returnsNil() async {
    let registry = TerminalBridgeRegistry.shared

    let bridge = await registry.bridge(for: .ghostty)

    #expect(bridge == nil)
}
