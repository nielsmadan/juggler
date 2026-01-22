//
//  OnboardingView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case 1:
                    AccessibilityStep()
                case 2:
                    ITerm2RuntimeStep()
                case 3:
                    ShortcutsStep()
                case 4:
                    HooksStep()
                case 5:
                    FinishStep(dismiss: dismiss)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }

                Spacer()

                // Step indicators
                HStack(spacing: 8) {
                    ForEach(0 ..< 6) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep < 5 {
                    Button("Continue") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 520)
    }
}

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Welcome to Juggler")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Navigate Claude Code sessions with global hotkeys.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct AccessibilityStep: View {
    @State private var hasPermission = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Accessibility Permission")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "Juggler needs Accessibility access to listen for global keyboard shortcuts, even when other apps are focused."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            if hasPermission {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings") {
                    NSWorkspace.shared
                        .open(
                            URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                            )!
                        )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            checkPermission()
        }
    }

    private func checkPermission() {
        hasPermission = AXIsProcessTrusted()
    }
}

struct ShortcutsStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Default Shortcuts")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                ShortcutRow(keys: "Shift+Cmd+J", description: "Cycle forward through idle sessions")
                ShortcutRow(keys: "Shift+Cmd+K", description: "Cycle backward through idle sessions")
                ShortcutRow(keys: "Shift+Cmd+L", description: "Backburner current session")
                ShortcutRow(keys: "Shift+Cmd+H", description: "Reactivate all backburnered sessions")
                ShortcutRow(keys: "Shift+Cmd+;", description: "Show session monitor")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Text("You can customize these in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .leading)

            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

struct ITerm2RuntimeStep: View {
    @State private var runtimeInstalled = false
    @State private var isChecking = true

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)

            Text("iTerm2 Setup")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "Juggler uses iTerm2's Python API to read tab names and manage sessions."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                // Step 1: Python Runtime
                HStack(alignment: .top, spacing: 12) {
                    if runtimeInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("1.")
                            .fontWeight(.bold)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install Python Runtime")
                            .fontWeight(.medium)
                        Text("iTerm2 → Scripts → Manage → Install Python Runtime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Step 2: Enable API
                HStack(alignment: .top, spacing: 12) {
                    if runtimeInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("2.")
                            .fontWeight(.bold)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Python API")
                            .fontWeight(.medium)
                        Text("iTerm2 → Settings → General → Magic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Check \"Enable Python API\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Step 3: Grant automation permission
                HStack(alignment: .top, spacing: 12) {
                    if runtimeInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("3.")
                            .fontWeight(.bold)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Grant Automation Permission")
                            .fontWeight(.medium)
                        Text("Click \"Check Again\" below - macOS will")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("prompt you to grant Juggler access to iTerm2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

                Button("Check Again") {
                    checkRuntime()
                }
            }
        }
        .padding()
    }

    private func checkRuntime() {
        isChecking = true

        // Try to request a cookie from iTerm2 - this verifies the API is actually enabled
        let script = """
        tell application "iTerm2" to request cookie and key for app named "Juggler"
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    // If we got a result with a string value, the API is enabled
                    runtimeInstalled = (error == nil && result.stringValue != nil)
                    isChecking = false
                }
            } else {
                DispatchQueue.main.async {
                    runtimeInstalled = false
                    isChecking = false
                }
            }
        }
    }
}

struct HooksStep: View {
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Install Claude Code Hooks")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "Juggler needs to install hooks in ~/.claude/hooks to detect when Claude Code sessions become idle or need input."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            if isInstalled {
                Label("Hooks Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Install Hooks") {
                    installHooks()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling || isInstalled)

                Button("I'll do it myself") {
                    // Skip - user can install manually
                }
            }
        }
        .padding()
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

struct FinishStep: View {
    let dismiss: DismissAction
    @AppStorage(AppStorageKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppStorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "Juggler lives in your menu bar. Start some Claude Code sessions and use Shift+Cmd+J to cycle through them!"
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Toggle("Launch Juggler at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Failed to update launch at login: \(error)")
                    }
                }

            Button("Finish") {
                hasCompletedOnboarding = true
                // Start the daemon now that onboarding is complete
                Task {
                    try? await ITerm2Bridge.shared.start()
                }
                // Hide dock icon now that onboarding is complete
                NSApp.setActivationPolicy(.accessory)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
