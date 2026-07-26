//
//  HotkeyManager.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Foundation
import SwiftUI

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// The app that was frontmost before the show-monitor hotkey opened the popover.
    private var previousApp: NSRunningApplication?

    /// Whether the show-monitor hotkey initiated the current popover/window cycle.
    /// Reset when Juggler loses focus so external window opens don't confuse step 3.
    private var monitorCycleActive = false

    private init() {}

    func setupHotkeys() {
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                self?.monitorCycleActive = false
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .shouldAutoAdvance, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAutoAdvance()
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .shouldAutoRestart, object: nil, queue: .main
        ) { [weak self] notification in
            guard let sessionID = notification.userInfo?["sessionID"] as? String else { return }
            Task { @MainActor in
                await self?.handleAutoRestart(sessionID: sessionID)
            }
        }
    }

    /// Entry point for a global hotkey firing. Called from `ShortcutCenter`'s
    /// global context handler (which runs synchronously on key-down via the
    /// Carbon activator), so terminal-frontmost state is captured here before
    /// any async hop — mirroring the old `KeyboardShortcuts.onKeyDown` path.
    func dispatch(_ action: GlobalAction) {
        switch action {
        case .cycleForward:
            let wasTerminalFrontmost = SessionManager.shared.isTerminalFrontmost()
            Task { await self.handleCycleForward(wasTerminalFrontmost: wasTerminalFrontmost) }
        case .cycleBackward:
            let wasTerminalFrontmost = SessionManager.shared.isTerminalFrontmost()
            Task { await self.handleCycleBackward(wasTerminalFrontmost: wasTerminalFrontmost) }
        case .backburner:
            Task { await self.handleBackburner() }
        case .sendToBack:
            Task { await self.handleSendToBack() }
        case .reactivateAll:
            handleReactivateAll()
        case .showMonitor:
            handleShowMonitor()
        case .goToLastNotification:
            Task { await self.handleGoToLastNotification() }
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
        let outcome = await SessionActivator.shared.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .cycle,
            nextSession: cycle
        )
        switch outcome {
        case .activated:
            return
        case .unavailable:
            logDebug(.hotkey, "No session to cycle to")
        case let .failed(error):
            logError(.hotkey, "Cycle \(direction) failed: \(error)")
        }
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
                SessionManager.shared.sessions.first { $0.id == sessionID && $0.state.isIncludedInCycle }
            }
        )
    }

    private func handleGoToLastNotification() async {
        logDebug(.hotkey, "Go to last notification triggered")
        guard let id = SessionManager.shared.lastNotifiedSessionID,
              let target = SessionManager.shared.sessions.first(where: { $0.id == id }) else {
            BeaconManager.shared.show(sessionName: "No Notification")
            return
        }
        let outcome = await SessionActivator.shared.activate(
            session: target,
            trigger: .hotkey,
            presentation: .notificationJump
        )
        if case let .failed(error) = outcome {
            logError(.hotkey, "Go to last notification failed: \(error)")
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
        guard goToNext else { return }
        guard SessionManager.shared.currentSession != nil else { return }
        SessionManager.shared.advanceColorIndex(by: 1)
        let outcome = await SessionActivator.shared.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .failureOnly,
            nextSession: { SessionManager.shared.currentSession }
        )
        if case let .failed(error) = outcome {
            logError(.hotkey, "Backburner go-to-next failed: \(error)")
        }
    }

    private func handleSendToBack() async {
        logDebug(.hotkey, "Send to back triggered")
        guard let current = SessionManager.shared.currentSession,
              current.state.isIncludedInCycle else {
            logDebug(.hotkey, "No cyclable current session to send to back")
            return
        }
        guard let next = SessionManager.shared.sendToBackOfQueue(sessionID: current.id) else {
            logDebug(.hotkey, "Send to back not applicable in current queue mode")
            return
        }
        SessionManager.shared.updateFocusedSession(terminalSessionID: next.id)
        await activateWithRetry(
            direction: "send-to-back",
            cycle: { SessionManager.shared.currentSession }
        )
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
            // Step 2: popover visible → hide popover, open main window
            StatusBarManager.shared.hidePopover()
            StatusBarManager.shared.openMainWindow()
            monitorCycleActive = true
        } else if monitorCycleActive, mainWindowVisible {
            // Step 3: main window visible (opened by this cycle) → close, return
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.close()
            }
            previousApp?.activate()
            previousApp = nil
            monitorCycleActive = false
        } else {
            // Step 1: nothing visible (or window opened externally) → show popover
            previousApp = NSWorkspace.shared.frontmostApplication
            StatusBarManager.shared.showPopover()
            monitorCycleActive = true
        }
    }
}
