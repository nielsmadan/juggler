//
//  JugglerApp.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Carbon.HIToolbox
import ShortcutField
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowNeedsRestore = true
    private var hideAccessoryWorkItem: DispatchWorkItem?

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false // Keep running when window closes (menu bar app stays active)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await TerminalBridgeRegistry.shared.stopAll()
            await HookServer.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_: Notification) {
        // If another instance is already running, activate it and exit.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
            .filter { $0 != .current }
        if let existing = others.first {
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // Restore saved window position on launch (avoids flicker at default position)
        if UserDefaults.standard.string(forKey: AppStorageKeys.mainWindowFrame) != nil {
            DispatchQueue.main.async { [weak self] in
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.alphaValue = 0
                    self?.restoreSavedFrame(for: window)
                    window.alphaValue = 1
                }
            }
        }
    }

    func restoreSavedFrame(for window: NSWindow) {
        mainWindowNeedsRestore = false
        guard let frameString = UserDefaults.standard.string(forKey: AppStorageKeys.mainWindowFrame) else { return }
        let savedFrame = NSRectFromString(frameString)
        let onScreen = NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) })
        if savedFrame.width > 100, savedFrame.height > 100, onScreen {
            window.setFrame(savedFrame, display: false)
        }
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "main"
        else { return }
        // Must save before window deallocs
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: AppStorageKeys.mainWindowFrame)
        mainWindowNeedsRestore = true
        // Cancel any pending hide and schedule a new one. Using a cancellable
        // work item prevents a race where the user reopens the window within
        // the 0.1s delay, causing the dock icon to disappear while visible.
        hideAccessoryWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            NSApp.setActivationPolicy(.accessory)
        }
        hideAccessoryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "main"
        else { return }

        let wasInAccessoryMode = NSApp.activationPolicy() == .accessory

        hideAccessoryWorkItem?.cancel()
        hideAccessoryWorkItem = nil

        // When a notification click activated us, yield focus to the terminal
        // after the system's activation lifecycle has settled (see comment in
        // NotificationManager.didReceive for details).
        if let bundleID = notificationTerminalBundleID() {
            scheduleTerminalActivation(bundleID: bundleID)
            return
        }

        NSApp.setActivationPolicy(.regular)

        if mainWindowNeedsRestore {
            mainWindowNeedsRestore = false
            restoreSavedFrame(for: window)
        }

        // Window was auto-created from accessory mode. Hide it immediately to
        // prevent a flash, then decide on the next run loop (didReceive fires
        // after windowDidBecomeKey, so the notification flag isn't set yet).
        if wasInAccessoryMode {
            window.alphaValue = 0
            DispatchQueue.main.async {
                if let bundleID = self.notificationTerminalBundleID() {
                    self.scheduleTerminalActivation(bundleID: bundleID)
                    window.close()
                } else {
                    window.alphaValue = 1
                }
            }
        }
    }

    private func notificationTerminalBundleID() -> String? {
        guard NotificationManager.shared.isHandlingNotificationClick else { return nil }
        return NotificationManager.shared.pendingTerminalBundleID
    }

    private func scheduleTerminalActivation(bundleID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
            }
        }
    }
}

@main
struct JugglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager.shared

    init() {
        // Reduce tooltip hover delay from default ~1000ms to 300ms
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")

        UserDefaults.standard.register(defaults: [
            // Highlight triggers (all on by default)
            "highlightOnHotkey": true,
            "highlightOnGuiSelect": true,
            "highlightOnNotification": true,
            // Tab highlighting
            "tabHighlightEnabled": true,
            "tabHighlightDuration": 2.0,
            "tabHighlightColorRed": 255.0,
            "tabHighlightColorGreen": 165.0,
            "tabHighlightColorBlue": 0.0,
            // Pane highlighting
            "paneHighlightEnabled": true,
            "paneHighlightDuration": 1.0,
            "paneHighlightColorRed": 255.0,
            "paneHighlightColorGreen": 165.0,
            "paneHighlightColorBlue": 0.0,
            // Notifications
            "notifyOnIdle": true,
            "notifyOnPermission": true,
            "playSound": true,
            // Backburner behavior
            "goToNextOnBackburner": true,
            // Auto-advance behavior
            AppStorageKeys.autoAdvanceOnBusy: false,
            AppStorageKeys.autoRestartOnIdle: false,
            // Cycling colors
            "useCyclingColors": true,
            "useTerminalCyclingColors": true,
            // Terminal enablement (iTerm2 on by default for existing users)
            AppStorageKeys.iterm2Enabled: true,
            AppStorageKeys.kittyEnabled: false,
            // Beacon HUD
            "beaconEnabled": true,
            "beaconDuration": 1.5,
            "beaconPosition": BeaconPosition.center.rawValue,
            "beaconSize": BeaconSize.m.rawValue,
            "beaconAnchor": BeaconAnchor.screen.rawValue
        ])

        setupDefaultLocalShortcuts()

        // Skip heavy service startup when running as a test host
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NotificationManager.shared.requestPermission()

        Task {
            await TerminalBridgeRegistry.shared.register(ITerm2Bridge.shared, for: .iterm2)
            await TerminalBridgeRegistry.shared.register(KittyBridge.shared, for: .kitty)

            try? await HookServer.shared.start()
            // Only start bridges if onboarding is complete (avoids early permission prompt)
            if UserDefaults.standard.bool(forKey: AppStorageKeys.hasCompletedOnboarding) {
                if UserDefaults.standard.bool(forKey: AppStorageKeys.iterm2Enabled) {
                    try? await TerminalBridgeRegistry.shared.start(.iterm2)
                }
                if UserDefaults.standard.bool(forKey: AppStorageKeys.kittyEnabled) {
                    try? await TerminalBridgeRegistry.shared.start(.kitty)
                }
            }
        }

        Task { @MainActor in
            HotkeyManager.shared.setupHotkeys()
            StatusBarManager.shared.setup()
            SessionManager.shared.startAppFocusObserver()
        }
    }

    var body: some Scene {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AppStorageKeys.hasCompletedOnboarding)

        Window("Juggler", id: "main") {
            SessionMonitorView()
                .environment(sessionManager)
        }
        .defaultSize(width: 480, height: screenHeight)
        .defaultPosition(.topTrailing)
        .defaultLaunchBehavior(hasCompletedOnboarding ? .presented : .suppressed)
        .commands {
            AboutCommands()
        }

        Window("Welcome to Juggler", id: "onboarding") {
            OnboardingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(hasCompletedOnboarding ? .suppressed : .presented)

        Window("About Juggler", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Juggler") {
                openWindow(id: "about")
            }
        }
    }
}

private func setupDefaultLocalShortcuts() {
    let defaults: [(key: String, keyCode: Int, shift: Bool)] = [
        (AppStorageKeys.localShortcutMoveDown, kVK_ANSI_K, false),
        (AppStorageKeys.localShortcutMoveUp, kVK_ANSI_J, false),
        (AppStorageKeys.localShortcutBackburner, kVK_ANSI_L, false),
        (AppStorageKeys.localShortcutReactivateSelected, kVK_ANSI_L, true), // Shift+L
        (AppStorageKeys.localShortcutReactivateAll, kVK_ANSI_H, false),
        (AppStorageKeys.localShortcutRename, kVK_ANSI_R, false),
        (AppStorageKeys.localShortcutCycleModeForward, kVK_Tab, false),
        (AppStorageKeys.localShortcutCycleModeBackward, kVK_Tab, true) // Shift+Tab
    ]

    for (key, keyCode, shift) in defaults where UserDefaults.standard.data(forKey: key) == nil {
        let modifiers: NSEvent.ModifierFlags = shift ? .shift : []
        let shortcut = Shortcut(keyCode: UInt16(keyCode), modifiers: modifiers)
        shortcut.save(to: key)
    }
}
