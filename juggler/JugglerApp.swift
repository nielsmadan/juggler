//
//  JugglerApp.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import SwiftUI

private var isUnitTestHost: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

private func allowsDuplicateTestInstance() -> Bool {
    if isUnitTestHost { return true }
    #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-performanceTesting")
    #else
        return false
    #endif
}

private func otherRunningInstance() -> NSRunningApplication? {
    guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first { $0 != .current && !$0.isTerminated }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate static let duplicateInstance: NSRunningApplication? =
        allowsDuplicateTestInstance() ? nil : otherRunningInstance()

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SessionManager.shared.commitInProgressBusyTime()
        Task {
            await TerminalBridgeRegistry.shared.stopAll()
            await HookServer.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_: Notification) {
        if let existing = AppDelegate.duplicateInstance {
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        WindowManager.shared.start()
    }
}

@main
struct JugglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager.shared

    init() {
        // Reduce tooltip hover delay from default ~1000ms to 300ms
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")

        for (key, value) in RowSlotMigration.pendingValues(stored: UserDefaults.standard.object(forKey:)) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.register(defaults: RowSlotPosition.registrationDefaults)
        for (key, value) in RowActionMigration.pendingValues(stored: UserDefaults.standard.object(forKey:)) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.register(defaults: RowActionPosition.registrationDefaults)
        UserDefaults.standard.register(defaults: [
            "highlightOnHotkey": true,
            "highlightOnGuiSelect": true,
            "highlightOnNotification": true,
            "tabHighlightEnabled": true,
            "tabHighlightDuration": 2.0,
            "tabHighlightColorRed": 255.0,
            "tabHighlightColorGreen": 165.0,
            "tabHighlightColorBlue": 0.0,
            "paneHighlightEnabled": true,
            "paneHighlightDuration": 1.0,
            "paneHighlightColorRed": 255.0,
            "paneHighlightColorGreen": 165.0,
            "paneHighlightColorBlue": 0.0,
            "notifyOnIdle": true,
            "notifyOnPermission": true,
            "playSound": false,
            "goToNextOnBackburner": true,
            AppStorageKeys.autoAdvanceOnBusy: false,
            AppStorageKeys.autoRestartOnIdle: false,
            AppStorageKeys.prioritizePermissionSessions: false,
            "useCyclingColors": true,
            "useTerminalCyclingColors": true,
            AppStorageKeys.iterm2Enabled: true,
            AppStorageKeys.kittyEnabled: false,
            AppStorageKeys.showInDock: true,
            AppStorageKeys.quitOnMonitorClose: false,
            "beaconEnabled": true,
            "beaconDuration": 1.5,
            "beaconPosition": BeaconPosition.center.rawValue,
            "beaconSize": BeaconSize.m.rawValue,
            "beaconAnchor": BeaconAnchor.screen.rawValue,
            AppStorageKeys.statsUseCyclingColors: true,
            AppStorageKeys.statsBarColorRed: 255.0,
            AppStorageKeys.statsBarColorGreen: 165.0,
            AppStorageKeys.statsBarColorBlue: 0.0
        ])

        guard !isUnitTestHost else { return }

        guard AppDelegate.duplicateInstance == nil else { return }

        NotificationManager.shared.requestPermission()

        Task {
            await TerminalBridgeRegistry.shared.register(ITerm2Bridge.shared, for: .iterm2)
            await TerminalBridgeRegistry.shared.register(KittyBridge.shared, for: .kitty)
            await TerminalBridgeRegistry.shared.register(WezTermBridge.shared, for: .wezterm)

            await registerStatusConsumer()
            try? await HookServer.shared.start()
            await hydrateRunningSessions()
            // Only start bridges if onboarding is complete (avoids early permission prompt)
            if UserDefaults.standard.bool(forKey: AppStorageKeys.hasCompletedOnboarding) {
                // Refresh any installed hook/plugin that a prior app version left stale on disk,
                // before sessions start arriving.
                await IntegrationSync.run()
                if UserDefaults.standard.bool(forKey: AppStorageKeys.iterm2Enabled) {
                    try? await TerminalBridgeRegistry.shared.start(.iterm2)
                }
                if UserDefaults.standard.bool(forKey: AppStorageKeys.kittyEnabled) {
                    try? await TerminalBridgeRegistry.shared.start(.kitty)
                }
                if UserDefaults.standard.bool(forKey: AppStorageKeys.wezTermEnabled) {
                    try? await TerminalBridgeRegistry.shared.start(.wezterm)
                }
            }
        }

        Task { @MainActor in
            HotkeyManager.shared.setupHotkeys()
            ShortcutCenter.shared.start()
            StatusBarManager.shared.setup()
            SessionManager.shared.startAppFocusObserver()
        }
    }

    var body: some Scene {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AppStorageKeys.hasCompletedOnboarding)

        Window("Juggler", id: WindowManager.SceneID.main) {
            SessionMonitorView()
                .environment(sessionManager)
                .allowsWindowActivationEvents()
        }
        .defaultSize(width: 480, height: screenHeight)
        .defaultPosition(.topTrailing)
        .defaultLaunchBehavior(hasCompletedOnboarding ? .presented : .suppressed)
        .commands {
            AppCommands()
        }

        Window("Welcome to Juggler", id: WindowManager.SceneID.onboarding) {
            OnboardingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(hasCompletedOnboarding ? .suppressed : .presented)

        Window("About Juggler", id: WindowManager.SceneID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

/// Registers Juggler as a hooklinesinker status consumer so installed hooks fan events out to
/// this instance's `/hook` port.
private func registerStatusConsumer() async {
    let result = await HooklinesinkerClient.shared.installConsumer()
    let summary = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    await MainActor.run {
        if result.isSuccess {
            logInfo(.hooks, "Registered hooklinesinker consumer: \(summary)")
        } else {
            logWarning(.hooks, "Failed to register hooklinesinker consumer: \(result.failureMessage)")
        }
    }
}

/// Replays sessions that were already running before launch. Always called — even on failure —
/// so `HookServer` stops tracking pre-hydration bindings.
private func hydrateRunningSessions() async {
    do {
        let sessions = try await HooklinesinkerClient.shared.sessions()
        await HookServer.shared.hydrate(from: sessions)
        await MainActor.run {
            logInfo(.hooks, "Hydrated \(sessions.statuses.count) running session(s) from hooklinesinker")
            if sessions.skippedRecordCount > 0 {
                logWarning(.hooks, "Skipped \(sessions.skippedRecordCount) unreadable hooklinesinker record(s)")
            }
            for problem in sessions.problems {
                logWarning(.hooks, problem.logLine)
            }
        }
    } catch {
        await HookServer.shared.hydrate([])
        await MainActor.run {
            logWarning(.hooks, "Session hydration failed: \(error.localizedDescription)")
        }
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // swiftlint:disable:next redundant_discardable_let
        let _ = WindowManager.shared.registerMainWindowOpener { openWindow(id: WindowManager.SceneID.main) }

        CommandGroup(replacing: .appInfo) {
            Button("About Juggler") {
                openWindow(id: WindowManager.SceneID.about)
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                WindowManager.shared.openSettings()
            }
            .keyboardShortcut(",")
        }
    }
}
