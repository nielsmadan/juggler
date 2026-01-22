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
        logDebug(.hotkey, "Cycle forward triggered")
        guard let session = SessionManager.shared.cycleForward() else {
            logDebug(.hotkey, "No session to cycle to")
            return
        }

        do {
            try await TerminalActivation.activate(session: session, trigger: .hotkey)
        } catch {
            logError(.hotkey, "Cycle forward failed: \(error)")
        }
    }

    private func handleCycleBackward() async {
        logDebug(.hotkey, "Cycle backward triggered")
        guard let session = SessionManager.shared.cycleBackward() else {
            logDebug(.hotkey, "No session to cycle to")
            return
        }

        do {
            try await TerminalActivation.activate(session: session, trigger: .hotkey)
        } catch {
            logError(.hotkey, "Cycle backward failed: \(error)")
        }
    }

    private func handleBackburner() async {
        logDebug(.hotkey, "Backburner triggered")
        guard let session = SessionManager.shared.currentSession else {
            logDebug(.hotkey, "No current session to backburner")
            return
        }
        SessionManager.shared.backburnerSession(terminalSessionID: session.id)

        let goToNext = UserDefaults.standard.bool(forKey: AppStorageKeys.goToNextOnBackburner)
        if goToNext, let nextSession = SessionManager.shared.currentSession {
            do {
                try await TerminalActivation.activate(session: nextSession, trigger: .hotkey)
            } catch {
                logError(.hotkey, "Backburner go-to-next failed: \(error)")
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
