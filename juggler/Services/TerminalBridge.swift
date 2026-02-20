//
//  TerminalBridge.swift
//  Juggler
//

import Foundation
import SwiftUI

protocol TerminalBridge: Sendable {
    func start() async throws
    func stop() async
    func activate(sessionID: String) async throws
    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws
    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo?
}

struct HighlightConfig: Codable, Sendable {
    let enabled: Bool
    let color: [Int]
    let duration: TimeInterval
}

struct TerminalSessionInfo: Sendable {
    let id: String
    let tabName: String
    let windowName: String
    let tabIndex: Int
    let paneIndex: Int
    let paneCount: Int
    let isActive: Bool
}

enum ActivationTrigger {
    case hotkey
    case guiSelect
    case notification
}

enum TerminalActivation {
    static func activate(session: Session, trigger: ActivationTrigger) async throws {
        guard let bridge = await TerminalBridgeRegistry.shared.bridge(for: session.terminalType) else {
            throw TerminalBridgeError.bridgeNotAvailable(session.terminalType)
        }
        do {
            try await bridge.activate(sessionID: session.terminalSessionID)
        } catch let error as TerminalBridgeError {
            if case let .commandFailed(message) = error,
               message.localizedCaseInsensitiveContains("session not found")
            {
                await MainActor.run {
                    SessionManager.shared.removeSession(sessionID: session.id)
                }
                throw TerminalBridgeError.sessionNotFound(session.id)
            }
            throw error
        }
        if let tmuxPane = session.tmuxPane {
            selectTmuxPane(tmuxPane)
        }
        guard shouldHighlight(for: trigger) else { return }
        try await bridge.highlight(
            sessionID: session.terminalSessionID,
            tabConfig: tabHighlightConfig(for: session),
            paneConfig: paneHighlightConfig(for: session)
        )
    }

    private static func shouldHighlight(for trigger: ActivationTrigger) -> Bool {
        switch trigger {
        case .hotkey: UserDefaults.standard.bool(forKey: AppStorageKeys.highlightOnHotkey)
        case .guiSelect: UserDefaults.standard.bool(forKey: AppStorageKeys.highlightOnGuiSelect)
        case .notification: UserDefaults.standard.bool(forKey: AppStorageKeys.highlightOnNotification)
        }
    }

    private static func sessionColorIndex(for session: Session) -> Int {
        let idx = SessionManager.shared.sessions.firstIndex(where: { $0.id == session.id }) ?? 0
        return idx % CyclingColors.paletteRGB.count
    }

    private static func tabHighlightConfig(for session: Session) -> HighlightConfig? {
        buildTabHighlightConfig(
            enabled: UserDefaults.standard.bool(forKey: AppStorageKeys.tabHighlightEnabled),
            useCycling: UserDefaults.standard.bool(forKey: AppStorageKeys.useTerminalCyclingColors),
            colorIndex: sessionColorIndex(for: session),
            customColor: [
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorRed)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorGreen)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorBlue)),
            ],
            duration: UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightDuration)
        )
    }

    private static func paneHighlightConfig(for session: Session) -> HighlightConfig? {
        buildPaneHighlightConfig(
            enabled: UserDefaults.standard.bool(forKey: AppStorageKeys.paneHighlightEnabled),
            useCycling: UserDefaults.standard.bool(forKey: AppStorageKeys.useTerminalCyclingColors),
            colorIndex: sessionColorIndex(for: session),
            customColor: [
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorRed)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorGreen)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorBlue)),
            ],
            duration: UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightDuration)
        )
    }

    static func buildTabHighlightConfig(
        enabled: Bool,
        useCycling: Bool,
        colorIndex: Int,
        customColor: [Int],
        duration: Double
    ) -> HighlightConfig? {
        guard enabled else { return nil }
        let color = useCycling ? CyclingColors.paletteRGB[colorIndex % CyclingColors.paletteRGB.count] : customColor
        return HighlightConfig(enabled: true, color: color, duration: duration > 0 ? duration : 2.0)
    }

    static func buildPaneHighlightConfig(
        enabled: Bool,
        useCycling: Bool,
        colorIndex: Int,
        customColor: [Int],
        duration: Double
    ) -> HighlightConfig? {
        guard enabled else { return nil }
        let color = useCycling
            ? CyclingColors.darkPaletteRGB[colorIndex % CyclingColors.darkPaletteRGB.count] : customColor
        return HighlightConfig(enabled: true, color: color, duration: duration > 0 ? duration : 1.0)
    }

    private static func selectTmuxPane(_ pane: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "select-pane", "-t", pane]
        try? process.run()
        process.waitUntilExit()
    }
}

enum TerminalBridgeError: Error, LocalizedError {
    case daemonNotRunning
    case connectionFailed
    case connectionTimeout
    case commandTimeout
    case commandFailed(String)
    case invalidResponse
    case authenticationFailed(String)
    case sessionNotFound(String)
    case bridgeNotAvailable(TerminalType)

    var errorDescription: String? {
        switch self {
        case .daemonNotRunning:
            "Terminal daemon is not running"
        case .connectionFailed:
            "Failed to connect to terminal daemon"
        case .connectionTimeout:
            "Connection to daemon timed out"
        case .commandTimeout:
            "Command timed out"
        case let .commandFailed(message):
            "Command failed: \(message)"
        case .invalidResponse:
            "Invalid response from daemon"
        case let .authenticationFailed(message):
            "Authentication failed: \(message)"
        case let .sessionNotFound(sessionID):
            "Session not found: \(sessionID)"
        case let .bridgeNotAvailable(terminalType):
            "No bridge available for \(terminalType.displayName)"
        }
    }
}
