//
//  OnboardingView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import ServiceManagement
import ShortcutKit
import ShortcutKitUI
import Sparkle
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var integrationProgress = IntegrationSetupProgress()
    private let stepCount = 4
    private let integrationsStep = 1

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case integrationsStep:
                    IntegrationHubView(onContinue: { currentStep += 1 }, progress: integrationProgress)
                case 2:
                    ShortcutsStep()
                case 3:
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
                    ForEach(0 ..< stepCount, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(currentStep + 1) of \(stepCount)")

                Spacer()

                if currentStep < stepCount - 1, currentStep != integrationsStep {
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
                    let global = ShortcutCenter.shared.globalContext
                    ShortcutBindingEditor(.cycleForward, in: global)
                    ShortcutBindingEditor(.cycleBackward, in: global)
                    ShortcutBindingEditor(.backburner, in: global)
                    ShortcutBindingEditor(.sendToBack, in: global)
                    ShortcutBindingEditor(.reactivateAll, in: global)
                    ShortcutBindingEditor(.goToLastNotification, in: global, showsDescription: true)
                    ShortcutBindingEditor(.sessionMenu, in: global, showsDescription: true)
                    ShortcutBindingEditor(.showMonitor, in: global, showsDescription: true)
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
    @State private var enableLaunchAtLogin = false
    @State private var enableAutoUpdate = true
    @AppStorage(AppStorageKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppStorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    private var defaultCycleInstruction: String {
        Self.cycleInstruction(keys: ShortcutCenter.shared.globalContext.displayStrings(for: .cycleForward).first)
    }

    static func cycleInstruction(keys: String?) -> String {
        guard let keys else { return "use the Cycle Forward shortcut to cycle through them" }
        return "use \(keys) to cycle through them"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Juggler lives in your menu bar. Start some Claude Code sessions and \(defaultCycleInstruction)!")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Toggle("Launch Juggler at Login", isOn: $enableLaunchAtLogin)
                .toggleStyle(.checkbox)

            Toggle("Automatically download and install updates", isOn: $enableAutoUpdate)
                .toggleStyle(.checkbox)

            Button("Finish") {
                if enableLaunchAtLogin {
                    do {
                        try SMAppService.mainApp.register()
                        launchAtLogin = true
                    } catch {
                        logError(.session, "Failed to register launch at login: \(error)")
                    }
                }
                let updater = UpdateManager.shared.updater
                updater.automaticallyChecksForUpdates = true
                updater.automaticallyDownloadsUpdates = enableAutoUpdate
                hasCompletedOnboarding = true
                Task {
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
                WindowManager.shared.openMainWindow()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
