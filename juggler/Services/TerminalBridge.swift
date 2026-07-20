//
//  TerminalBridge.swift
//  Juggler
//

import Foundation
import SwiftUI

/// Context a bridge needs to set up local addressing for a session from a hook event.
/// `listenSocket` is the hook-supplied control socket (kitty's `KITTY_LISTEN_ON`; nil for
/// terminals that don't use one). `isRemote` is true when the session runs over ssh, in
/// which case any hook-supplied socket points at the remote host and is unusable locally.
struct HookAddressingContext: Sendable {
    let isRemote: Bool
    let listenSocket: String?
}

protocol TerminalBridge: Sendable {
    func start() async throws
    func stop() async
    func activate(sessionID: String) async throws
    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws
    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo?

    /// Register any local addressing state (e.g. a control socket) a hook event implies,
    /// so a later `activate` can reach the session. Terminals that address sessions
    /// directly (iTerm2 by pane UUID) don't need this — hence the no-op default.
    func prepareAddressing(sessionID: String, context: HookAddressingContext) async
}

extension TerminalBridge {
    func prepareAddressing(sessionID _: String, context _: HookAddressingContext) async {}
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
    static func activate(
        session: Session,
        trigger: ActivationTrigger,
        sessionManager: SessionManager = .shared,
        registry: TerminalBridgeRegistry = .shared
    ) async throws {
        // A remote tmux session's terminalSessionID is stale (tmux caches ITERM_SESSION_ID
        // in its environment), so once we've learned the live local pane hosting it we
        // address that instead. Falls back to terminalSessionID for every other session
        // (and treats an empty binding as absent, so it can never mask a good id).
        let activationID = session.liveHostPaneID.flatMap { $0.isEmpty ? nil : $0 }
            ?? session.terminalSessionID

        // No activation address means the session can never be reached by any bridge.
        // Remove it rather than letting an empty id route into the iTerm2 daemon (which
        // asserts). This also self-heals any phantom row created before this guard existed.
        guard !activationID.isEmpty else {
            await MainActor.run {
                logWarning(.session, "Session '\(session.id)' has no terminal session ID, removing")
                sessionManager.removeSession(sessionID: session.id)
            }
            throw TerminalBridgeError.sessionNotFound(session.id)
        }
        guard let bridge = await registry.bridge(for: session.terminalType) else {
            await MainActor.run {
                logError(.session, "No bridge available for \(session.terminalType.displayName)")
            }
            throw TerminalBridgeError.bridgeNotAvailable(session.terminalType)
        }
        do {
            try await bridge.activate(sessionID: activationID)
        } catch let error as TerminalBridgeError {
            if case let .commandFailed(message) = error,
               await isSessionGone(bridge: bridge, activationID: activationID, message: message) {
                await MainActor.run {
                    logWarning(.session, "Session '\(session.id)' not found in terminal, removing")
                    sessionManager.removeSession(sessionID: session.id)
                }
                throw TerminalBridgeError.sessionNotFound(session.id)
            }
            throw error
        }
        // Local tmux only: the `tmux` client runs on this Mac. For a remote tmux session
        // (over ssh) the pane id belongs to the remote server, so a local select-pane
        // would target the wrong tmux — skip it.
        if let tmuxPane = session.tmuxPane, shouldRunLocalTmuxSelect(for: session) {
            await selectTmuxPane(tmuxPane)
        }
        guard shouldHighlight(for: trigger) else { return }
        try await bridge.highlight(
            sessionID: activationID,
            tabConfig: tabHighlightConfig(for: session),
            paneConfig: paneHighlightConfig(for: session)
        )
    }

    /// Whether a local `tmux select-pane` is meaningful for this session: only for local
    /// tmux, never for a remote (ssh) tmux whose pane lives on another host.
    static func shouldRunLocalTmuxSelect(for session: Session) -> Bool {
        session.tmuxPane != nil && (session.remoteHost?.isEmpty ?? true)
    }

    private static func isSessionGone(bridge: TerminalBridge, activationID: String, message: String) async -> Bool {
        if message.localizedCaseInsensitiveContains("session not found") {
            return true
        }
        do {
            return try await bridge.getSessionInfo(sessionID: activationID) == nil
        } catch {
            return false
        }
    }

    private static func shouldHighlight(for trigger: ActivationTrigger) -> Bool {
        switch trigger {
        case .hotkey: UserDefaults.standard.bool(forKey: AppStorageKeys.highlightOnHotkey)
        case .guiSelect: UserDefaults.standard.bool(forKey: AppStorageKeys.highlightOnGuiSelect)
        case .notification: UserDefaults.standard.bool(forKey: AppStorageKeys.highlightOnNotification)
        }
    }

    private static func sessionColorIndex(for _: Session) -> Int {
        SessionManager.shared.activeColorIndex
    }

    private static func tabHighlightConfig(for session: Session) -> HighlightConfig? {
        buildTabHighlightConfig(
            enabled: UserDefaults.standard.bool(forKey: AppStorageKeys.tabHighlightEnabled),
            useCycling: UserDefaults.standard.bool(forKey: AppStorageKeys.useTerminalCyclingColors),
            colorIndex: sessionColorIndex(for: session),
            customColor: [
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorRed)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorGreen)),
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.tabHighlightColorBlue))
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
                Int(UserDefaults.standard.double(forKey: AppStorageKeys.paneHighlightColorBlue))
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

    private static func selectTmuxPane(_ pane: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "select-pane", "-t", pane]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                await MainActor.run {
                    logWarning(
                        .session,
                        "tmux select-pane failed for '\(pane)' with status \(process.terminationStatus)"
                    )
                }
            }
        } catch {
            await MainActor.run {
                logWarning(.session, "tmux select-pane failed for '\(pane)': \(error)")
            }
        }
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
