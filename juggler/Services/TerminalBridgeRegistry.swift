//
//  TerminalBridgeRegistry.swift
//  Juggler
//

import Foundation

actor TerminalBridgeRegistry {
    static let shared = TerminalBridgeRegistry()

    private var bridges: [TerminalType: any TerminalBridge] = [:]

    init() {}

    func register(_ bridge: any TerminalBridge, for type: TerminalType) {
        bridges[type] = bridge
    }

    func bridge(for type: TerminalType) -> (any TerminalBridge)? {
        bridges[type]
    }

    func stopAll() async {
        for (_, bridge) in bridges {
            await bridge.stop()
        }
    }

    func start(_ type: TerminalType) async throws {
        guard let bridge = bridges[type] else { return }
        try await bridge.start()
    }
}
