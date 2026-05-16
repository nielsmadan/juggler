//
//  StatusBarManager.swift
//  Juggler
//

import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusBarManager {
    static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var menu: NSMenu?
    private var settingsWindow: NSWindow?

    private init() {}

    var isPopoverShown: Bool {
        popover?.isShown ?? false
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(named: "juggling")
            button.image?.isTemplate = true
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environment(SessionManager.shared)
        )

        menu = NSMenu()

        let showItem = NSMenuItem(title: "Open Juggler", action: #selector(openMainWindow), keyEquivalent: "")
        showItem.target = self
        menu?.addItem(showItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu?.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu?.addItem(updateItem)

        menu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)

        observeDaemonStatus()
    }

    /// Reactively reflect ITerm2DaemonStatus in the menu bar button. Re-arms itself
    /// on every observable change via withObservationTracking.
    private func observeDaemonStatus() {
        withObservationTracking {
            applyDaemonStatus(
                state: ITerm2DaemonStatus.shared.state,
                stderrTail: ITerm2DaemonStatus.shared.lastStderrTail
            )
        } onChange: { [weak self] in
            // onChange fires once when any tracked property mutates; hop back to
            // main and re-establish tracking for the next change.
            DispatchQueue.main.async { self?.observeDaemonStatus() }
        }
    }

    private func applyDaemonStatus(state: DaemonState, stderrTail: String?) {
        guard let button = statusItem?.button else { return }

        switch state {
        case .stopped, .ready:
            button.alphaValue = 1.0
            button.contentTintColor = nil
            button.toolTip = nil
        case .starting:
            button.alphaValue = 1.0
            button.contentTintColor = nil
            button.toolTip = "Connecting to iTerm2…"
        case .waitingForITerm2:
            button.alphaValue = 0.5
            button.contentTintColor = nil
            button.toolTip = "Waiting for iTerm2 — make sure it's running and the Python API is enabled."
        case let .failed(reason):
            button.alphaValue = 1.0
            button.contentTintColor = .systemRed
            let tail = (stderrTail?.isEmpty == false) ? "\n\n\(stderrTail!.suffix(400))" : ""
            button.toolTip = "iTerm2 integration unavailable.\n\(reason)\(tail)"
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        if let menuItem = menu?.items.first {
            let isWindowVisible = NSApp.windows.contains { $0.identifier?.rawValue == "main" && $0.isVisible }
            menuItem.title = isWindowVisible ? "Show Juggler" : "Open Juggler"
        }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, let popover, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func hidePopover() {
        popover?.performClose(nil)
    }

    @objc func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Juggler" }) {
            // Restore saved frame before showing to avoid flicker
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.restoreSavedFrame(for: window)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }

    @objc func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView()
                    .environment(SessionManager.shared)
            )

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(hostingController.view.fittingSize)
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
