import Foundation
@testable import Juggler
import Testing

/// `codex-install.sh` is a bash+Python hand-port of `CodexHooksInstaller.swift` — it exists
/// so `install-remote.sh` can install Codex hooks on a remote host without the app. The two
/// implementations compute Codex's `trusted_hash` independently; if they drift, remote
/// installs silently produce hooks Codex rejects. This suite runs the real script and asserts
/// its generated trust hashes are byte-identical to the Swift implementation's.
@Suite("codex-install.sh — parity with CodexHooksInstaller")
struct CodexInstallScriptParityTests {
    /// Repo-relative path to the script, resolved from this test file's location.
    private static var scriptPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JugglerTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("juggler/Resources/codex-hooks/codex-install.sh")
            .path
    }

    private static let events = CodexHooksInstaller.agentEvents

    @Test func scriptTrustHashesMatchSwiftImplementation() throws {
        let script = Self.scriptPath
        try #require(
            FileManager.default.fileExists(atPath: script),
            "codex-install.sh not found at \(script)"
        )

        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        // Run the installer against a throwaway HOME — it copies the adjacent
        // codex-notify.sh and writes ~/.codex/{hooks.json,config.toml}. Fully offline.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        proc.environment = env
        let output = Pipe()
        proc.standardOutput = output
        proc.standardError = output
        try proc.run()
        proc.waitUntilExit()

        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(proc.terminationStatus == 0, "codex-install.sh failed:\n\(log)")

        let toml = try String(
            contentsOfFile: home.appendingPathComponent(".codex/config.toml").path,
            encoding: .utf8
        )
        let notifyPath = home.appendingPathComponent(".codex/hooks/juggler/notify.sh").path
        let scriptHashes = Set(Self.parseTrustedHashes(toml).values)

        #expect(
            scriptHashes.count == Self.events.count,
            "expected \(Self.events.count) distinct trust hashes"
        )

        for event in Self.events {
            let expected = CodexHooksInstaller.computeTrustedHash(
                event: event,
                command: "\(notifyPath) \(event)"
            )
            #expect(
                scriptHashes.contains(expected),
                "no script-generated trust hash matches Swift's for \(event)"
            )
        }

        // The trust hashes alone can't catch a script that writes one timeout into hooks.json
        // and fingerprints another — that combination installs cleanly and never fires.
        let hooksJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: home.appendingPathComponent(".codex/hooks.json"))
        ) as? [String: Any]
        let hooks = hooksJSON?["hooks"] as? [String: Any]

        for event in Self.events {
            let groups = hooks?[event] as? [[String: Any]]
            let handler = groups?
                .compactMap { $0["hooks"] as? [[String: Any]] }
                .flatMap(\.self)
                .first { $0["command"] as? String == CodexHooksInstaller.hookCommand(
                    for: event, notifyScriptPath: notifyPath
                ) }
            #expect(
                handler?["timeout"] as? Int == CodexHooksInstaller.timeoutSeconds(for: event),
                "script wrote the wrong hooks.json timeout for \(event)"
            )
        }
    }

    /// Extracts every `[hooks.state."<key>"]` → `trusted_hash` pair from config.toml contents.
    private static func parseTrustedHashes(_ toml: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        for line in toml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[hooks.state.\""), trimmed.hasSuffix("\"]") {
                currentKey = String(trimmed.dropFirst("[hooks.state.\"".count).dropLast("\"]".count))
            } else if let key = currentKey, trimmed.hasPrefix("trusted_hash") {
                if let open = trimmed.firstIndex(of: "\"") {
                    let afterOpen = trimmed.index(after: open)
                    if let close = trimmed[afterOpen...].firstIndex(of: "\"") {
                        result[key] = String(trimmed[afterOpen ..< close])
                    }
                }
                currentKey = nil
            }
        }
        return result
    }
}
