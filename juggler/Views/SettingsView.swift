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

    // tmux configuration state
    @State private var tmuxConfigured = false
    @State private var isConfiguringTmux = false
    @State private var tmuxConfigError: String?

    private var hooksPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/juggler/notify.sh").path
    }

    private var tmuxConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tmux.conf").path
    }

    private let tmuxUpdateEnvironmentLine = "set-option -ga update-environment ' ITERM_SESSION_ID'"

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

            Section("tmux") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("ITERM_SESSION_ID in update-environment")
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
            checkTmuxConfigured()
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

    // MARK: - tmux Configuration

    private func checkTmuxConfigured() {
        guard FileManager.default.fileExists(atPath: tmuxConfPath) else {
            tmuxConfigured = false
            return
        }

        do {
            let contents = try String(contentsOfFile: tmuxConfPath, encoding: .utf8)
            tmuxConfigured = contents.contains("update-environment") && contents.contains("ITERM_SESSION_ID")
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
