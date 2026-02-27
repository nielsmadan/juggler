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
                    HStack(alignment: .top, spacing: 12) {
                        if remoteControlEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remote Control Enabled")
                                .fontWeight(.medium)
                            Text("allow_remote_control socket-only in kitty.conf")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        if listenOnConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Listen Socket Configured")
                                .fontWeight(.medium)
                            Text("listen_on unix:/tmp/kitty-{kitty_pid} in kitty.conf")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 12) {
                        if watcherInstalled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Install Watcher")
                                .fontWeight(.medium)
                            Text("Enables focus tracking and session termination detection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let error = watcherInstallError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Divider()

                    if let error = configError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        if connectionTested {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test Connection")
                                .fontWeight(.medium)
                            Text("Verifies Juggler can communicate with Kitty.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let error = testError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
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
            checkConfiguration()
        }
    }

    private var kittyConfPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/kitty/kitty.conf").path
    }

    private func setupIntegration() {
        if !remoteControlEnabled {
            appendToKittyConf("allow_remote_control socket-only")
        }
        if !listenOnConfigured {
            appendToKittyConf("listen_on unix:/tmp/kitty-{kitty_pid}")
        }
        if !watcherInstalled {
            installWatcher()
        }
    }

    private func appendToKittyConf(_ line: String) {
        configError = nil

        do {
            let fileURL = URL(fileURLWithPath: kittyConfPath)
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/kitty")

            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: kittyConfPath) {
                let existingContent = try String(contentsOfFile: kittyConfPath, encoding: .utf8)

                // Skip if directive already present (non-commented)
                let directiveKey = String(line.split(separator: " ").first ?? "")
                let alreadyPresent = existingContent.split(separator: "\n").contains { l in
                    let trimmed = l.trimmingCharacters(in: .whitespaces)
                    return !trimmed.hasPrefix("#") && trimmed.hasPrefix(directiveKey)
                }
                if alreadyPresent {
                    checkConfiguration()
                    return
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { handle.closeFile() }
                handle.seekToEndOfFile()

                var lineToAppend = line + "\n"
                if !existingContent.isEmpty, !existingContent.hasSuffix("\n") {
                    lineToAppend = "\n" + lineToAppend
                }

                handle.write(Data(lineToAppend.utf8))
            } else {
                try (line + "\n").write(toFile: kittyConfPath, atomically: true, encoding: .utf8)
            }

            checkConfiguration()
        } catch {
            configError = "Failed to update kitty.conf: \(error.localizedDescription)"
        }
    }

    private func checkConfiguration() {
        if let contents = try? String(contentsOfFile: kittyConfPath, encoding: .utf8) {
            remoteControlEnabled = contents.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("#") && trimmed.hasPrefix("allow_remote_control")
                    && (trimmed.contains("yes") || trimmed.contains("socket"))
            }

            listenOnConfigured = contents.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("listen_on") && !trimmed.hasPrefix("#")
            }

            watcherInstalled = contents.contains("juggler_watcher.py")
        } else {
            remoteControlEnabled = false
            listenOnConfigured = false
            watcherInstalled = false
        }
    }

    private func installWatcher() {
        isInstallingWatcher = true
        watcherInstallError = nil

        guard let scriptPath = Bundle.main.path(forResource: "install_kitty_watcher", ofType: "sh") else {
            watcherInstallError = "Install script not found in bundle"
            isInstallingWatcher = false
            return
        }

        Task {
            let result = await runProcess(executableURL: "/bin/bash", arguments: [scriptPath])
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

    private func testConnection() {
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
