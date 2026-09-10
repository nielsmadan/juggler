//
//  SettingsView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import ServiceManagement
import ShortcutKit
import ShortcutKitUI
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
    @AppStorage(AppStorageKeys.playSound) private var playSound = false
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
                    "Removes all integrations (Claude Code hooks, Kitty watcher, OpenCode plugin, Pi extension, Antigravity hooks), resets Automation permission, clears settings, and quits the app."
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

    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "com.nielsmadan.Juggler"
    }

    private func performUninstall() async -> String {
        var actions: [String] = []
        actions += await unregisterLoginItem()
        actions += await runIntegrationCleanup()
        actions += clearDefaults()
        actions += clearCaches()
        return actions.joined(separator: "\n")
    }

    private func unregisterLoginItem() async -> [String] {
        try? await SMAppService.mainApp.unregister()
        return ["Removed login item"]
    }

    private func runIntegrationCleanup() async -> [String] {
        var actions: [String] = []
        if Bundle.main.path(forResource: "uninstall", ofType: "sh") != nil {
            if let error = await ScriptInstaller.runBundledScript(resource: "uninstall") {
                actions.append("Integration cleanup failed: \(error)")
            } else {
                actions.append("Removed Juggler integrations; hooks shared with other apps remain installed")
                actions.append("Reset Automation permission")
            }
        }
        return actions
    }

    private func clearDefaults() -> [String] {
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
        UserDefaults.standard.synchronize()
        return ["Cleared all settings"]
    }

    private func clearCaches() -> [String] {
        let fm = FileManager.default
        guard let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
        let appCache = cachesDir.appendingPathComponent(bundleId)
        guard fm.fileExists(atPath: appCache.path) else { return [] }
        try? fm.removeItem(at: appCache)
        return ["Cleared caches"]
    }
}

struct IntegrationSettingsView: View {
    @AppStorage(AppStorageKeys.codexIgnorePermissionEvents) private var codexIgnorePermissionEvents = false

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

    @State private var wezTermCliFound = false

    @State private var tmuxConfigured = false
    @State private var isConfiguringTmux = false
    @State private var tmuxConfigError: String?

    @State private var openCodePluginInstalled = false
    @State private var isInstallingOpenCodePlugin = false
    @State private var openCodeInstallError: String?

    @State private var codexController = CodexSetupController()

    @State private var piExtensionInstalled = false
    @State private var isInstallingPiExtension = false
    @State private var piInstallError: String?

    @State private var droidHooksInstalled = false
    @State private var isInstallingDroidHooks = false
    @State private var droidInstallError: String?

    @State private var qwenHooksInstalled = false
    @State private var isInstallingQwenHooks = false
    @State private var qwenInstallError: String?

    @State private var kimiHooksInstalled = false
    @State private var isInstallingKimiHooks = false
    @State private var kimiInstallError: String?

    @State private var antigravityController = AntigravitySetupController()

    @State private var showingSSHSheet = false

    private var tmuxConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tmux.conf").path
    }

    private let tmuxUpdateEnvironmentLine =
        "set-option -ga update-environment ' ITERM_SESSION_ID KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID WEZTERM_PANE'"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                permissionsForm

                categoryHeader("Terminals")
                terminalsForm

                categoryHeader("Agents")
                agentsForm

                categoryHeader("Tools")
                toolsForm
            }
        }
        .sheet(isPresented: $showingSSHSheet) {
            SSHSettingsSheet()
        }
        .onAppear {
            checkPermissions()
            checkKittyStatus()
            checkWezTermStatus()
            checkTmuxConfigured()
            codexController.initializePermissionEventPreference()
            codexController.refresh()
            antigravityController.refresh()
        }
        .task {
            await refreshAgentHookStatus()
        }
    }

    private func refreshAgentHookStatus() async {
        hooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .claude)
        openCodePluginInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .opencode)
        piExtensionInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .pi)
        droidHooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .droid)
        qwenHooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .qwen)
        kimiHooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .kimi)
    }

    private func categoryHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
            .underline()
            .padding(.horizontal, 112)
    }

    private var permissionsForm: some View {
        Form {
            Section("Permissions") {
                PermissionRow(label: "Notifications", granted: hasNotifications) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Notifications")!
                    )
                }
                Button("Refresh") {
                    checkPermissions()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
    }

    private var terminalsForm: some View {
        Form {
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

            Section("iTerm2") {
                PermissionRow(label: "Automation Permission", granted: hasAutomation) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                    )
                }
            }

            Section("WezTerm") {
                HStack {
                    Text("wezterm CLI")
                    Spacer()
                    if wezTermCliFound {
                        Label("Found", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Found", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(
                    "Juggler activates WezTerm panes via the wezterm CLI — no configuration needed. Highlighting and focus-sync aren't available for WezTerm."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
    }

    private var agentsForm: some View {
        Form {
            Section("Claude Code") {
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
                SettingWithDescription(
                    description: "Codex emits the same permission event before Auto Review and manual approval. "
                        + "Ignoring it prevents Auto Review from briefly putting the session in Juggler's permission "
                        + "queue, but also hides manual permission prompts. On first setup, Juggler preselects this "
                        + "from the global Codex config; profile and command-line overrides are not detected."
                ) {
                    Toggle("Ignore Codex permission events", isOn: $codexIgnorePermissionEvents)
                }

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

            Section("Pi") {
                HStack {
                    Text("Extension")
                    Spacer()
                    if piExtensionInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = piInstallError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(piExtensionInstalled ? "Reinstall Extension" : "Install Extension") {
                    installPiExtension()
                }
                .disabled(isInstallingPiExtension)

                if piExtensionInstalled {
                    Text("Restart Pi or run /reload for it to take effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Factory Droid") {
                HStack {
                    Text("Hook Script")
                    Spacer()
                    if droidHooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = droidInstallError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(droidHooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    installDroidHooks()
                }
                .disabled(isInstallingDroidHooks)

                if droidHooksInstalled {
                    Text("Droid reads hooks at startup — restart a running droid session for it to take effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Qwen Code") {
                HStack {
                    Text("Hook Script")
                    Spacer()
                    if qwenHooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = qwenInstallError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(qwenHooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    installQwenHooks()
                }
                .disabled(isInstallingQwenHooks)
            }

            Section("Kimi Code") {
                HStack {
                    Text("Hook Script")
                    Spacer()
                    if kimiHooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = kimiInstallError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(kimiHooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    installKimiHooks()
                }
                .disabled(isInstallingKimiHooks)
            }

            Section("Antigravity") {
                HStack {
                    Text("Hook Script")
                    Spacer()
                    if antigravityController.hooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = antigravityController.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(antigravityController.hooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    antigravityController.installHooks()
                }
                .disabled(antigravityController.isInstallingHooks)

                Text(
                    "No permission or compaction events for agy sessions. Requires Antigravity CLI 1.0.8+; Juggler picks up the hooks on its next run."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
    }

    private var toolsForm: some View {
        Form {
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

            Section("SSH Tracking") {
                Text("Track Claude Code sessions on remote hosts via reverse port forward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Configure SSH") {
                    showingSSHSheet = true
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
    }

    // MARK: - Permissions

    private func checkPermissions() {
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
            let authorized = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                hasNotifications = authorized
            }
        }
    }

    // MARK: - Claude Code Hooks

    private func installHooks() {
        isInstallingHooks = true
        hookInstallError = nil

        Task {
            if let error = await ScriptInstaller.installHooks() {
                hookInstallError = error
            }
            hooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .claude)
            isInstallingHooks = false
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

    // MARK: - WezTerm

    private func checkWezTermStatus() {
        // Use the bridge's own resolution (fixed paths + PATH) so the status can't disagree
        // with what the bridge would actually run.
        wezTermCliFound = WezTermBridge.locateCLI() != nil
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

    private func installOpenCodePlugin() {
        isInstallingOpenCodePlugin = true
        openCodeInstallError = nil

        Task {
            do {
                try await OpenCodePluginInstaller.install()
            } catch {
                openCodeInstallError = error.localizedDescription
            }
            openCodePluginInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .opencode)
            isInstallingOpenCodePlugin = false
        }
    }

    private func installPiExtension() {
        isInstallingPiExtension = true
        piInstallError = nil

        Task {
            do {
                try await PiExtensionInstaller.install()
            } catch {
                piInstallError = error.localizedDescription
            }
            piExtensionInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .pi)
            isInstallingPiExtension = false
        }
    }

    // MARK: - Factory Droid Hooks

    private func installDroidHooks() {
        isInstallingDroidHooks = true
        droidInstallError = nil

        Task {
            let result = await HooklinesinkerClient.shared.installHooks(agent: .droid)
            if !result.isSuccess {
                droidInstallError = result.failureMessage
            }
            droidHooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .droid)
            isInstallingDroidHooks = false
        }
    }

    // MARK: - Qwen Code Hooks

    private func installQwenHooks() {
        isInstallingQwenHooks = true
        qwenInstallError = nil

        Task {
            let result = await HooklinesinkerClient.shared.installHooks(agent: .qwen)
            if !result.isSuccess {
                qwenInstallError = result.failureMessage
            }
            qwenHooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .qwen)
            isInstallingQwenHooks = false
        }
    }

    // MARK: - Kimi Code Hooks

    private func installKimiHooks() {
        isInstallingKimiHooks = true
        kimiInstallError = nil

        Task {
            let result = await HooklinesinkerClient.shared.installHooks(agent: .kimi)
            if !result.isSuccess {
                kimiInstallError = result.failureMessage
            }
            kimiHooksInstalled = await HooklinesinkerClient.shared.isInstalled(agent: .kimi)
            isInstallingKimiHooks = false
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
        // Juggler's "Display" section sits above the per-context shortcut lists in
        // one native grouped Form. `.embedded` emits one Section per context
        // (Global, Session List) with no scroll/card of its own, so it reads as a
        // native macOS settings pane — matching the pre-ShortcutKit layout.
        Form {
            Section("Display") {
                Toggle("Show Shortcut Helper", isOn: $showShortcutHelper)
                HintPreferencesView(registry: ShortcutCenter.shared.registry)
            }
            KeyBindingsView(
                registry: ShortcutCenter.shared.registry,
                style: .regular,
                presentation: .embedded,
                showsDescriptions: true
            )
        }
        .formStyle(.grouped)
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

                Text(
                    "Terminal highlighting applies to iTerm2 and Kitty only. WezTerm has no external tab/pane coloring, so its sessions activate without a highlight."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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

private struct SSHSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            SSHSettingsView()
        }
        .frame(minWidth: 560, minHeight: 640, idealHeight: 760)
    }
}

/// The two snippets the SSH tab tells the user to run. Extracted so the env-var interface
/// they hand to `scripts/install-remote.sh` can be pinned by a test — the one-liner and the
/// script are edited in different places and have drifted apart before.
enum RemoteSetupSnippets {
    static func installOneLiner(revision: String, sink: String) -> String {
        "curl -fsSL https://raw.githubusercontent.com/nielsmadan/juggler/\(revision)"
            + "/scripts/install-remote.sh | JUGGLER_SINK=\(sink) bash"
    }

    static func sshConfig(marker: String, port: UInt16) -> String {
        """
        \(marker)
        Host *
            RemoteForward \(port) localhost:\(port)
            ExitOnForwardFailure no
            SendEnv KITTY_WINDOW_ID ITERM_SESSION_ID
            ControlMaster auto
            ControlPath ~/.ssh/control-%r@%h:%p
            ControlPersist 10m
        """
    }
}

struct SSHSettingsView: View {
    private static let sshConfigMarker = "# Juggler: reverse-tunnel hook port"

    private var hookPort: UInt16 { TestInstanceConfig.hookPort() }

    private var sshConfigSnippet: String {
        RemoteSetupSnippets.sshConfig(marker: Self.sshConfigMarker, port: hookPort)
    }

    @State private var sshConfigInstalled = false
    @State private var sshConfigError: String?

    private var sshConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config").path
    }

    // `just release` advances this to an immutable release-preparation commit.
    private static let installRevision = "d8b864f579e10fe0680a27b4b05324ebdc4e9b76"
    private var installOneLiner: String {
        RemoteSetupSnippets.installOneLiner(
            revision: Self.installRevision,
            sink: HooklinesinkerClient.shared.sinkURL
        )
    }

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
                    "SSH to the remote and run this once per host. It downloads a "
                        + "checksum-verified hooklinesinker release for the remote's "
                        + "architecture, points it back at this Juggler through the tunnel, and "
                        + "installs hooks for whichever agents are there (Claude Code, Codex, "
                        + "OpenCode, Pi). Codex additionally needs its hooks trusted on that "
                        + "host — the script prints the two steps.",
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
                    + "localhost:\(hookPort) on every machine you ssh to. ControlMaster makes all "
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
