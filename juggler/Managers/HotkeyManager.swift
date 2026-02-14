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

    private init() {}

    func setupHotkeys() {
        KeyboardShortcuts.onKeyDown(for: .cycleForward) {
            Task { await self.handleCycleForward() }
        }

        KeyboardShortcuts.onKeyDown(for: .cycleBackward) {
            Task { await self.handleCycleBackward() }
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

    private func handleCycleForward() async {
        await activateWithRetry(direction: "forward", cycle: SessionManager.shared.cycleForward)
    }

    private func handleCycleBackward() async {
        await activateWithRetry(direction: "backward", cycle: SessionManager.shared.cycleBackward)
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
                ) ?? .tabTitle
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
        if StatusBarManager.shared.isPopoverShown {
            StatusBarManager.shared.hidePopover()
            StatusBarManager.shared.openMainWindow()
        } else {
            StatusBarManager.shared.showPopover()
        }
    }
}
