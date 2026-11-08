//
//  TerminalBridgeRegistry.swift
//  Juggler
//

import Foundation

actor TerminalBridgeRegistry {
    static let shared = TerminalBridgeRegistry()

    private var bridges: [TerminalType: any TerminalBridge] = [:]
    private let beforeLookup: (@Sendable () async -> Void)?

    init(beforeLookup: (@Sendable () async -> Void)? = nil) {
        self.beforeLookup = beforeLookup
    }

    func register(_ bridge: any TerminalBridge, for type: TerminalType) {
        bridges[type] = bridge
    }

    func bridge(for type: TerminalType) async -> (any TerminalBridge)? {
        await beforeLookup?()
        return bridges[type]
    }

    func stopAll() async {
        for (_, bridge) in bridges {
            await bridge.stop()
        }
    }

    func start(_ type: TerminalType) async throws {
        guard let bridge = bridges[type] else {
            await MainActor.run {
                logWarning(.daemon, "start() called for '\(type.displayName)' but no bridge registered")
            }
            return
        }
        do {
            try await bridge.start()
        } catch {
            await MainActor.run {
                logError(.daemon, "Failed to start bridge for '\(type.displayName)': \(error)")
            }
            throw error
        }
    }
}
