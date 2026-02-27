//
//  OnboardingView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case 1:
                    AccessibilityStep()
                case 2:
                    IntegrationHubView(onContinue: { currentStep += 1 })
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

            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0 ..< 5) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep < 4, currentStep != 2 {
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Welcome to Juggler")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .padding()
    }
}

struct AccessibilityStep: View {
    @State private var hasPermission = false
    @State private var pollTimer: Timer?

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
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    checkPermission()
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
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

            Text("Global Shortcuts")
                .font(.title)
                .fontWeight(.bold)

            Form {
                Section("Global Shortcuts") {
                    KeyboardShortcuts.Recorder("Cycle Forward:", name: .cycleForward)
                    KeyboardShortcuts.Recorder("Cycle Backward:", name: .cycleBackward)
                    KeyboardShortcuts.Recorder("Backburner Current:", name: .backburner)
                    KeyboardShortcuts.Recorder("Reactivate All:", name: .reactivateAll)
                    KeyboardShortcuts.Recorder("Show Monitor:", name: .showMonitor)
                }
            }
            .formStyle(.grouped)

            Text("You can also change these later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
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
                openWindow(id: "main")
                NSApp.setActivationPolicy(.regular)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
