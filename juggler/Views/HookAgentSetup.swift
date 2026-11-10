import SwiftUI

struct HookAgentSetup: Identifiable {
    let agent: HooklinesinkerAgent
    let icon: String
    let configPath: String
    let reportsPermission: Bool
    let isExperimental: Bool
    let startupHint: String?

    var id: HooklinesinkerAgent { agent }
    var title: String { agent.displayName }

    var cardDescription: String {
        isExperimental ? "Install hooks for session tracking (experimental)" : "Install hooks for session tracking"
    }

    var permissionHint: String? {
        reportsPermission ? nil : "No permission events: a session waiting for approval shows as working."
    }

    var setupSummary: String {
        let states = reportsPermission ? "become idle or need input" : "become idle"
        return "Juggler needs to register hooks in \(configPath) to detect when \(title) sessions \(states)."
    }

    static let all: [HookAgentSetup] = [
        HookAgentSetup(
            agent: .droid, icon: "cpu", configPath: "~/.factory/hooks.json", reportsPermission: true,
            isExperimental: false,
            startupHint: "Droid reads hooks at startup — restart a running droid session for it to take effect."
        ),
        HookAgentSetup(
            agent: .qwen, icon: "atom", configPath: "~/.qwen/settings.json", reportsPermission: true,
            isExperimental: false,
            startupHint: nil
        ),
        HookAgentSetup(
            agent: .kimi, icon: "moon.stars", configPath: "~/.kimi-code/config.toml", reportsPermission: true,
            isExperimental: false,
            startupHint: nil
        ),
        HookAgentSetup(
            agent: .cursor, icon: "cursorarrow.rays", configPath: "~/.cursor/hooks.json", reportsPermission: false,
            isExperimental: true,
            startupHint: nil
        )
    ]
}

struct HookAgentSetupView: View {
    let setup: HookAgentSetup
    @Binding var isConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("\(setup.title) Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text(setup.setupSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                SetupStep(
                    number: 1,
                    isComplete: isInstalled,
                    title: "Install Hooks",
                    detail: "Registers Juggler's hook events in \(setup.configPath)"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            if isInstalled {
                Label("Hooks Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let hint = setup.startupHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .task {
            isInstalled = await HooklinesinkerClient.shared.isInstalled(agent: setup.agent)
        }
    }

    private func installHooks() {
        isInstalling = true
        errorMessage = nil

        Task {
            let result = await HooklinesinkerClient.shared.installHooks(agent: setup.agent)
            if !result.isSuccess {
                errorMessage = result.failureMessage
            }
            isInstalled = await HooklinesinkerClient.shared.isInstalled(agent: setup.agent)
            isInstalling = false
        }
    }
}

struct HookAgentSettingsSection: View {
    let setup: HookAgentSetup
    @State private var isInstalled = false
    @State private var isInstalling = false
    @State private var installError: String?

    var body: some View {
        Section(setup.title) {
            HStack {
                Text("Hook Script")
                Spacer()
                if isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not Installed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = installError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(isInstalled ? "Reinstall Hooks" : "Install Hooks") {
                installHooks()
            }
            .disabled(isInstalling)

            if isInstalled, let hint = setup.startupHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let hint = setup.permissionHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            isInstalled = await HooklinesinkerClient.shared.isInstalled(agent: setup.agent)
        }
    }

    private func installHooks() {
        isInstalling = true
        installError = nil

        Task {
            let result = await HooklinesinkerClient.shared.installHooks(agent: setup.agent)
            if !result.isSuccess {
                installError = result.failureMessage
            }
            isInstalled = await HooklinesinkerClient.shared.isInstalled(agent: setup.agent)
            isInstalling = false
        }
    }
}
