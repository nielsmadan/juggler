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
    func resetHighlight(sessionID: String) async throws
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
    let windowIndex: Int
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
        try await ITerm2Bridge.shared.activate(sessionID: session.terminalSessionID)
        if let tmuxPane = session.tmuxPane {
            selectTmuxPane(tmuxPane)
        }
        guard shouldHighlight(for: trigger) else { return }
        try await ITerm2Bridge.shared.highlight(
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
        let enabled = UserDefaults.standard.bool(forKey: AppStorageKeys.tabHighlightEnabled)
        guard enabled else { return nil }

        let duration = UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightDuration)
        let useCycling = UserDefaults.standard.bool(forKey: AppStorageKeys.useTerminalCyclingColors)

        let color: [Int] = if useCycling {
            CyclingColors.paletteRGB[sessionColorIndex(for: session)]
        } else {
            [
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorRed)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorGreen)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorBlue))
            ]
        }
        return HighlightConfig(enabled: true, color: color, duration: duration > 0 ? duration : 2.0)
    }

    private static func paneHighlightConfig(for session: Session) -> HighlightConfig? {
        let enabled = UserDefaults.standard.bool(forKey: AppStorageKeys.paneHighlightEnabled)
        guard enabled else { return nil }

        let duration = UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightDuration)
        let useCycling = UserDefaults.standard.bool(forKey: AppStorageKeys.useTerminalCyclingColors)

        let color: [Int] = if useCycling {
            CyclingColors.darkPaletteRGB[sessionColorIndex(for: session)]
        } else {
            [
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorRed)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorGreen)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorBlue))
            ]
        }
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
        }
    }
}
