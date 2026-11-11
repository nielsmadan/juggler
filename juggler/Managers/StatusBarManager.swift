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
    private let popoverPresentation = PopoverPresentation()

    private init() {}

    var isPopoverShown: Bool {
        popover?.isShown ?? false
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let icon = NSImage(named: "juggling")
            icon?.isTemplate = true
            button.image = icon
            button.setAccessibilityTitle("Juggler")
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingController = NSHostingController(
            rootView: MenuBarView(presentation: popoverPresentation)
                .environment(SessionManager.shared)
        )
        hostingController.sizingOptions = .preferredContentSize
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = hostingController

        menu = NSMenu()

        let showItem = NSMenuItem(
            title: "Open Juggler",
            action: #selector(WindowManager.openMainWindow),
            keyEquivalent: ""
        )
        showItem.target = WindowManager.shared
        menu?.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(WindowManager.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = WindowManager.shared
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

    /// Reactively reflect ITerm2DaemonStatus in the menu bar button.
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
            button.toolTip = "Juggler"
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
            menuItem.title = WindowManager.shared.isMainWindowVisible ? "Show Juggler" : "Open Juggler"
        }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func togglePopover() {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, let popover, !popover.isShown else { return }
        popoverPresentation.willShow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func hidePopover() {
        popover?.performClose(nil)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
@Observable
final class PopoverPresentation {
    private(set) var showCount = 0

    func willShow() {
        showCount += 1
    }
}
