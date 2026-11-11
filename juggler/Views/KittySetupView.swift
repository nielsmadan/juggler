//
//  KittySetupView.swift
//  Juggler
//

import SwiftUI

struct KittySetupView: View {
    @Binding var isConfigured: Bool
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var kitty = KittySetupController()
    @State private var connectionTested = false
    @State private var testError: String?

    private let stepActionIndent: CGFloat = 28

    var body: some View {
        VStack(spacing: 16) {
            Text("Kitty Setup")
                .font(.title2)
                .fontWeight(.bold)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SetupStep(
                        isComplete: kitty.status.remoteControlEnabled,
                        title: "Remote Control Enabled",
                        detail: "\(KittyConfigParser.remoteControlDirective) in kitty.conf"
                    )
                    if !kitty.status.remoteControlEnabled {
                        Button("Add to kitty.conf") {
                            kitty.append(KittyConfigParser.remoteControlDirective)
                        }
                        .accessibilityLabel("Add remote control to kitty.conf")
                        .padding(.leading, stepActionIndent)
                    }

                    SetupStep(
                        isComplete: kitty.status.listenOnConfigured,
                        title: "Listen Socket Configured",
                        detail: "\(KittyConfigParser.listenOnDirective) in kitty.conf"
                    )
                    if !kitty.status.listenOnConfigured {
                        Button("Add to kitty.conf") {
                            kitty.append(KittyConfigParser.listenOnDirective)
                        }
                        .accessibilityLabel("Add listen socket to kitty.conf")
                        .padding(.leading, stepActionIndent)
                    }

                    if let error = kitty.configError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Divider()

                    SetupStep(
                        isComplete: kitty.status.watcherInstalled,
                        title: "Install Watcher",
                        detail: "Enables focus tracking and session termination detection."
                    )
                    Button(kitty.status.watcherInstalled ? "Reinstall Watcher" : "Install Watcher") {
                        Task { await kitty.installWatcher() }
                    }
                    .disabled(kitty.isInstallingWatcher)
                    .padding(.leading, stepActionIndent)

                    if let error = kitty.watcherError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Divider()

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

                if kitty.canTestConnection {
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
            kitty.refresh()
        }
    }

    func testConnection() {
        testError = nil

        Task {
            do {
                try await KittyBridge.shared.testConnection()
                connectionTested = true
            } catch {
                let message = "Could not connect to Kitty: \(error.localizedDescription)"
                testError = message
                connectionTested = false
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}
