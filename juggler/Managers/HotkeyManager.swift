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
    private let sessionManager: SessionManager
    private let activator: SessionActivator
    private let showBeacon: (String) -> Void

    init(
        sessionManager: SessionManager = .shared,
        activator: SessionActivator = .shared,
        showBeacon: @escaping (String) -> Void = { BeaconManager.shared.show(sessionName: $0) }
    ) {
        self.sessionManager = sessionManager
        self.activator = activator
        self.showBeacon = showBeacon
    }

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
        ) { [weak self] notification in
            guard let request = notification.userInfo?["request"] as? SessionAutomaticActivation else { return }
            Task { @MainActor in
                await self?.handleAutomaticActivation(request)
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .shouldAutoRestart, object: nil, queue: .main
        ) { [weak self] notification in
            guard let request = notification.userInfo?["request"] as? SessionAutomaticActivation else { return }
            Task { @MainActor in
                await self?.handleAutomaticActivation(request)
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
            let wasTerminalFrontmost = sessionManager.isTerminalFrontmost()
            Task { await self.handleCycleForward(wasTerminalFrontmost: wasTerminalFrontmost) }
        case .cycleBackward:
            let wasTerminalFrontmost = sessionManager.isTerminalFrontmost()
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
        case .editNote:
            SessionNoteEditorManager.shared.editFocusedSession()
        }
    }

    private func handleCycleForward(wasTerminalFrontmost: Bool) async {
        await activateWithRetry(
            direction: "forward",
            presentation: cyclePresentation(),
            cycle: { self.sessionManager.cycleForward(wasTerminalFrontmost: wasTerminalFrontmost) }
        )
    }

    private func handleCycleBackward(wasTerminalFrontmost: Bool) async {
        await activateWithRetry(
            direction: "backward",
            presentation: cyclePresentation(),
            cycle: { self.sessionManager.cycleBackward(wasTerminalFrontmost: wasTerminalFrontmost) }
        )
    }

    private func cyclePresentation() -> SessionActivationPresentation {
        let manager = sessionManager
        return .forCyclableCount(
            manager.cyclableSessions.count,
            returnsToFocusedSession: manager.isFocusedOnOnlyCyclableSession
        )
    }

    private func activateWithRetry(
        direction: String,
        presentation: SessionActivationPresentation = .cycle,
        automaticRequest: SessionAutomaticActivation? = nil,
        cycle: () -> Session?
    ) async {
        logDebug(.hotkey, "Cycle \(direction) triggered")
        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey,
            presentation: presentation,
            automaticRequest: automaticRequest,
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

    func handleAutomaticActivation(_ request: SessionAutomaticActivation) async {
        await activateWithRetry(
            direction: request.kind == .advance ? "auto-advance" : "auto-restart",
            automaticRequest: request,
            cycle: { self.sessionManager.nextAutomaticSession(for: request) }
        )
    }

    func handleGoToLastNotification() async {
        logDebug(.hotkey, "Go to last notification triggered")
        guard let notification = sessionManager.lastNotificationTarget,
              let target = sessionManager.session(for: notification) else {
            showBeacon("No Notification")
            return
        }
        let outcome = await activator.activate(
            session: target,
            trigger: .hotkey,
            policy: .notification(notification),
            presentation: .notificationJump
        )
        if case let .failed(error) = outcome {
            logError(.hotkey, "Go to last notification failed: \(error)")
        }
    }

    func handleBackburner() async {
        logDebug(.hotkey, "Backburner triggered")
        guard let session = sessionManager.currentCommandSession else {
            logDebug(.hotkey, "No current session to backburner")
            return
        }
        sessionManager.backburnerSession(terminalSessionID: session.id)

        let goToNext = UserDefaults.standard.bool(forKey: AppStorageKeys.goToNextOnBackburner)
        guard goToNext else { return }
        guard sessionManager.currentCyclableSession != nil else { return }
        sessionManager.advanceColorIndex(by: 1)
        let outcome = await activator.activateFirstAvailable(
            trigger: .hotkey,
            presentation: .failureOnly,
            nextSession: { self.sessionManager.currentCyclableSession }
        )
        if case let .failed(error) = outcome {
            logError(.hotkey, "Backburner go-to-next failed: \(error)")
        }
    }

    func handleSendToBack() async {
        logDebug(.hotkey, "Send to back triggered")
        guard let current = sessionManager.currentCommandSession,
              current.isCycleEligible else {
            logDebug(.hotkey, "No cyclable current session to send to back")
            return
        }
        guard let next = sessionManager.sendToBackOfQueue(sessionID: current.id) else {
            logDebug(.hotkey, "Send to back not applicable in current queue mode")
            return
        }
        sessionManager.updateFocusedSession(terminalSessionID: next.id)
        await activateWithRetry(
            direction: "send-to-back",
            cycle: { self.sessionManager.currentCyclableSession }
        )
    }

    private func handleReactivateAll() {
        logDebug(.hotkey, "Reactivate all triggered")
        sessionManager.reactivateAllBackburnered()
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
