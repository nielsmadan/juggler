//
//  SettingsView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import KeyboardShortcuts
import ServiceManagement
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

            HighlightingSettingsView()
                .tabItem {
                    Label("Highlighting", systemImage: "sparkles")
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
        .frame(minWidth: 450)
    }
}

struct GeneralSettingsView: View {
    @AppStorage(AppStorageKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleMode: String = SessionTitleMode.tabTitle.rawValue
    @AppStorage(AppStorageKeys.notifyOnIdle) private var notifyOnIdle = true
    @AppStorage(AppStorageKeys.notifyOnPermission) private var notifyOnPermission = true
    @AppStorage(AppStorageKeys.playSound) private var playSound = true
    @AppStorage(AppStorageKeys.enableStats) private var enableStats = true
    @AppStorage(AppStorageKeys.idleSessionColoring) private var idleSessionColoring = true

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
                            print("Failed to update launch at login: \(error)")
                            // Revert the toggle on failure
                            launchAtLogin = !newValue
                        }
                    }

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
                SettingWithDescription(description: "Color footer from green to red depending on idle session %") {
                    Toggle("Idle Status Coloring", isOn: $idleSessionColoring)
                        .disabled(!enableStats)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // Sync with actual system state
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct IntegrationSettingsView: View {
    // Permissions state
    @State private var hasAccessibility = false
    @State private var hasAutomation = false
    @State private var hasNotifications = false

    // Claude Code Hooks state
    @State private var hooksInstalled = false
    @State private var isInstallingHooks = false
    @State private var hookInstallError: String?

    // Kitty state
    @AppStorage(AppStorageKeys.kittyEnabled) private var kittyEnabled = false
    @State private var kittyInstalled = false
    @State private var kittyRemoteControl = false
    @State private var kittyListenOn = false
    @State private var kittyWatcherInstalled = false
    @State private var isInstallingKittyWatcher = false
    @State private var kittyWatcherError: String?
    @State private var kittyConfigError: String?

    // tmux configuration state
    @State private var tmuxConfigured = false
    @State private var isConfiguringTmux = false
    @State private var tmuxConfigError: String?

    // OpenCode state
    @State private var openCodePluginInstalled = false
    @State private var isInstallingOpenCodePlugin = false
    @State private var openCodeInstallError: String?

    private var hooksPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/juggler/notify.sh").path
    }

    private var tmuxConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tmux.conf").path
    }

    private var openCodePluginPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/juggler-opencode.ts").path
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

            Section("Kitty") {
                HStack {
                    Text("Kitty App")
                    Spacer()
                    if kittyInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Found", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

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
                    if !kittyRemoteControl, kittyInstalled {
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
                    if !kittyListenOn, kittyInstalled {
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
        }
    }

    // MARK: - Permissions

    private func checkPermissions() {
        hasAccessibility = AXIsProcessTrusted()
        checkAutomation()
        checkNotifications()
    }

    private func checkAutomation() {
        let script = NSAppleScript(source: "tell application \"iTerm2\" to name")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        hasAutomation = error == nil
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

        guard let scriptPath = Bundle.main.path(forResource: "install", ofType: "sh") else {
            hookInstallError = "Install script not found in bundle"
            isInstallingHooks = false
            return
        }

        Task {
            let result = await runProcess(executableURL: "/bin/bash", arguments: [scriptPath])
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

    private var kittyConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/kitty/kitty.conf").path
    }

    private func checkKittyStatus() {
        kittyInstalled = FileManager.default.fileExists(atPath: "/Applications/kitty.app")

        if let contents = try? String(contentsOfFile: kittyConfPath, encoding: .utf8) {
            kittyRemoteControl = contents.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("#") && trimmed.hasPrefix("allow_remote_control")
                    && (trimmed.contains("yes") || trimmed.contains("socket"))
            }
            kittyListenOn = contents.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("listen_on") && !trimmed.hasPrefix("#")
            }
            kittyWatcherInstalled = contents.contains("juggler_watcher.py")
        } else {
            kittyRemoteControl = false
            kittyListenOn = false
            kittyWatcherInstalled = false
        }
    }

    private func appendToKittyConf(_ line: String) {
        kittyConfigError = nil

        do {
            let fileURL = URL(fileURLWithPath: kittyConfPath)
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/kitty")

            // Create config directory if needed
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: kittyConfPath) {
                let existingContent = try String(contentsOfFile: kittyConfPath, encoding: .utf8)
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()

                var lineToAppend = line + "\n"
                if !existingContent.isEmpty, !existingContent.hasSuffix("\n") {
                    lineToAppend = "\n" + lineToAppend
                }

                handle.write(Data(lineToAppend.utf8))
                handle.closeFile()
            } else {
                try (line + "\n").write(toFile: kittyConfPath, atomically: true, encoding: .utf8)
            }

            checkKittyStatus()
        } catch {
            kittyConfigError = "Failed to update kitty.conf: \(error.localizedDescription)"
        }
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

        guard let scriptPath = Bundle.main.path(forResource: "install_kitty_watcher", ofType: "sh") else {
            kittyWatcherError = "Install script not found in bundle"
            isInstallingKittyWatcher = false
            return
        }

        Task {
            let result = await runProcess(executableURL: "/bin/bash", arguments: [scriptPath])
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
            tmuxConfigured = contents.contains("update-environment")
                && (contents.contains("ITERM_SESSION_ID") || contents.contains("KITTY_WINDOW_ID"))
        } catch {
            tmuxConfigured = false
        }
    }

    private func configureTmux() {
        isConfiguringTmux = true
        tmuxConfigError = nil

        do {
            let fileURL = URL(fileURLWithPath: tmuxConfPath)

            if FileManager.default.fileExists(atPath: tmuxConfPath) {
                let existingContent = try String(contentsOfFile: tmuxConfPath, encoding: .utf8)
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()

                var lineToAppend = tmuxUpdateEnvironmentLine + "\n"
                if !existingContent.isEmpty, !existingContent.hasSuffix("\n") {
                    lineToAppend = "\n" + lineToAppend
                }

                handle.write(Data(lineToAppend.utf8))
                handle.closeFile()
            } else {
                try (tmuxUpdateEnvironmentLine + "\n").write(toFile: tmuxConfPath, atomically: true, encoding: .utf8)
            }

            checkTmuxConfigured()
        } catch {
            tmuxConfigError = "Failed to update ~/.tmux.conf: \(error.localizedDescription)"
        }

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

private struct SettingWithDescription<Content: View>: View {
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                    description: "First press opens the menu bar popover, second press opens the monitor window."
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
    @State private var moveDown = LocalShortcut.load(from: AppStorageKeys.localShortcutMoveDown)
    @State private var moveUp = LocalShortcut.load(from: AppStorageKeys.localShortcutMoveUp)
    @State private var backburner = LocalShortcut.load(from: AppStorageKeys.localShortcutBackburner)
    @State private var reactivateSelected = LocalShortcut.load(from: AppStorageKeys.localShortcutReactivateSelected)
    @State private var reactivateAll = LocalShortcut.load(from: AppStorageKeys.localShortcutReactivateAll)
    @State private var rename = LocalShortcut.load(from: AppStorageKeys.localShortcutRename)
    @State private var cycleModeForward = LocalShortcut.load(from: AppStorageKeys.localShortcutCycleModeForward)
    @State private var cycleModeBackward = LocalShortcut.load(from: AppStorageKeys.localShortcutCycleModeBackward)
    @State private var togglePause: LocalShortcut? = LocalShortcut.load(from: AppStorageKeys.localShortcutTogglePause)
        ?? LocalShortcut(keyCode: 1, modifiers: []) // S
    @State private var resetStats: LocalShortcut? = LocalShortcut.load(from: AppStorageKeys.localShortcutResetStats)
        ?? LocalShortcut(keyCode: 1, modifiers: .shift) // ⇧S

    var body: some View {
        Section("Session List Shortcuts") {
            LocalShortcutRow(label: "Move Down", shortcut: $moveDown, storageKey: AppStorageKeys.localShortcutMoveDown)
            LocalShortcutRow(label: "Move Up", shortcut: $moveUp, storageKey: AppStorageKeys.localShortcutMoveUp)
            LocalShortcutRow(
                label: "Backburner",
                shortcut: $backburner,
                storageKey: AppStorageKeys.localShortcutBackburner
            )
            LocalShortcutRow(
                label: "Reactivate Selected",
                shortcut: $reactivateSelected,
                storageKey: AppStorageKeys.localShortcutReactivateSelected
            )
            LocalShortcutRow(
                label: "Reactivate All",
                shortcut: $reactivateAll,
                storageKey: AppStorageKeys.localShortcutReactivateAll
            )
            LocalShortcutRow(label: "Rename", shortcut: $rename, storageKey: AppStorageKeys.localShortcutRename)
            LocalShortcutRow(
                label: "Cycle Mode Forward",
                shortcut: $cycleModeForward,
                storageKey: AppStorageKeys.localShortcutCycleModeForward
            )
            LocalShortcutRow(
                label: "Cycle Mode Backward",
                shortcut: $cycleModeBackward,
                storageKey: AppStorageKeys.localShortcutCycleModeBackward
            )
            LocalShortcutRow(
                label: "Start/Pause Stats",
                shortcut: $togglePause,
                storageKey: AppStorageKeys.localShortcutTogglePause
            )
            LocalShortcutRow(
                label: "Reset Stats",
                shortcut: $resetStats,
                storageKey: AppStorageKeys.localShortcutResetStats
            )
        }
    }
}

struct LocalShortcutRow: View {
    let label: String
    @Binding var shortcut: LocalShortcut?
    let storageKey: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            LocalShortcutRecorderView(shortcut: $shortcut, storageKey: storageKey)
                .frame(width: 130)
                .padding(.trailing, 4)
        }
    }
}

struct HighlightingSettingsView: View {
    // Session list highlighting
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true

    // Terminal highlighting cycling
    @AppStorage(AppStorageKeys.useTerminalCyclingColors) private var useTerminalCyclingColors = true

    // Tab bar settings
    @AppStorage(AppStorageKeys.tabHighlightEnabled) private var tabHighlightEnabled = true
    @AppStorage(AppStorageKeys.tabHighlightDuration) private var tabHighlightDuration = 2.0
    @AppStorage(AppStorageKeys.tabHighlightColorRed) private var tabHighlightColorRed = 255.0
    @AppStorage(AppStorageKeys.tabHighlightColorGreen) private var tabHighlightColorGreen = 165.0
    @AppStorage(AppStorageKeys.tabHighlightColorBlue) private var tabHighlightColorBlue = 0.0

    // Pane settings
    @AppStorage(AppStorageKeys.paneHighlightEnabled) private var paneHighlightEnabled = true
    @AppStorage(AppStorageKeys.paneHighlightDuration) private var paneHighlightDuration = 1.0
    @AppStorage(AppStorageKeys.paneHighlightColorRed) private var paneHighlightColorRed = 255.0
    @AppStorage(AppStorageKeys.paneHighlightColorGreen) private var paneHighlightColorGreen = 165.0
    @AppStorage(AppStorageKeys.paneHighlightColorBlue) private var paneHighlightColorBlue = 0.0

    // Per-trigger highlighting
    @AppStorage(AppStorageKeys.highlightOnHotkey) private var highlightOnHotkey = true
    @AppStorage(AppStorageKeys.highlightOnGuiSelect) private var highlightOnGuiSelect = true
    @AppStorage(AppStorageKeys.highlightOnNotification) private var highlightOnNotification = true

    // Backburner behavior
    @AppStorage(AppStorageKeys.goToNextOnBackburner) private var goToNextOnBackburner = true

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

            Section("Tab Bar") {
                Toggle("Enable tab bar highlighting", isOn: $tabHighlightEnabled)

                Toggle("Use cycling colors", isOn: $useTerminalCyclingColors)
                    .disabled(!tabHighlightEnabled)

                if !useTerminalCyclingColors {
                    ColorPicker("Color", selection: tabHighlightColor)
                        .disabled(!tabHighlightEnabled)
                }

                Picker("Duration", selection: $tabHighlightDuration) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .disabled(!tabHighlightEnabled)
            }

            Section("Pane Background") {
                Toggle("Enable pane highlighting", isOn: $paneHighlightEnabled)

                if !useTerminalCyclingColors {
                    ColorPicker("Color", selection: paneHighlightColor)
                        .disabled(!paneHighlightEnabled)
                }

                Picker("Duration", selection: $paneHighlightDuration) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .disabled(!paneHighlightEnabled)
            }

            Section("Backburner") {
                Toggle("Go to next session on backburner", isOn: $goToNextOnBackburner)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

enum OpenCodePluginInstaller {
    static let pluginContent = """
        // Juggler plugin for OpenCode
        // Installed to ~/.config/opencode/plugins/juggler-opencode.ts
        // Posts session events to Juggler's HTTP server for session tracking

        const JUGGLER_PORT = process.env.JUGGLER_PORT || "7483";
        const JUGGLER_URL = `http://localhost:${JUGGLER_PORT}/hook`;

        // Detect terminal type from environment
        function getTerminalInfo(): Record<string, string> {
          const env = process.env;
          const info: Record<string, string> = {
            cwd: process.cwd(),
          };

          if (env.KITTY_WINDOW_ID) {
            info.terminalType = "kitty";
            info.sessionId = env.KITTY_WINDOW_ID;
            if (env.KITTY_LISTEN_ON) info.kittyListenOn = env.KITTY_LISTEN_ON;
            if (env.KITTY_PID) info.kittyPid = env.KITTY_PID;
          } else if (env.ITERM_SESSION_ID) {
            info.terminalType = "iterm2";
            info.sessionId = env.ITERM_SESSION_ID;
          }

          return info;
        }

        // Get git info from working directory
        async function getGitInfo(
          $: any
        ): Promise<{ branch: string; repo: string } | null> {
          try {
            const branch = (await $`git rev-parse --abbrev-ref HEAD 2>/dev/null`)
              .text()
              .trim();
            const toplevel = (await $`git rev-parse --show-toplevel 2>/dev/null`)
              .text()
              .trim();
            const repo = toplevel.split("/").pop() || "";
            return { branch, repo };
          } catch {
            return null;
          }
        }

        // Get tmux info if running inside tmux
        function getTmuxInfo(): Record<string, string> | null {
          const pane = process.env.TMUX_PANE;
          if (!pane) return null;
          return { pane };
        }

        // Events we care about for session tracking
        const TRACKED_EVENTS = new Set([
          "session.created",
          "session.status",
          "session.deleted",
          "session.compacted",
          "permission.asked",
          "server.instance.disposed",
        ]);

        export const JugglerPlugin = async ({
          $,
        }: {
          project: any;
          client: any;
          $: any;
          directory: string;
          worktree: string;
        }) => {
          const terminal = getTerminalInfo();
          const git = await getGitInfo($);
          const tmux = getTmuxInfo();

          // Post session.created on plugin load so Juggler sees the session immediately,
          // even when OpenCode resumes a previous session (which skips session.created)
          await postEvent("session.created");

          async function postEvent(eventType: string, sessionId?: string) {
            const payload: Record<string, any> = {
              agent: "opencode",
              event: eventType,
              terminal,
            };

            if (sessionId) {
              payload.hookInput = { session_id: sessionId };
            }

            if (git) {
              payload.git = git;
            }

            if (tmux) {
              payload.tmux = tmux;
            }

            try {
              await fetch(JUGGLER_URL, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload),
                signal: AbortSignal.timeout(2000),
              });
            } catch {
              // Juggler not running — silently ignore
            }
          }

          return {
            event: async ({
              event,
            }: {
              event: { type: string; [key: string]: any };
            }) => {
              if (!TRACKED_EVENTS.has(event.type)) return;

              const sessionId =
                (event as any).properties?.sessionID ||
                (event as any).properties?.info?.id ||
                (event as any).session_id ||
                (event as any).sessionID;

              // Translate session.status into synthetic event with status type
              let eventName = event.type;
              if (event.type === "session.status") {
                const status = (event as any).properties?.status?.type;
                if (!status) return;
                eventName = `session.status.${status}`;
              }

              await postEvent(eventName, sessionId);
            },
          };
        };
        """

    static func install() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pluginsDir = home.appendingPathComponent(".config/opencode/plugins")
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let pluginFile = pluginsDir.appendingPathComponent("juggler-opencode.ts")
        try pluginContent.write(to: pluginFile, atomically: true, encoding: .utf8)
    }
}

/// Run a process asynchronously without blocking the main thread.
/// Returns nil on success, or an error message string on failure.
func runProcess(executableURL: String, arguments: [String]) async -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executableURL)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        return error.localizedDescription
    }

    return await withCheckedContinuation { continuation in
        process.terminationHandler = { proc in
            if proc.terminationStatus == 0 {
                continuation.resume(returning: nil)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: output.isEmpty ? "Process failed" : output)
            }
        }
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
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
