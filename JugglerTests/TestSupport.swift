import Foundation
@testable import Juggler

/// A stub shell script standing in for the `hooklinesinker` CLI. It records its argv and the
/// XDG state root it was handed, so the exact command line — the contract with the CLI — is
/// asserted rather than assumed.
struct HooklinesinkerStub {
    let root: URL
    let client: HooklinesinkerClient

    /// Writes a stub that prints `stdout`, prints `stderr` on fd 2, and exits with `status`.
    /// The data root points at an empty directory, so every command falls back to the stub
    /// instead of needing a second promoted copy on disk.
    static func make(
        stdout: String = "",
        stderr: String = "",
        status: Int32 = 0,
        sinkURL: String? = nil,
        environmentOverrides: [String: String] = [:]
    ) throws -> HooklinesinkerStub {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hls-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("hooklinesinker")
        let script = """
        #!/bin/bash
        printf '%s\\n' "$(IFS=$'\\001'; echo "$*")" >> "\(root.path)/argv.log"
        printf 'XDG_STATE_HOME=%s\\n' "${XDG_STATE_HOME:-}" >> "\(root.path)/env.log"
        printf '%s' '\(shellQuoteBody(stdout))'
        printf '%s' '\(shellQuoteBody(stderr))' >&2
        exit \(status)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        return HooklinesinkerStub(
            root: root,
            client: HooklinesinkerClient(
                bundledExecutablePath: executable.path,
                dataRoot: root.appendingPathComponent("data").path,
                environmentOverrides: environmentOverrides,
                sinkURL: sinkURL
            )
        )
    }

    var recordedArguments: [[String]] {
        guard let log = try? String(contentsOf: root.appendingPathComponent("argv.log"), encoding: .utf8)
        else { return [] }
        return log
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init) }
    }

    var recordedEnvironment: [String] {
        guard let log = try? String(contentsOf: root.appendingPathComponent("env.log"), encoding: .utf8)
        else { return [] }
        return log.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func shellQuoteBody(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}

/// Protocol-v1 status bodies, spelled as the CLI emits them (camelCase, `cwd` on `session`).
/// Built as raw JSON rather than encoded from the model so a rename in the model can't
/// silently rewrite the contract these tests are pinning.
enum TestFixtures {
    static let workingStatus = statusJSON(
        bindingId: "binding-working",
        event: "UserPromptSubmit",
        phase: "working",
        sessionID: "native-session",
        terminalSessionID: "terminal-session"
    )

    static let endedStatus = statusJSON(
        bindingId: "binding-working",
        event: "SessionEnd",
        phase: "idle",
        running: false,
        sessionID: "native-session",
        terminalSessionID: "terminal-session"
    )

    static func statusJSON(
        bindingId: String = "binding-1",
        agent: String = "claude",
        event: String = "SessionStart",
        phase: String = "idle",
        running: Bool = true,
        sessionID: String = "native-session",
        cwd: String = "/test/project",
        transcriptPath: String? = nil,
        terminalSessionID: String? = "terminal-session",
        terminalType: String = "iterm2",
        tmuxPane: String? = nil,
        tmuxSessionName: String? = nil,
        gitBranch: String? = nil,
        gitRepo: String? = nil,
        remoteHost: String? = nil
    ) -> String {
        var fields: [String] = [
            "\"protocol\":1",
            "\"bindingId\":\(quoted(bindingId))",
            "\"agent\":\(quoted(agent))",
            "\"event\":\(quoted(event))",
            "\"phase\":\(quoted(phase))",
            "\"running\":\(running)",
            "\"observedAt\":\"2026-09-04T12:00:00Z\"",
            "\"session\":{\"id\":\(quoted(sessionID)),\"cwd\":\(quoted(cwd)),"
                + "\"transcriptPath\":\(optionalQuoted(transcriptPath))}",
            "\"process\":{\"pid\":4242,\"startedAt\":\"2026-09-04T11:00:00Z\",\"host\":\"test-host\"}"
        ]
        if let terminalSessionID {
            fields.append(
                "\"terminal\":{\"sessionId\":\(quoted(terminalSessionID)),"
                    + "\"terminalType\":\(quoted(terminalType)),\"kittyListenOn\":null,\"kittyPid\":null}"
            )
        }
        if tmuxPane != nil || tmuxSessionName != nil {
            fields.append(
                "\"tmux\":{\"pane\":\(optionalQuoted(tmuxPane)),"
                    + "\"sessionName\":\(optionalQuoted(tmuxSessionName))}"
            )
        }
        if gitBranch != nil || gitRepo != nil {
            fields.append(
                "\"git\":{\"branch\":\(optionalQuoted(gitBranch)),\"repo\":\(optionalQuoted(gitRepo))}"
            )
        }
        fields.append("\"remoteHost\":\(optionalQuoted(remoteHost))")
        return "{\(fields.joined(separator: ","))}"
    }

    static func sessionsEnvelope(_ statuses: [String], problems: [String] = []) -> String {
        let problemObjects = problems
            .map { "{\"observedAt\":\"2026-09-04T12:00:00Z\",\"message\":\(quoted($0))}" }
            .joined(separator: ",")
        return "{\"protocol\":1,\"sessions\":[\(statuses.joined(separator: ","))],"
            + "\"problems\":[\(problemObjects)]}"
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func optionalQuoted(_ value: String?) -> String {
        value.map { quoted($0) } ?? "null"
    }
}

/// Shared helper for constructing a minimal `Session` in tests.
/// The `id` string is used for both `claudeSessionID` and `terminalSessionID`,
/// and `projectPath` is derived as `/test/{id}` so sessions are easy to spot in failures.
func makeSession(_ id: String, state: SessionState = .idle) -> Session {
    Session(
        claudeSessionID: id,
        terminalSessionID: id,
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test/\(id)",
        terminalTabName: nil,
        terminalWindowName: nil,
        customName: nil,
        state: state,
        startedAt: Date()
    )
}
