//
//  KittySetupView.swift
//  Juggler
//

import SwiftUI

struct KittySetupView: View {
    @Binding var isConfigured: Bool
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var kittyInstalled = false
    @State private var remoteControlEnabled = false
    @State private var listenOnConfigured = false
    @State private var watcherInstalled = false
    @State private var connectionTested = false
    @State private var isInstallingWatcher = false
    @State private var watcherInstallError: String?
    @State private var configError: String?
    @State private var testError: String?

    var allReady: Bool {
        kittyInstalled && remoteControlEnabled && listenOnConfigured
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Kitty Setup")
                .font(.title2)
                .fontWeight(.bold)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SetupCheckRow(
                        title: "Kitty Installed",
                        detail: "Checks /Applications/kitty.app",
                        isComplete: kittyInstalled
                    )

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

                            if !remoteControlEnabled, kittyInstalled {
                                Button("Add to kitty.conf") {
                                    appendToKittyConf("allow_remote_control socket-only")
                                }
                                .padding(.top, 2)
                            }
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

                            if !listenOnConfigured, kittyInstalled {
                                Button("Add to kitty.conf") {
                                    appendToKittyConf("listen_on unix:/tmp/kitty-{kitty_pid}")
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    Divider()

                    // Watcher (optional)
                    HStack(alignment: .top, spacing: 12) {
                        if watcherInstalled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Install Watcher (Recommended)")
                                .fontWeight(.medium)
                            Text("Enables focus tracking and session termination detection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let error = watcherInstallError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button(watcherInstalled ? "Reinstall Watcher" : "Install Watcher") {
                                installWatcher()
                            }
                            .disabled(isInstallingWatcher)
                            .padding(.top, 4)
                        }
                    }

                    Divider()

                    if let error = configError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Test connection
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
                    Text("Restart Kitty after making configuration changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            HStack(spacing: 12) {
                Button("Check Configuration") {
                    checkConfiguration()
                }

                Button("Test Connection") {
                    testConnection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!kittyInstalled)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Done") {
                    isConfigured = allReady
                    isEnabled = allReady
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allReady)
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

    private func appendToKittyConf(_ line: String) {
        configError = nil

        do {
            let fileURL = URL(fileURLWithPath: kittyConfPath)
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/kitty")

            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: kittyConfPath) {
                let existingContent = try String(contentsOfFile: kittyConfPath, encoding: .utf8)
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()

                var lineToAppend = line + "\n"
                if !existingContent.isEmpty, !existingContent.hasSuffix("\n") {
                    lineToAppend = "\n" + lineToAppend
                }

                handle.write(Data(lineToAppend.utf8))
                handle.closeFile()
            } else {
                try (line + "\n").write(toFile: kittyConfPath, atomically: true, encoding: .utf8)
            }

            checkConfiguration()
        } catch {
            configError = "Failed to update kitty.conf: \(error.localizedDescription)"
        }
    }

    private func checkConfiguration() {
        kittyInstalled = FileManager.default.fileExists(atPath: "/Applications/kitty.app")

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
                try await KittyBridge.shared.start()
                connectionTested = true
            } catch {
                testError = "Could not find kitten binary: \(error.localizedDescription)"
                connectionTested = false
            }
        }
    }
}

private struct SetupCheckRow: View {
    let title: String
    let detail: String
    let isComplete: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
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
