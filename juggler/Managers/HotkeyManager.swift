//
//  HotkeyManager.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Foundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let cycleForward = Self("cycleForward", default: .init(.k, modifiers: [.command, .shift]))
    static let cycleBackward = Self("cycleBackward", default: .init(.j, modifiers: [.command, .shift]))
    static let backburner = Self("backburner", default: .init(.l, modifiers: [.command, .shift]))
    static let reactivateAll = Self("reactivateAll", default: .init(.h, modifiers: [.command, .shift]))
    static let showMonitor = Self("showMonitor", default: .init(.semicolon, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// The app that was frontmost before the show-monitor hotkey opened the popover.
    private var previousApp: NSRunningApplication?

    private var autoAdvanceObserver: NSObjectProtocol?
    private var autoRestartObserver: NSObjectProtocol?

    private init() {}

    func setupHotkeys() {
        autoAdvanceObserver = NotificationCenter.default.addObserver(
            forName: .shouldAutoAdvance, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAutoAdvance()
            }
        }

        autoRestartObserver = NotificationCenter.default.addObserver(
            forName: .shouldAutoRestart, object: nil, queue: .main
        ) { [weak self] notification in
            guard let sessionID = notification.userInfo?["sessionID"] as? String else { return }
            Task { @MainActor in
                await self?.handleAutoRestart(sessionID: sessionID)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .cycleForward) {
            // Capture frontmost app synchronously before async Task scheduling
            let wasTerminalFrontmost = SessionManager.shared.isTerminalFrontmost()
            Task { await self.handleCycleForward(wasTerminalFrontmost: wasTerminalFrontmost) }
        }

        KeyboardShortcuts.onKeyDown(for: .cycleBackward) {
            let wasTerminalFrontmost = SessionManager.shared.isTerminalFrontmost()
            Task { await self.handleCycleBackward(wasTerminalFrontmost: wasTerminalFrontmost) }
        }

        KeyboardShortcuts.onKeyDown(for: .backburner) {
            Task { await self.handleBackburner() }
        }

        KeyboardShortcuts.onKeyDown(for: .reactivateAll) {
            self.handleReactivateAll()
        }

        KeyboardShortcuts.onKeyDown(for: .showMonitor) {
            self.handleShowMonitor()
        }
    }

    private func handleCycleForward(wasTerminalFrontmost: Bool) async {
        await activateWithRetry(
            direction: "forward",
            cycle: { SessionManager.shared.cycleForward(wasTerminalFrontmost: wasTerminalFrontmost) }
        )
    }

    private func handleCycleBackward(wasTerminalFrontmost: Bool) async {
        await activateWithRetry(
            direction: "backward",
            cycle: { SessionManager.shared.cycleBackward(wasTerminalFrontmost: wasTerminalFrontmost) }
        )
    }

    private func activateWithRetry(
        direction: String,
        cycle: () -> Session?
    ) async {
        logDebug(.hotkey, "Cycle \(direction) triggered")
        // Each stale session is removed automatically on .sessionNotFound,
        // so cycle() will eventually return nil when no cyclable sessions remain.
        while let target = cycle() {
            // Guard against intermediate focus events during activation
            SessionManager.shared.beginActivation(targetSessionID: target.id)
            do {
                try await TerminalActivation.activate(session: target, trigger: .hotkey)
                SessionManager.shared.endActivation()
                let titleMode = SessionTitleMode(
                    rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.sessionTitleMode) ?? ""
                ) ?? .default
                let displayName = SessionManager.shared.disambiguatedDisplayName(
                    for: target, titleMode: titleMode
                )
                BeaconManager.shared.show(sessionName: displayName)
                return
            } catch TerminalBridgeError.sessionNotFound {
                SessionManager.shared.endActivation()
                logDebug(.hotkey, "Stale session skipped, retrying cycle \(direction)")
            } catch {
                SessionManager.shared.endActivation()
                logError(.hotkey, "Cycle \(direction) failed: \(error)")
                return
            }
        }
        logDebug(.hotkey, "No session to cycle to")
        BeaconManager.shared.show(sessionName: "All At Work")
    }

    private func handleAutoAdvance() async {
        await activateWithRetry(
            direction: "auto-advance",
            cycle: { SessionManager.shared.cycleForward() }
        )
    }

    private func handleAutoRestart(sessionID: String) async {
        await activateWithRetry(
            direction: "auto-restart",
            cycle: {
                // Return the target session directly if it's still cyclable, otherwise nil
                SessionManager.shared.sessions.first { $0.id == sessionID && $0.state.isIncludedInCycle }
            }
        )
    }

    private func handleBackburner() async {
        logDebug(.hotkey, "Backburner triggered")
        guard let session = SessionManager.shared.currentSession else {
            logDebug(.hotkey, "No current session to backburner")
            return
        }
        SessionManager.shared.backburnerSession(terminalSessionID: session.id)

        let goToNext = UserDefaults.standard.bool(forKey: AppStorageKeys.goToNextOnBackburner)
        guard goToNext else { return }
        // Each stale session is removed on .sessionNotFound, so currentSession
        // advances until we find a live one or run out.
        while let nextSession = SessionManager.shared.currentSession {
            SessionManager.shared.beginActivation(targetSessionID: nextSession.id)
            do {
                try await TerminalActivation.activate(session: nextSession, trigger: .hotkey)
                SessionManager.shared.endActivation()
                return
            } catch TerminalBridgeError.sessionNotFound {
                SessionManager.shared.endActivation()
                logDebug(.hotkey, "Backburner next session gone, retrying")
            } catch {
                SessionManager.shared.endActivation()
                logError(.hotkey, "Backburner go-to-next failed: \(error)")
                return
            }
        }
    }

    private func handleReactivateAll() {
        logDebug(.hotkey, "Reactivate all triggered")
        SessionManager.shared.reactivateAllBackburnered()
    }

    private func handleShowMonitor() {
        logDebug(.hotkey, "Show monitor triggered")
        let mainWindowVisible = NSApp.windows.contains {
            $0.identifier?.rawValue == "main" && $0.isVisible
        }

        if StatusBarManager.shared.isPopoverShown {
            // State 2: popover visible → hide popover, open main window
            StatusBarManager.shared.hidePopover()
            StatusBarManager.shared.openMainWindow()
        } else if mainWindowVisible {
            // State 3: main window visible → close it, go back to original app
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.close()
            }
            previousApp?.activate()
            previousApp = nil
        } else {
            // State 1: nothing visible → remember current app, show popover
            previousApp = NSWorkspace.shared.frontmostApplication
            StatusBarManager.shared.showPopover()
        }
    }
}
