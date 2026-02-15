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
                    IntegrationHubView()
                case 3:
                    ShortcutsStep()
                case 4:
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
                    ForEach(0 ..< 5) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep < 4 {
                    Button("Continue") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 700)
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

struct FinishStep: View {
    let dismiss: DismissAction
    @Environment(\.openWindow) private var openWindow
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
                        launchAtLogin = !newValue
                    }
                }

            Button("Finish") {
                hasCompletedOnboarding = true
                // Start configured bridges now that onboarding is complete
                Task {
                    if UserDefaults.standard.bool(forKey: AppStorageKeys.iterm2Enabled) {
                        try? await TerminalBridgeRegistry.shared.start(.iterm2)
                    }
                    if UserDefaults.standard.bool(forKey: AppStorageKeys.kittyEnabled) {
                        try? await TerminalBridgeRegistry.shared.start(.kitty)
                    }
                }
                // Open main window and show dock icon
                openWindow(id: "main")
                NSApp.setActivationPolicy(.regular)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
