//
//  SettingsView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import KeyboardShortcuts
import ServiceManagement
import ShortcutField
import Sparkle
import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            IntegrationSettingsView()
                .tabItem {
                    Label("Integration", systemImage: "puzzlepiece")
                }

            SSHSettingsView()
                .tabItem {
                    Label("SSH", systemImage: "network")
                }

            HighlightingSettingsView()
                .tabItem {
                    Label("Highlighting", systemImage: "sparkles")
                }

            BeaconSettingsView()
                .tabItem {
                    Label("Beacon", systemImage: "light.panel")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

            LogsSettingsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
        }
        .frame(minWidth: 480, minHeight: 640)
    }
}

struct GeneralSettingsView: View {
    @AppStorage(AppStorageKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppStorageKeys.showInDock) private var showInDock = true
    @AppStorage(AppStorageKeys.quitOnMonitorClose) private var quitOnMonitorClose = false
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleMode: String = SessionTitleMode
        .default.rawValue
    @AppStorage(AppStorageKeys.notifyOnIdle) private var notifyOnIdle = true
    @AppStorage(AppStorageKeys.notifyOnPermission) private var notifyOnPermission = true
    @AppStorage(AppStorageKeys.playSound) private var playSound = true
    @AppStorage(AppStorageKeys.enableStats) private var enableStats = true
    @AppStorage(AppStorageKeys.statsUseCyclingColors) private var statsUseCyclingColors = true
    @AppStorage(AppStorageKeys.statsBarColorRed) private var statsBarColorRed = 255.0
    @AppStorage(AppStorageKeys.statsBarColorGreen) private var statsBarColorGreen = 165.0
    @AppStorage(AppStorageKeys.statsBarColorBlue) private var statsBarColorBlue = 0.0
    @AppStorage(AppStorageKeys.goToNextOnBackburner) private var goToNextOnBackburner = true

    @State private var showingUninstallConfirm = false
    @State private var showingUninstallSummary = false
    @State private var uninstallSummary = ""

    private var statsBarColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: statsBarColorRed / 255,
                    green: statsBarColorGreen / 255,
                    blue: statsBarColorBlue / 255
                )
            },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    statsBarColorRed = components.redComponent * 255
                    statsBarColorGreen = components.greenComponent * 255
                    statsBarColorBlue = components.blueComponent * 255
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            logError(.session, "Failed to update launch at login: \(error)")
                            launchAtLogin = !newValue
                        }
                    }

                Toggle("Show Juggler in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        if newValue {
                            NSApp.setActivationPolicy(.regular)
                        } else {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }

                Toggle("Quit when Session Monitor is closed", isOn: $quitOnMonitorClose)

                Picker("Session Title", selection: $sessionTitleMode) {
                    ForEach(SessionTitleMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Notify when session becomes idle", isOn: $notifyOnIdle)
                Toggle("Notify when session needs permission", isOn: $notifyOnPermission)
                Toggle("Play sound", isOn: $playSound)
            }

            Section("Stats") {
                Toggle("Enable Stats", isOn: $enableStats)
                SettingWithDescription(description: "Each day's bar gets a color from the palette") {
                    Toggle("Use cycling colors", isOn: $statsUseCyclingColors)
                        .disabled(!enableStats)
                }
                if !statsUseCyclingColors {
                    ColorPicker("Bar color", selection: statsBarColor)
                        .disabled(!enableStats)
                }
            }

            Section("Backburner") {
                Toggle("Go to next session on backburner", isOn: $goToNextOnBackburner)
            }

            Section("Uninstall") {
                Text(
                    "Removes all integrations (Claude Code hooks, Kitty watcher, OpenCode plugin), resets Automation permission, clears settings, and quits the app. Accessibility permission must be removed manually in System Settings."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Button("Uninstall Juggler...") {
                    showingUninstallConfirm = true
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Uninstall Juggler?", isPresented: $showingUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task {
                    uninstallSummary = await performUninstall()
                    showingUninstallSummary = true
                }
            }
        } message: {
            Text("This will remove all integrations, permissions, and settings. You can then delete the app.")
        }
        .alert("Uninstall Complete", isPresented: $showingUninstallSummary) {
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } message: {
            Text(uninstallSummary)
        }
    }

    private func performUninstall() async -> String {
        var actions: [String] = []
        let fm = FileManager.default
        let bundleId = Bundle.main.bundleIdentifier ?? "com.nielsmadan.Juggler"

        // 1. Unregister login item
        try? await SMAppService.mainApp.unregister()
        actions.append("Removed login item")

        // 2. Run bundled uninstall.sh for integration cleanup
        if Bundle.main.path(forResource: "uninstall", ofType: "sh") != nil {
            if let error = await ScriptInstaller.runBundledScript(resource: "uninstall") {
                actions.append("Integration cleanup failed: \(error)")
            } else {
                actions.append("Removed integrations (Claude hooks, Kitty watcher, OpenCode plugin)")
                actions.append("Reset Automation permission")
            }
        }
        actions
            .append(
                "Note: Remove Accessibility permission manually in System Settings > Privacy & Security > Accessibility"
            )

        // 3. Clear UserDefaults
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
        UserDefaults.standard.synchronize()
        actions.append("Cleared all settings")

        // 4. Clear caches
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let appCache = cachesDir.appendingPathComponent(bundleId)
            if fm.fileExists(atPath: appCache.path) {
                try? fm.removeItem(at: appCache)
                actions.append("Cleared caches")
            }
        }

        return actions.joined(separator: "\n")
    }
}

struct IntegrationSettingsView: View {
    @State private var hasAccessibility = false
    @State private var hasAutomation = false
    @State private var hasNotifications = false

    @State private var hooksInstalled = false
    @State private var isInstallingHooks = false
    @State private var hookInstallError: String?

    @State private var kittyRemoteControl = false
    @State private var kittyListenOn = false
    @State private var kittyWatcherInstalled = false
    @State private var isInstallingKittyWatcher = false
    @State private var kittyWatcherError: String?
    @State private var kittyConfigError: String?

    @State private var tmuxConfigured = false
    @State private var isConfiguringTmux = false
    @State private var tmuxConfigError: String?

    @State private var openCodePluginInstalled = false
    @State private var isInstallingOpenCodePlugin = false
    @State private var openCodeInstallError: String?

    @State private var codexController = CodexSetupController()

    private var hooksPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/juggler/notify.sh").path
    }

    private var tmuxConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tmux.conf").path
    }

    private var openCodePluginPath: String {
        OpenCodePluginInstaller.pluginFilePath
    }

    private let tmuxUpdateEnvironmentLine =
        "set-option -ga update-environment ' ITERM_SESSION_ID KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID'"

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionRow(label: "Accessibility", granted: hasAccessibility) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                PermissionRow(label: "Automation (iTerm2)", granted: hasAutomation) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                    )
                }
                PermissionRow(label: "Notifications", granted: hasNotifications) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Notifications")!
                    )
                }

                Button("Refresh") {
                    checkPermissions()
                }
            }

            Section("Claude Code Hooks") {
                HStack {
                    Text("Hook Script")
                    Spacer()
                    if hooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = hookInstallError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(hooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    installHooks()
                }
                .disabled(isInstallingHooks)
            }

            Section("OpenCode") {
                HStack {
                    Text("Plugin")
                    Spacer()
                    if openCodePluginInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = openCodeInstallError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(openCodePluginInstalled ? "Reinstall Plugin" : "Install Plugin") {
                    installOpenCodePlugin()
                }
                .disabled(isInstallingOpenCodePlugin)
            }

            Section("Codex") {
                HStack {
                    Text("Hook Script")
                    Spacer()
                    if codexController.hooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(codexController.hooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    codexController.installHooks()
                }
                .disabled(codexController.isInstallingHooks)

                HStack {
                    Text("Feature Flag")
                    Spacer()
                    if codexController.featureFlagEnabled {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Enabled", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(codexController.featureFlagEnabled ? "Re-check Flag" : "Enable Feature Flag") {
                    codexController.enableFlag()
                }
                .disabled(codexController.isEnablingFlag)

                HStack {
                    Text("Enable in Codex")
                    Spacer()
                    if codexController.enabledInCodex {
                        Label("Trusted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Trusted", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Text(
                    "Bypasses Codex's own hook review. Alternatively, run /hooks in Codex and trust the Juggler hooks manually."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let error = codexController.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(codexController.enabledInCodex ? "Re-apply Trust" : "Enable in Codex") {
                    codexController.enableInCodex()
                }
                .disabled(codexController.isEnablingInCodex)
            }

            Section("Kitty") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Remote Control")
                        Spacer()
                        if kittyRemoteControl {
                            Label("Enabled", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not Configured", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !kittyRemoteControl {
                        Text("Adds allow_remote_control socket-only to kitty.conf")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Add to kitty.conf") {
                            configureKittyRemoteControl()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Listen Socket")
                        Spacer()
                        if kittyListenOn {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not Configured", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !kittyListenOn {
                        Text("Adds listen_on unix:/tmp/kitty-{kitty_pid} to kitty.conf")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Add to kitty.conf") {
                            configureKittyListenOn()
                        }
                    }
                }

                HStack {
                    Text("Watcher Script")
                    Spacer()
                    if kittyWatcherInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = kittyConfigError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if let error = kittyWatcherError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(kittyWatcherInstalled ? "Reinstall Watcher" : "Install Watcher") {
                    installKittyWatcher()
                }
                .disabled(isInstallingKittyWatcher)

                if !kittyRemoteControl || !kittyListenOn || kittyWatcherInstalled {
                    Text("Restart Kitty after changes for them to take effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("tmux") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal env vars in update-environment")
                        Spacer()
                        if tmuxConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not Configured", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Required for cycling between sessions in different tmux windows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = tmuxConfigError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    if !tmuxConfigured {
                        Button("Add to ~/.tmux.conf") {
                            configureTmux()
                        }
                        .disabled(isConfiguringTmux)

                        Text("Restart tmux after changes for them to take effect.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkPermissions()
            checkHooksInstalled()
            checkKittyStatus()
            checkTmuxConfigured()
            checkOpenCodePluginInstalled()
            codexController.refresh()
        }
    }

    // MARK: - Permissions

    private func checkPermissions() {
        hasAccessibility = AXIsProcessTrusted()
        checkAutomation()
        checkNotifications()
    }

    private func checkAutomation() {
        // Only check if iTerm2 is already running to avoid launching it as a side effect
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }
        guard isRunning else {
            hasAutomation = false
            return
        }
        Task.detached {
            let script = NSAppleScript(source: "tell application \"iTerm2\" to name")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            let granted = error == nil
            await MainActor.run {
                hasAutomation = granted
            }
        }
    }

    private func checkNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                hasNotifications = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Claude Code Hooks

    private func checkHooksInstalled() {
        hooksInstalled = FileManager.default.fileExists(atPath: hooksPath)
    }

    private func installHooks() {
        isInstallingHooks = true
        hookInstallError = nil

        Task {
            let result = await ScriptInstaller.installHooks()
            await MainActor.run {
                if let error = result {
                    hookInstallError = error
                } else {
                    checkHooksInstalled()
                }
                isInstallingHooks = false
            }
        }
    }

    // MARK: - Kitty

    private func checkKittyStatus() {
        let status = KittyConfigParser.status()
        kittyRemoteControl = status.remoteControlEnabled
        kittyListenOn = status.listenOnConfigured
        kittyWatcherInstalled = status.watcherInstalled
    }

    private func appendToKittyConf(_ line: String) {
        kittyConfigError = KittyConfigParser.appendToConf(line)
        checkKittyStatus()
    }

    private func configureKittyRemoteControl() {
        appendToKittyConf("allow_remote_control socket-only")
    }

    private func configureKittyListenOn() {
        appendToKittyConf("listen_on unix:/tmp/kitty-{kitty_pid}")
    }

    private func installKittyWatcher() {
        isInstallingKittyWatcher = true
        kittyWatcherError = nil

        Task {
            let result = await ScriptInstaller.installKittyWatcher()
            await MainActor.run {
                if let error = result {
                    kittyWatcherError = error
                } else {
                    checkKittyStatus()
                }
                isInstallingKittyWatcher = false
            }
        }
    }

    // MARK: - tmux Configuration

    private func checkTmuxConfigured() {
        guard FileManager.default.fileExists(atPath: tmuxConfPath) else {
            tmuxConfigured = false
            return
        }

        do {
            let contents = try String(contentsOfFile: tmuxConfPath, encoding: .utf8)
            tmuxConfigured = TmuxConfigValidator.isConfigured(contents: contents)
        } catch {
            tmuxConfigured = false
        }
    }

    private func configureTmux() {
        isConfiguringTmux = true
        tmuxConfigError = ConfigFileWriter.appendLine(
            tmuxUpdateEnvironmentLine,
            toFileAt: tmuxConfPath,
            duplicateCheck: .exactMatch
        )
        checkTmuxConfigured()
        isConfiguringTmux = false
    }

    // MARK: - OpenCode Plugin

    private func checkOpenCodePluginInstalled() {
        openCodePluginInstalled = FileManager.default.fileExists(atPath: openCodePluginPath)
    }

    private func installOpenCodePlugin() {
        isInstallingOpenCodePlugin = true
        openCodeInstallError = nil

        do {
            try OpenCodePluginInstaller.install()
            checkOpenCodePluginInstalled()
        } catch {
            openCodeInstallError = error.localizedDescription
        }
        isInstallingOpenCodePlugin = false
    }
}

private struct PermissionRow: View {
    let label: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not Granted", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    openSettings()
                }
            }
        }
    }
}

struct ShortcutsSettingsView: View {
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show Shortcut Helper", isOn: $showShortcutHelper)
            }

            Section("Global Shortcuts") {
                KeyboardShortcuts.Recorder("Cycle Forward:", name: .cycleForward)
                KeyboardShortcuts.Recorder("Cycle Backward:", name: .cycleBackward)
                KeyboardShortcuts.Recorder("Backburner Current:", name: .backburner)
                KeyboardShortcuts.Recorder("Reactivate All:", name: .reactivateAll)
                SettingWithDescription(
                    description: "Activates the session from the most recent notification."
                ) {
                    KeyboardShortcuts.Recorder("Last Notification:", name: .goToLastNotification)
                }
                SettingWithDescription(
                    description: "Cycles: popover → monitor window → back to previous app."
                ) {
                    KeyboardShortcuts.Recorder("Show Monitor:", name: .showMonitor)
                }
            }

            SessionListShortcutsSection()
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SessionListShortcutsSection: View {
    @State private var moveDown = DiscreteShortcut.load(from: AppStorageKeys.localShortcutMoveDown)
    @State private var moveUp = DiscreteShortcut.load(from: AppStorageKeys.localShortcutMoveUp)
    @State private var backburner = DiscreteShortcut.load(from: AppStorageKeys.localShortcutBackburner)
    @State private var reactivateSelected = DiscreteShortcut.load(from: AppStorageKeys.localShortcutReactivateSelected)
    @State private var reactivateAll = DiscreteShortcut.load(from: AppStorageKeys.localShortcutReactivateAll)
    @State private var rename = DiscreteShortcut.load(from: AppStorageKeys.localShortcutRename)
    @State private var cycleModeForward = DiscreteShortcut.load(from: AppStorageKeys.localShortcutCycleModeForward)
    @State private var cycleModeBackward = DiscreteShortcut.load(from: AppStorageKeys.localShortcutCycleModeBackward)
    @State private var toggleBeacon: DiscreteShortcut? = DiscreteShortcut
        .load(from: AppStorageKeys.localShortcutToggleBeacon)
        ?? DiscreteShortcut(keyCode: 11, modifiers: []) // B
    @State private var toggleAutoNext: DiscreteShortcut? = DiscreteShortcut
        .load(from: AppStorageKeys.localShortcutToggleAutoNext)
        ?? DiscreteShortcut(keyCode: 0, modifiers: []) // A
    @State private var toggleAutoRestart: DiscreteShortcut? = DiscreteShortcut
        .load(from: AppStorageKeys.localShortcutToggleAutoRestart)
        ?? DiscreteShortcut(keyCode: 12, modifiers: []) // Q

    var body: some View {
        Section("Session List Shortcuts") {
            ShortcutRow(label: "Move Down", shortcut: $moveDown, storageKey: AppStorageKeys.localShortcutMoveDown)
            ShortcutRow(label: "Move Up", shortcut: $moveUp, storageKey: AppStorageKeys.localShortcutMoveUp)
            ShortcutRow(
                label: "Backburner",
                shortcut: $backburner,
                storageKey: AppStorageKeys.localShortcutBackburner
            )
            ShortcutRow(
                label: "Reactivate Selected",
                shortcut: $reactivateSelected,
                storageKey: AppStorageKeys.localShortcutReactivateSelected
            )
            ShortcutRow(
                label: "Reactivate All",
                shortcut: $reactivateAll,
                storageKey: AppStorageKeys.localShortcutReactivateAll
            )
            ShortcutRow(label: "Rename", shortcut: $rename, storageKey: AppStorageKeys.localShortcutRename)
            ShortcutRow(
                label: "Cycle Mode Forward",
                shortcut: $cycleModeForward,
                storageKey: AppStorageKeys.localShortcutCycleModeForward
            )
            ShortcutRow(
                label: "Cycle Mode Backward",
                shortcut: $cycleModeBackward,
                storageKey: AppStorageKeys.localShortcutCycleModeBackward
            )
            ShortcutRow(
                label: "Toggle Beacon",
                shortcut: $toggleBeacon,
                storageKey: AppStorageKeys.localShortcutToggleBeacon
            )
            ShortcutRow(
                label: "Auto Next",
                shortcut: $toggleAutoNext,
                storageKey: AppStorageKeys.localShortcutToggleAutoNext
            )
            ShortcutRow(
                label: "Auto Restart",
                shortcut: $toggleAutoRestart,
                storageKey: AppStorageKeys.localShortcutToggleAutoRestart
            )
        }
    }
}

struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: DiscreteShortcut?
    let storageKey: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ShortcutRecorderView($shortcut)
                .frame(width: 130)
                .padding(.trailing, 4)
                .onChange(of: shortcut) { _, newValue in
                    if let newValue {
                        newValue.save(to: storageKey)
                    } else {
                        DiscreteShortcut.remove(from: storageKey)
                    }
                    NotificationCenter.default.post(name: .localShortcutsDidChange, object: nil)
                }
        }
    }
}

struct HighlightingSettingsView: View {
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true

    @AppStorage(AppStorageKeys.useTerminalCyclingColors) private var useTerminalCyclingColors = true

    @AppStorage(AppStorageKeys.tabHighlightEnabled) private var tabHighlightEnabled = true
    @AppStorage(AppStorageKeys.tabHighlightDuration) private var tabHighlightDuration = 2.0
    @AppStorage(AppStorageKeys.tabHighlightColorRed) private var tabHighlightColorRed = 255.0
    @AppStorage(AppStorageKeys.tabHighlightColorGreen) private var tabHighlightColorGreen = 165.0
    @AppStorage(AppStorageKeys.tabHighlightColorBlue) private var tabHighlightColorBlue = 0.0

    @AppStorage(AppStorageKeys.paneHighlightEnabled) private var paneHighlightEnabled = true
    @AppStorage(AppStorageKeys.paneHighlightDuration) private var paneHighlightDuration = 1.0
    @AppStorage(AppStorageKeys.paneHighlightColorRed) private var paneHighlightColorRed = 255.0
    @AppStorage(AppStorageKeys.paneHighlightColorGreen) private var paneHighlightColorGreen = 165.0
    @AppStorage(AppStorageKeys.paneHighlightColorBlue) private var paneHighlightColorBlue = 0.0

    @AppStorage(AppStorageKeys.highlightOnHotkey) private var highlightOnHotkey = true
    @AppStorage(AppStorageKeys.highlightOnGuiSelect) private var highlightOnGuiSelect = true
    @AppStorage(AppStorageKeys.highlightOnNotification) private var highlightOnNotification = true

    private var tabHighlightColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: tabHighlightColorRed / 255,
                    green: tabHighlightColorGreen / 255,
                    blue: tabHighlightColorBlue / 255
                )
            },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    tabHighlightColorRed = components.redComponent * 255
                    tabHighlightColorGreen = components.greenComponent * 255
                    tabHighlightColorBlue = components.blueComponent * 255
                }
            }
        )
    }

    private var paneHighlightColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: paneHighlightColorRed / 255,
                    green: paneHighlightColorGreen / 255,
                    blue: paneHighlightColorBlue / 255
                )
            },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    paneHighlightColorRed = components.redComponent * 255
                    paneHighlightColorGreen = components.greenComponent * 255
                    paneHighlightColorBlue = components.blueComponent * 255
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Highlight Triggers") {
                Toggle("On hotkey cycling", isOn: $highlightOnHotkey)
                Toggle("On session select", isOn: $highlightOnGuiSelect)
                Toggle("On notification click", isOn: $highlightOnNotification)
            }

            Section("Session List") {
                SettingWithDescription(description: "Each session row gets a unique color from the palette") {
                    Toggle("Use cycling highlight colors", isOn: $useCyclingColors)
                }
            }

            Section("Terminal Highlighting") {
                Toggle("Use cycling colors", isOn: $useTerminalCyclingColors)

                Toggle("Tab bar highlighting", isOn: $tabHighlightEnabled)

                if !useTerminalCyclingColors {
                    ColorPicker("Tab color", selection: tabHighlightColor)
                        .disabled(!tabHighlightEnabled)
                }

                Picker("Tab duration", selection: $tabHighlightDuration) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .disabled(!tabHighlightEnabled)

                Toggle("Pane highlighting", isOn: $paneHighlightEnabled)

                if !useTerminalCyclingColors {
                    ColorPicker("Pane color", selection: paneHighlightColor)
                        .disabled(!paneHighlightEnabled)
                }

                Picker("Pane duration", selection: $paneHighlightDuration) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .disabled(!paneHighlightEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct UpdatesSettingsView: View {
    private let updateManager = UpdateManager.shared

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        Form {
            Section("Software Update") {
                LabeledContent("Current Version") {
                    Text(currentVersion)
                }

                Button("Check for Updates...") {
                    updateManager.checkForUpdates()
                }

                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updateManager.updater.automaticallyChecksForUpdates },
                        set: { updateManager.updater.automaticallyChecksForUpdates = $0 }
                    )
                )

                Toggle(
                    "Automatically download and install updates",
                    isOn: Binding(
                        get: { updateManager.updater.automaticallyDownloadsUpdates },
                        set: { updateManager.updater.automaticallyDownloadsUpdates = $0 }
                    )
                )
                .disabled(!updateManager.updater.automaticallyChecksForUpdates)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - SSH Settings

struct SSHSettingsView: View {
    private static let sshConfigMarker = "# Juggler: reverse-tunnel hook port"

    private let sshConfigSnippet = """
    \(sshConfigMarker)
    Host *
        RemoteForward 7483 localhost:7483
        ExitOnForwardFailure no
        SendEnv KITTY_WINDOW_ID ITERM_SESSION_ID
        ControlMaster auto
        ControlPath ~/.ssh/control-%r@%h:%p
        ControlPersist 10m
    """

    @State private var sshConfigInstalled = false
    @State private var sshConfigError: String?

    private var sshConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config").path
    }

    // Pinned to a release tag so onboarding new remotes uses a known-good revision
    // of install-remote.sh + the hook scripts it pulls. Bump on every release.
    private let installOneLiner =
        "curl -fsSL https://raw.githubusercontent.com/nielsmadan/juggler/v1.4.2/scripts/install-remote.sh | bash"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                limitationsWarning

                sshConfigStep

                stepBlock(
                    number: 2,
                    title: "Enable terminal identity forwarding",
                    description:
                    "Juggler needs the remote shell to carry its local terminal's window ID, "
                        + "otherwise clicking or cycling to the session can't focus the right tab.\n\n"
                        + "Kitty: use `kitten ssh` instead of `ssh` — it forwards the ID "
                        + "automatically, no remote changes needed.\n\n"
                        + "iTerm2 or any other terminal: add the line below to the remote's "
                        + "/etc/ssh/sshd_config (it accumulates with any existing AcceptEnv line — "
                        + "don't replace it), then reload sshd: `sudo systemctl reload ssh` on "
                        + "Linux, or `sudo launchctl kickstart -k system/com.openssh.sshd` on a "
                        + "macOS remote. Open a fresh SSH session afterward — env acceptance is "
                        + "negotiated at connect time.",
                    code: "AcceptEnv ITERM_SESSION_ID KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID"
                )

                stepBlock(
                    number: 3,
                    title: "Install the Juggler hook on the remote machine",
                    description:
                    "SSH to the remote and run this once per host. It detects which agents are "
                        + "installed (Claude Code, Codex, OpenCode) and installs the matching "
                        + "hooks, then cleans up after itself.",
                    code: installOneLiner
                )

                stepBlock(
                    number: 4,
                    title: "Verify",
                    description:
                    "Open a new SSH session, run your agent, and it should appear in Juggler's "
                        + "session list within a second. Remote sessions are tagged with an SSH "
                        + "badge showing user@host on hover.",
                    code: nil
                )
            }
            .padding()
        }
        .onAppear(perform: checkSSHConfig)
    }

    private var sshConfigStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("1.")
                    .font(.headline)
                    .frame(width: 22, alignment: .leading)
                Text("Add a reverse port forward to your SSH config")
                    .font(.headline)
                Spacer()
                if sshConfigInstalled {
                    Label("SSH config added", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Text(
                "On your Mac, append this to ~/.ssh/config. The tunnel exposes Juggler at "
                    + "localhost:7483 on every machine you ssh to. ControlMaster makes all "
                    + "sessions to a host share one connection and one tunnel, so a second "
                    + "session doesn't fight over the port; ExitOnForwardFailure=no keeps ssh "
                    + "working even if a forward can't be set up."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            codeBlock(sshConfigSnippet)

            HStack {
                Button("Add to ~/.ssh/config", action: installSSHConfig)
                    .disabled(sshConfigInstalled)
                if let error = sshConfigError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text(
                "The `SendEnv` line forwards your terminal's window ID toward the remote, but "
                    + "it only takes effect once the remote accepts it — see step 2. "
                    + "Without ControlMaster, opening a second session to the same host prints "
                    + "a harmless \"remote port forwarding failed\" warning — the new session "
                    + "reuses the first session's tunnel; ControlMaster removes the warning by "
                    + "sharing one connection outright."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func checkSSHConfig() {
        guard FileManager.default.fileExists(atPath: sshConfigPath),
              let contents = try? String(contentsOfFile: sshConfigPath, encoding: .utf8)
        else {
            sshConfigInstalled = false
            return
        }
        sshConfigInstalled = contents.contains(Self.sshConfigMarker)
    }

    private func installSSHConfig() {
        sshConfigError = nil
        let fm = FileManager.default
        let sshDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

        do {
            if !fm.fileExists(atPath: sshDir.path) {
                try fm.createDirectory(
                    at: sshDir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            // OpenSSH refuses to read configs from a directory with looser perms.
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir.path)

            // Don't use `try?` here: a decode failure would silently treat the file as empty
            // and the subsequent atomic write would clobber the user's existing config.
            let existing: String = fm.fileExists(atPath: sshConfigPath)
                ? try String(contentsOfFile: sshConfigPath, encoding: .utf8)
                : ""

            if existing.contains(Self.sshConfigMarker) {
                sshConfigInstalled = true
                return
            }

            let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            let newContents = existing + separator + "\n" + sshConfigSnippet + "\n"
            try newContents.write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sshConfigPath)
            sshConfigInstalled = true
        } catch {
            sshConfigError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track Claude Code sessions over SSH")
                .font(.title2)
                .fontWeight(.bold)
            Text(
                "Juggler can monitor Claude Code sessions running on remote Linux/macOS hosts. "
                    + "The remote sends hook events through a reverse SSH tunnel; activation and "
                    + "close-detection use the local terminal tab that holds the ssh connection."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var limitationsWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Known limitations")
                    .font(.headline)
                Text(
                    "Tmux pane focusing inside the SSH session only lands on the terminal tab, "
                        + "not the specific pane. Abrupt SSH disconnects (network drop, sleep) "
                        + "freeze the session in its last-known state until the tunnel reconnects."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private func stepBlock(number: Int, title: String, description: String, code: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.headline)
                    .frame(width: 22, alignment: .leading)
                Text(title)
                    .font(.headline)
            }
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let code {
                codeBlock(code)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func codeBlock(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color.black.opacity(0.05))
            .cornerRadius(4)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .controlSize(.small)
        }
    }
}
