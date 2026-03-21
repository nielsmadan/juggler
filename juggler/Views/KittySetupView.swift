//
//  KittySetupView.swift
//  Juggler
//

import SwiftUI

struct KittySetupView: View {
    @Binding var isConfigured: Bool
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var remoteControlEnabled = false
    @State private var listenOnConfigured = false
    @State private var watcherInstalled = false
    @State private var connectionTested = false
    @State private var isInstallingWatcher = false
    @State private var watcherInstallError: String?
    @State private var configError: String?
    @State private var testError: String?

    var allReady: Bool {
        remoteControlEnabled && listenOnConfigured
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Kitty Setup")
                .font(.title2)
                .fontWeight(.bold)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SetupStep(
                        isComplete: remoteControlEnabled,
                        title: "Remote Control Enabled",
                        detail: "allow_remote_control socket-only in kitty.conf"
                    )

                    SetupStep(
                        isComplete: listenOnConfigured,
                        title: "Listen Socket Configured",
                        detail: "listen_on unix:/tmp/kitty-{kitty_pid} in kitty.conf"
                    )

                    Divider()

                    SetupStep(
                        isComplete: watcherInstalled,
                        title: "Install Watcher",
                        detail: "Enables focus tracking and session termination detection."
                    )

                    if let error = watcherInstallError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Divider()

                    if let error = configError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    SetupStep(
                        isComplete: connectionTested,
                        title: "Test Connection",
                        detail: "Verifies Juggler can communicate with Kitty."
                    )

                    if let error = testError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                if allReady {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)

                    if !connectionTested {
                        Label(
                            "Please restart Kitty for configuration changes to take effect.",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                    }
                } else {
                    Button("Setup Kitty") {
                        setupIntegration()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }

            Spacer()

            if connectionTested {
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
            refreshStatus()
        }
    }

    private func setupIntegration() {
        if !remoteControlEnabled {
            configError = KittyConfigParser.appendToConf("allow_remote_control socket-only")
            refreshStatus()
            if configError != nil { return }
        }
        if !listenOnConfigured {
            configError = KittyConfigParser.appendToConf("listen_on unix:/tmp/kitty-{kitty_pid}")
            refreshStatus()
            if configError != nil { return }
        }
        if !watcherInstalled {
            installWatcher()
        }
    }

    private func refreshStatus() {
        let status = KittyConfigParser.status()
        remoteControlEnabled = status.remoteControlEnabled
        listenOnConfigured = status.listenOnConfigured
        watcherInstalled = status.watcherInstalled
    }

    private func installWatcher() {
        isInstallingWatcher = true
        watcherInstallError = nil

        Task {
            let result = await ScriptInstaller.installKittyWatcher()
            await MainActor.run {
                if let error = result {
                    watcherInstallError = error
                } else {
                    watcherInstalled = true
                }
                isInstallingWatcher = false
            }
        }
    }

    func testConnection() {
        testError = nil

        Task {
            do {
                try await KittyBridge.shared.testConnection()
                connectionTested = true
            } catch {
                testError = "Could not connect to Kitty: \(error.localizedDescription)"
                connectionTested = false
            }
        }
    }
}
