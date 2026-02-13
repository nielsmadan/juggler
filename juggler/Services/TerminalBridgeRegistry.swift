//
//  TerminalBridgeRegistry.swift
//  Juggler
//

import Foundation

actor TerminalBridgeRegistry {
    static let shared = TerminalBridgeRegistry()

    private var bridges: [TerminalType: any TerminalBridge] = [:]

    private init() {}

    func register(_ bridge: any TerminalBridge, for type: TerminalType) {
        bridges[type] = bridge
    }

    func bridge(for type: TerminalType) -> (any TerminalBridge)? {
        bridges[type]
    }

    func startAll() async {
        for (type, bridge) in bridges {
            do {
                try await bridge.start()
            } catch {
                await MainActor.run {
                    logWarning(.session, "Failed to start \(type.displayName) bridge: \(error)")
                }
            }
        }
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

    func stop(_ type: TerminalType) async {
        guard let bridge = bridges[type] else { return }
        await bridge.stop()
    }
}
