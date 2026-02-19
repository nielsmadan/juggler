//
//  IntegrationHubView.swift
//  Juggler
//

import SwiftUI

struct IntegrationHubView: View {
    @AppStorage(AppStorageKeys.iterm2Enabled) private var iterm2Enabled = true
    @AppStorage(AppStorageKeys.kittyEnabled) private var kittyEnabled = false

    @State private var showingITerm2Setup = false
    @State private var showingKittySetup = false
    @State private var showingTmuxSetup = false
    @State private var showingClaudeCodeSetup = false
    @State private var showingOpenCodeSetup = false

    @State private var iterm2Configured = false
    @State private var kittyConfigured = false
    @State private var tmuxConfigured = false
    @State private var claudeCodeConfigured = false
    @State private var openCodeConfigured = false

    var hasAnyTerminal: Bool {
        iterm2Configured || kittyConfigured
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

            // Terminal cards
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

                IntegrationCard(
                    icon: "rectangle.split.3x1",
                    title: "tmux",
                    description: "Env forwarding for terminal session tracking",
                    isConfigured: tmuxConfigured,
                    action: { showingTmuxSetup = true }
                )
            }

            // Agent cards
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
            }

            if !hasAnyTerminal {
                Text("Configure at least one terminal to continue.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
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

            HStack(spacing: 12) {
                Button("Open iTerm2") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }

                Button("Check") {
                    checkRuntime()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Done") {
                    isConfigured = runtimeInstalled
                    isEnabled = runtimeInstalled
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!runtimeInstalled)
            }
        }
        .padding()
    }

    private func checkRuntime() {
        let script = """
        tell application "iTerm2" to request cookie and key for app named "Juggler"
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    runtimeInstalled = (error == nil && result.stringValue != nil)
                }
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

            HStack {
                Button("Skip") {
                    dismiss()
                }

                Spacer()

                Button("Done") {
                    isConfigured = envConfigured
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!envConfigured)
            }
        }
        .padding()
        .onAppear {
            checkTmuxConfigured()
        }
    }

    private func checkTmuxConfigured() {
        guard FileManager.default.fileExists(atPath: tmuxConfPath) else {
            envConfigured = false
            return
        }

        do {
            let contents = try String(contentsOfFile: tmuxConfPath, encoding: .utf8)
            envConfigured = contents.contains("update-environment")
                && (contents.contains("ITERM_SESSION_ID") || contents.contains("KITTY_WINDOW_ID"))
        } catch {
            envConfigured = false
        }
    }

    private func configureTmux() {
        isConfiguring = true
        configError = nil

        do {
            let fileURL = URL(fileURLWithPath: tmuxConfPath)

            if FileManager.default.fileExists(atPath: tmuxConfPath) {
                let existingContent = try String(contentsOfFile: tmuxConfPath, encoding: .utf8)
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()

                var lineToAppend = updateEnvironmentLine + "\n"
                if !existingContent.isEmpty, !existingContent.hasSuffix("\n") {
                    lineToAppend = "\n" + lineToAppend
                }

                handle.write(Data(lineToAppend.utf8))
                handle.closeFile()
            } else {
                try (updateEnvironmentLine + "\n").write(toFile: tmuxConfPath, atomically: true, encoding: .utf8)
            }

            checkTmuxConfigured()
        } catch {
            configError = "Failed to update ~/.tmux.conf: \(error.localizedDescription)"
        }

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

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Done") {
                    isConfigured = isInstalled
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isInstalled)
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

        guard let scriptPath = Bundle.main.path(forResource: "install", ofType: "sh") else {
            errorMessage = "Install script not found in bundle"
            isInstalling = false
            return
        }

        Task {
            let result = await runProcess(executableURL: "/bin/bash", arguments: [scriptPath])
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
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/juggler-opencode.ts").path
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("OpenCode Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Juggler needs to install a plugin in ~/.config/opencode/plugins to detect when OpenCode sessions become idle or need input."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: isInstalled,
                    title: "Install Plugin",
                    detail: "Adds juggler-opencode.ts to ~/.config/opencode/plugins/"
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

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Done") {
                    isConfigured = isInstalled
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isInstalled)
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

struct SetupStep: View {
    let number: Int
    let isComplete: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(number).")
                    .fontWeight(.bold)
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
