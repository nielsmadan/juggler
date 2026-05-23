//
//  WezTermSetupView.swift
//  Juggler
//

import SwiftUI

struct WezTermSetupView: View {
    @Binding var isConfigured: Bool
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var luaInstalled = false
    @State private var requireLinePresent = false
    @State private var connectionTested = false
    @State private var isInstallingLua = false
    @State private var installError: String?
    @State private var testError: String?

    var luaReady: Bool { luaInstalled && requireLinePresent }

    var body: some View {
        VStack(spacing: 16) {
            Text("WezTerm Setup")
                .font(.title2)
                .fontWeight(.bold)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SetupStep(
                        isComplete: luaReady,
                        title: "Install Lua Snippet",
                        detail: "Copies juggler_wezterm.lua and adds require to wezterm.lua"
                    )

                    if let error = installError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Divider()

                    SetupStep(
                        isComplete: connectionTested,
                        title: "Test Connection",
                        detail: "Verifies Juggler can talk to WezTerm via wezterm cli"
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

                if luaReady {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)

                    if !connectionTested {
                        Label(
                            "Please restart WezTerm (or reload its config) for the Lua snippet to take effect.",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                    }
                } else {
                    Button(isInstallingLua ? "Installing..." : "Install Lua Snippet") {
                        installLua()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .disabled(isInstallingLua)
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
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .onAppear { refreshStatus() }
    }

    private func refreshStatus() {
        let status = WezTermConfigValidator.status()
        luaInstalled = status.luaSnippetInstalled
        requireLinePresent = status.requireLinePresent
    }

    private func installLua() {
        isInstallingLua = true
        installError = nil

        Task {
            let result = await ScriptInstaller.installWezTermLua()
            await MainActor.run {
                if let error = result {
                    installError = error
                }
                refreshStatus()
                isInstallingLua = false
            }
        }
    }

    func testConnection() {
        testError = nil

        Task {
            do {
                try await WezTermBridge.shared.testConnection()
                connectionTested = true
            } catch {
                testError = "Could not connect to WezTerm: \(error.localizedDescription)"
                connectionTested = false
            }
        }
    }
}
