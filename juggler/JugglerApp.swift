//
//  JugglerApp.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Carbon.HIToolbox
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false // Keep running when window closes (menu bar app stays active)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await ITerm2Bridge.shared.stop()
            await HookServer.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Show in dock since main window opens on launch
        NSApp.setActivationPolicy(.regular)

        // Listen for window events to toggle dock icon
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
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "main"
        else { return }
        // Delay to allow window to fully close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "main"
        else { return }
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct JugglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager.shared

    init() {
        // Set default values for settings
        UserDefaults.standard.register(defaults: [
            // Tab highlighting (off by default)
            "tabHighlightEnabled": false,
            "tabHighlightDuration": 2.0,
            "tabHighlightColorRed": 255.0,
            "tabHighlightColorGreen": 165.0,
            "tabHighlightColorBlue": 0.0,
            // Pane highlighting (on by default)
            "paneHighlightEnabled": true,
            "paneHighlightDuration": 2.0,
            "paneHighlightColorRed": 255.0,
            "paneHighlightColorGreen": 165.0,
            "paneHighlightColorBlue": 0.0,
            // Notifications
            "notifyOnIdle": true,
            "notifyOnPermission": true,
            "playSound": true,
            // Cycling colors
            "useCyclingColors": true,
            "useTerminalCyclingColors": true
        ])

        // Set up default local shortcuts if not already configured
        setupDefaultLocalShortcuts()

        // Request notification permission
        NotificationManager.shared.requestPermission()

        Task {
            try? await HookServer.shared.start()
            // Only start daemon if onboarding is complete (avoids early permission prompt)
            if UserDefaults.standard.bool(forKey: AppStorageKeys.hasCompletedOnboarding) {
                try? await ITerm2Bridge.shared.start()
            }
        }

        Task { @MainActor in
            HotkeyManager.shared.setupHotkeys()
            StatusBarManager.shared.setup()
        }
    }

    var body: some Scene {
        // Main window - Session Monitor
        // Use screen's visible height for max vertical space
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800

        Window("Juggler", id: "main") {
            SessionMonitorView()
                .environment(sessionManager)
        }
        .defaultSize(width: 480, height: screenHeight)
        .defaultPosition(.topTrailing)
        .defaultLaunchBehavior(.presented)
        .commands {
            AboutCommands()
        }

        Window("Welcome to Juggler", id: "onboarding") {
            OnboardingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

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

/// Set up default local shortcuts if not already configured
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
        let shortcut = LocalShortcut(keyCode: UInt16(keyCode), modifiers: modifiers)
        shortcut.save(to: key)
    }
}
