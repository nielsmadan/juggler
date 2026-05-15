//
//  IntegrationHubView.swift
//  Juggler
//

import SwiftUI

struct IntegrationHubView: View {
    let onContinue: () -> Void

    @AppStorage(AppStorageKeys.iterm2Enabled) private var iterm2Enabled = true
    @AppStorage(AppStorageKeys.kittyEnabled) private var kittyEnabled = false
    @AppStorage(AppStorageKeys.codexEnabled) private var codexEnabled = false

    @State private var showingITerm2Setup = false
    @State private var showingKittySetup = false
    @State private var showingTmuxSetup = false
    @State private var showingClaudeCodeSetup = false
    @State private var showingOpenCodeSetup = false
    @State private var showingCodexSetup = false

    @State private var iterm2Configured = false
    @State private var kittyConfigured = false
    @State private var tmuxConfigured = false
    @State private var claudeCodeConfigured = false
    @State private var openCodeConfigured = false
    @State private var codexConfigured = false

    @State private var showingIncompleteAlert = false

    var hasAnyTerminal: Bool {
        iterm2Configured || kittyConfigured
    }

    var hasAnyAgent: Bool {
        claudeCodeConfigured || openCodeConfigured || codexConfigured
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)

            Text("Set Up Integrations")
                .font(.title)
                .fontWeight(.bold)

            Text("Select the terminals you use. You can configure multiple.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Terminals")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IntegrationCard(
                    icon: "terminal.fill",
                    title: "iTerm2",
                    description: "macOS terminal with Python API",
                    isConfigured: iterm2Configured,
                    action: { showingITerm2Setup = true }
                )

                IntegrationCard(
                    icon: "cat.fill",
                    title: "Kitty",
                    description: "GPU-accelerated terminal with remote control",
                    isConfigured: kittyConfigured,
                    action: { showingKittySetup = true }
                )
            }

            VStack(spacing: 8) {
                Text("Multiplexer (Optional)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IntegrationCard(
                    icon: "rectangle.split.3x1",
                    title: "tmux",
                    description: "Env forwarding for terminal session tracking",
                    isConfigured: tmuxConfigured,
                    action: { showingTmuxSetup = true }
                )
            }

            VStack(spacing: 8) {
                Text("Agents")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IntegrationCard(
                    icon: "brain",
                    title: "Claude Code",
                    description: "Install hooks for session tracking",
                    isConfigured: claudeCodeConfigured,
                    action: { showingClaudeCodeSetup = true }
                )

                IntegrationCard(
                    icon: "hammer",
                    title: "OpenCode",
                    description: "Install plugin for session tracking",
                    isConfigured: openCodeConfigured,
                    action: { showingOpenCodeSetup = true }
                )

                IntegrationCard(
                    icon: "barcode",
                    title: "Codex",
                    description: "Install hooks for session tracking (experimental)",
                    isConfigured: codexConfigured,
                    action: { showingCodexSetup = true }
                )
            }

            Button("Continue") {
                if hasAnyTerminal, hasAnyAgent {
                    onContinue()
                } else {
                    showingIncompleteAlert = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .alert("Incomplete Setup", isPresented: $showingIncompleteAlert) {
            Button("Go Back", role: .cancel) {}
            Button("Continue Anyway", role: .destructive) {
                onContinue()
            }
        } message: {
            Text("Juggler needs at least one terminal and one agent integration to function correctly.")
        }
        .sheet(isPresented: $showingITerm2Setup) {
            ITerm2SetupView(isConfigured: $iterm2Configured, isEnabled: $iterm2Enabled)
                .frame(width: 540, height: 480)
        }
        .sheet(isPresented: $showingKittySetup) {
            KittySetupView(isConfigured: $kittyConfigured, isEnabled: $kittyEnabled)
                .frame(width: 540, height: 540)
        }
        .sheet(isPresented: $showingTmuxSetup) {
            TmuxSetupView(isConfigured: $tmuxConfigured)
                .frame(width: 540, height: 420)
        }
        .sheet(isPresented: $showingClaudeCodeSetup) {
            ClaudeCodeSetupView(isConfigured: $claudeCodeConfigured)
                .frame(width: 540, height: 420)
        }
        .sheet(isPresented: $showingOpenCodeSetup) {
            OpenCodeSetupView(isConfigured: $openCodeConfigured)
                .frame(width: 540, height: 420)
        }
        .sheet(isPresented: $showingCodexSetup) {
            CodexSetupView(isConfigured: $codexConfigured, isEnabled: $codexEnabled)
                .frame(width: 540, height: 560)
        }
    }
}

struct IntegrationCard: View {
    let icon: String
    let title: String
    let description: String
    let isConfigured: Bool
    var isDisabled: Bool = false
    var isAlwaysEnabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundStyle(isDisabled ? .secondary : .primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isAlwaysEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.opacity(0.5))
                } else if isDisabled {
                    Text("Coming Soon")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - iTerm2 Setup (extracted from OnboardingView)

struct ITerm2SetupView: View {
    @Binding var isConfigured: Bool
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var runtimeInstalled = false
    @State private var isITerm2Running = false
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            Text("iTerm2 Setup")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: runtimeInstalled,
                    title: "Install Python Runtime",
                    detail: "iTerm2 → Scripts → Manage → Install Python Runtime"
                )

                SetupStep(
                    number: 2,
                    isComplete: runtimeInstalled,
                    title: "Enable Python API",
                    detail: "iTerm2 → Settings → General → Magic → Enable Python API"
                )

                SetupStep(
                    number: 3,
                    isComplete: runtimeInstalled,
                    title: "Grant Automation Permission",
                    detail: "Click \"Check\" below - macOS will prompt for access"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            if isITerm2Running {
                Button("Check") {
                    checkRuntime()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open iTerm2") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            if runtimeInstalled {
                Button("Done") {
                    isConfigured = true
                    isEnabled = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding()
        .onAppear {
            checkITerm2Running()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    checkITerm2Running()
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func checkITerm2Running() {
        isITerm2Running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }
    }

    private func checkRuntime() {
        let script = """
        tell application "iTerm2" to request cookie and key for app named "Juggler"
        """

        Task { @MainActor in
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                runtimeInstalled = (error == nil && result.stringValue != nil)
            }
        }
    }
}

// MARK: - tmux Setup

struct TmuxSetupView: View {
    @Binding var isConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var envConfigured = false
    @State private var isConfiguring = false
    @State private var configError: String?

    private var tmuxConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tmux.conf").path
    }

    private let updateEnvironmentLine =
        "set-option -ga update-environment ' ITERM_SESSION_ID KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID'"

    var body: some View {
        VStack(spacing: 16) {
            Text("tmux Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Juggler needs terminal env vars forwarded into tmux sessions so it can identify which terminal each session runs in."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: envConfigured,
                    title: "Add update-environment to ~/.tmux.conf",
                    detail: "Forwards ITERM_SESSION_ID, KITTY_WINDOW_ID, KITTY_LISTEN_ON, and KITTY_PID into tmux sessions"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            if let error = configError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if !envConfigured {
                Button("Add to ~/.tmux.conf") {
                    configureTmux()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConfiguring)

                Text("Restart tmux after changes for them to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if envConfigured {
                Button("Done") {
                    isConfigured = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding()
        .onAppear {
            checkTmuxConfigured()
        }
    }

    private func checkTmuxConfigured() {
        guard FileManager.default.fileExists(atPath: tmuxConfPath),
              let contents = try? String(contentsOfFile: tmuxConfPath, encoding: .utf8)
        else {
            envConfigured = false
            return
        }
        envConfigured = TmuxConfigValidator.isConfigured(contents: contents)
    }

    private func configureTmux() {
        isConfiguring = true
        configError = ConfigFileWriter.appendLine(
            updateEnvironmentLine,
            toFileAt: tmuxConfPath,
            duplicateCheck: .exactMatch
        )
        checkTmuxConfigured()
        isConfiguring = false
    }
}

// MARK: - Claude Code Setup

struct ClaudeCodeSetupView: View {
    @Binding var isConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var errorMessage: String?

    private var hooksPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/juggler/notify.sh").path
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Claude Code Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Juggler needs to install hooks in ~/.claude/hooks to detect when Claude Code sessions become idle or need input."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: isInstalled,
                    title: "Install Hooks",
                    detail: "Adds notify.sh to ~/.claude/hooks/juggler/"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            if isInstalled {
                Label("Hooks Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if !isInstalled {
                Button("Install Hooks") {
                    installHooks()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)
            }

            Spacer()

            if isInstalled {
                Button("Done") {
                    isConfigured = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding()
        .onAppear {
            isInstalled = FileManager.default.fileExists(atPath: hooksPath)
        }
    }

    private func installHooks() {
        isInstalling = true
        errorMessage = nil

        Task {
            let result = await ScriptInstaller.installHooks()
            await MainActor.run {
                if let error = result {
                    errorMessage = error
                } else {
                    isInstalled = true
                }
                isInstalling = false
            }
        }
    }
}

// MARK: - OpenCode Setup

struct OpenCodeSetupView: View {
    @Binding var isConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var errorMessage: String?

    private var pluginPath: String {
        OpenCodePluginInstaller.pluginFilePath
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("OpenCode Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Juggler needs to install a plugin for OpenCode to detect when sessions become idle or need input."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: isInstalled,
                    title: "Install Plugin",
                    detail: "Adds juggler-opencode.ts to the OpenCode plugins directory"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            if isInstalled {
                Label("Plugin Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if !isInstalled {
                Button("Install Plugin") {
                    installPlugin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)
            }

            Spacer()

            if isInstalled {
                Button("Done") {
                    isConfigured = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding()
        .onAppear {
            isInstalled = FileManager.default.fileExists(atPath: pluginPath)
        }
    }

    private func installPlugin() {
        isInstalling = true
        errorMessage = nil

        do {
            try OpenCodePluginInstaller.install()
            isInstalled = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isInstalling = false
    }
}

// MARK: - Codex Setup

struct CodexSetupView: View {
    @Binding var isConfigured: Bool
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var controller = CodexSetupController()

    var body: some View {
        VStack(spacing: 16) {
            Text("Codex Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Juggler installs hooks for Codex, enables the hooks feature flag, and trusts the hooks so Codex runs them."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: controller.hooksInstalled,
                    title: "Install Hooks",
                    detail: "Adds notify.sh and hooks.json to ~/.codex/hooks/juggler/"
                )

                SetupStep(
                    number: 2,
                    isComplete: controller.featureFlagEnabled,
                    title: "Enable Feature Flag",
                    detail: "Sets features.hooks = true in ~/.codex/config.toml"
                )

                SetupStep(
                    number: 3,
                    isComplete: controller.enabledInCodex,
                    title: "Enable in Codex",
                    detail: "Trusts Juggler's hooks so Codex runs them"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Text(
                "\"Enable in Codex\" bypasses Codex's own hook review. Alternatively, run /hooks in Codex and trust the Juggler hooks manually."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if let error = controller.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(controller.hooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                        controller.installHooks()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isInstallingHooks)

                    Button(controller.featureFlagEnabled ? "Re-check Flag" : "Enable Feature Flag") {
                        controller.enableFlag()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isEnablingFlag)
                }

                Button(controller.enabledInCodex ? "Re-apply Trust" : "Enable in Codex") {
                    controller.enableInCodex()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isEnablingInCodex)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Done") {
                    isConfigured = true
                    isEnabled = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.allComplete)
            }
        }
        .padding()
        .onAppear {
            controller.refresh()
        }
    }
}

struct SetupStep: View {
    let number: Int?
    let isComplete: Bool
    let title: String
    let detail: String

    /// Numbered step style (shows "1.", "2." when incomplete)
    init(number: Int, isComplete: Bool, title: String, detail: String) {
        self.number = number
        self.isComplete = isComplete
        self.title = title
        self.detail = detail
    }

    /// Check style (shows xmark when incomplete, no number)
    init(isComplete: Bool, title: String, detail: String) {
        number = nil
        self.isComplete = isComplete
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let number {
                Text("\(number).")
                    .fontWeight(.bold)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
