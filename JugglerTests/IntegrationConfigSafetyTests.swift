import Foundation
@testable import Juggler
import Testing

/// Guards the configuration surfaces Juggler still writes itself. Claude and Codex hook
/// registration moved to hooklinesinker, which carries its own safety tests; what stays here
/// is the Codex trust-entry cleanup Juggler's reset flow runs.
@Suite("Integration configuration safety")
struct IntegrationConfigSafetyTests {
    private static var resourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("juggler/Resources")
    }

    @Test @MainActor func codexCleanupPreservesLaterChangesAndUnrelatedTrust() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let config = codex.appendingPathComponent("config.toml")
        let hooksJSON = codex.appendingPathComponent("hooks.json")
        let notify = codex.appendingPathComponent("hooks/juggler/notify.sh").path
        let currentKey = "\(hooksJSON.path):session_start:1:0"
        let staleKey = "\(hooksJSON.path):stop:4:0"
        let staleHash = CodexHooksInstaller.computeTrustedHash(
            event: "Stop",
            command: "\(notify) Stop"
        )
        let contents = """
        [features]
        hooks = true

        [model]
        reasoning_effort = "high"

        [hooks.state."\(hooksJSON.path):session_start:0:0"]
        trusted_hash = "sha256:user"

        [hooks.state."\(currentKey)"]
        trusted_hash = "sha256:outdated-juggler"

        [hooks.state."\(staleKey)"]
        trusted_hash = "\(staleHash)"

        [hooks.state."/other/hooks.json:stop:0:0"]
        trusted_hash = "sha256:other"
        """
        try Data(contents.utf8).write(to: config)
        let hooks: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    ["hooks": [["command": "user-hook"]]],
                    ["hooks": [["command": "\(notify) SessionStart"]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: hooks).write(to: hooksJSON)

        let result = try run(
            executable: "/usr/bin/env",
            arguments: [
                "python3",
                Self.resourcesDirectory.appendingPathComponent("codex_config_cleanup.py").path,
                config.path,
                hooksJSON.path,
                notify
            ],
            home: home
        )

        try #require(result.status == 0, Comment(rawValue: result.output))
        let updated = try String(contentsOf: config, encoding: .utf8)
        #expect(updated.contains("hooks = true"))
        #expect(updated.contains("reasoning_effort = \"high\""))
        #expect(updated.contains("session_start:0:0"))
        #expect(updated.contains("/other/hooks.json:stop:0:0"))
        #expect(!updated.contains(currentKey))
        #expect(!updated.contains(staleKey))
    }

    @Test func codexCleanupPreservesSymlinkedConfig() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appendingPathComponent(".codex")
        let managedDirectory = home.appendingPathComponent("dotfiles")
        let managedConfig = managedDirectory.appendingPathComponent("codex-config.toml")
        let config = codex.appendingPathComponent("config.toml")
        let hooksJSON = codex.appendingPathComponent("hooks.json")
        let notify = codex.appendingPathComponent("hooks/juggler/notify.sh").path
        let key = "\(hooksJSON.path):stop:0:0"
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        try Data("[hooks.state.\"\(key)\"]\ntrusted_hash = \"sha256:juggler\"\n".utf8).write(to: managedConfig)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: managedConfig)
        let hooks: [String: Any] = [
            "hooks": [
                "Stop": [["hooks": [["command": "\(notify) Stop"]]]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: hooks).write(to: hooksJSON)

        let result = try run(
            executable: "/usr/bin/env",
            arguments: [
                "python3",
                Self.resourcesDirectory.appendingPathComponent("codex_config_cleanup.py").path,
                config.path,
                hooksJSON.path,
                notify
            ],
            home: home
        )

        try #require(result.status == 0, Comment(rawValue: result.output))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: config.path) == managedConfig.path)
        #expect(try String(contentsOf: managedConfig, encoding: .utf8).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-config-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func run(executable: String, arguments: [String], home: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
