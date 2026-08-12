import Foundation
import Testing

/// Runs the real bundled `antigravity-notify.sh` under `Process()`. This bash script holds
/// the feature's two most consequential, type-unchecked behaviors: the stdout `decision`
/// Antigravity reads (a wrong value traps the agent's loop), and the `workspacePaths[0]` →
/// cwd extraction (agy runs the hook from its own config dir, so `$PWD` is wrong). Both are
/// untestable from Swift except by executing the script.
@Suite("antigravity-notify.sh — hook contract")
struct AntigravityNotifyScriptTests {
    private static var scriptPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JugglerTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("juggler/Resources/antigravity-hooks/antigravity-notify.sh")
            .path
    }

    /// Runs the script with `event` and `stdinJSON`. `port` defaults to a dead port so the
    /// POST fails fast and the stdout response is exercised in isolation. Terminal/tmux env
    /// is stripped so payloads are deterministic regardless of where the test runs.
    private func runNotify(event: String, stdinJSON: String, port: String = "1") throws -> String {
        let script = Self.scriptPath
        try #require(FileManager.default.fileExists(atPath: script), "notify script missing at \(script)")

        // Feed stdin from a temp file, not a Pipe: writing to a pipe whose reader (the
        // script) has already exited raises SIGPIPE and would crash the test runner.
        let stdinFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ag-stdin-\(UUID().uuidString).json")
        try Data(stdinJSON.utf8).write(to: stdinFile)
        defer { try? FileManager.default.removeItem(at: stdinFile) }
        let stdinHandle = try FileHandle(forReadingFrom: stdinFile)
        defer { try? stdinHandle.close() }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script, event]
        var env = ProcessInfo.processInfo.environment
        env["JUGGLER_PORT"] = port
        for key in ["ITERM_SESSION_ID", "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "KITTY_PID",
                    "WEZTERM_PANE", "TMUX", "TMUX_PANE", "SSH_CONNECTION"] {
            env.removeValue(forKey: key)
        }
        proc.environment = env

        let stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdinHandle
        proc.standardOutput = stdout
        proc.standardError = stderr
        try proc.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - stdout decision contract

    @Test func stop_emitsAllowDecision() throws {
        #expect(try runNotify(event: "Stop", stdinJSON: #"{"conversationId":"c1"}"#) == "{\"decision\":\"stop\"}\n")
    }

    @Test func preInvocation_emitsEmptyObject() throws {
        #expect(try runNotify(event: "PreInvocation", stdinJSON: #"{"conversationId":"c1"}"#) == "{}\n")
    }

    @Test func unknownEvent_emitsEmptyObject() throws {
        #expect(try runNotify(event: "SomethingElse", stdinJSON: #"{"conversationId":"c1"}"#) == "{}\n")
    }

    @Test func stop_emitsAllowDecision_withEmptyStdin() throws {
        #expect(try runNotify(event: "Stop", stdinJSON: "") == "{\"decision\":\"stop\"}\n")
    }

    // MARK: - payload capture (workspacePaths cwd + camelCase normalization)

    /// One-shot HTTP capture server: binds 127.0.0.1:<ephemeral>, writes its port to
    /// `argv[1]`, captures one request body to `argv[2]`, replies 200, exits.
    private static let captureServerPy = """
    import socket, sys
    port_file, body_file = sys.argv[1], sys.argv[2]
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    s.settimeout(15)
    with open(port_file, "w") as f:
        f.write(str(s.getsockname()[1]))
    conn, _ = s.accept()
    conn.settimeout(15)
    data = b""
    while b"\\r\\n\\r\\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            break
        data += chunk
    header, _, body = data.partition(b"\\r\\n\\r\\n")
    length = 0
    for line in header.split(b"\\r\\n"):
        if line.lower().startswith(b"content-length:"):
            length = int(line.split(b":", 1)[1].strip())
    while len(body) < length:
        chunk = conn.recv(4096)
        if not chunk:
            break
        body += chunk
    with open(body_file, "wb") as f:
        f.write(body)
    conn.sendall(b"HTTP/1.1 200 OK\\r\\nContent-Length: 0\\r\\n\\r\\n")
    conn.close()
    """

    /// Runs the notify script against a real one-shot capture server and returns the decoded
    /// JSON body it POSTed.
    private func capturePayload(event: String, stdinJSON: String) throws -> [String: Any] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ag-notify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let portFile = dir.appendingPathComponent("port").path
        let bodyFile = dir.appendingPathComponent("body").path

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", "-c", Self.captureServerPy, portFile, bodyFile]
        let serverErr = Pipe()
        server.standardError = serverErr
        try server.run()
        defer { if server.isRunning { server.terminate() } }

        let port = try waitForPort(file: portFile)
        _ = try runNotify(event: event, stdinJSON: stdinJSON, port: port)
        server.waitUntilExit()

        try #require(
            FileManager.default.fileExists(atPath: bodyFile),
            "capture server wrote no body (curl never connected)"
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: bodyFile))
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "captured body was not a JSON object"
        )
    }

    /// Polls `file` until the capture server has written its bound port (up to ~5s).
    private func waitForPort(file: String) throws -> String {
        for _ in 0 ..< 500 {
            if let s = try? String(contentsOfFile: file, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        Issue.record("capture server never reported its port")
        throw CancellationError()
    }

    // cwd comes from workspacePaths[0], not $PWD.
    @Test func workspacePaths_drivesReportedCwd() throws {
        let ws = "/tmp/ag-workspace-\(UUID().uuidString)"
        let payload = try capturePayload(
            event: "PreInvocation",
            stdinJSON: #"{"conversationId":"c1","workspacePaths":["\#(ws)"]}"#
        )
        let terminal = try #require(payload["terminal"] as? [String: Any])
        #expect(terminal["cwd"] as? String == ws)
    }

    @Test func normalizesConversationIdAndTranscriptPath() throws {
        let payload = try capturePayload(
            event: "PreInvocation",
            stdinJSON: #"{"conversationId":"abc-123","transcriptPath":"/t/x.jsonl"}"#
        )
        #expect(payload["agent"] as? String == "antigravity")
        let hookInput = try #require(payload["hookInput"] as? [String: Any])
        #expect(hookInput["session_id"] as? String == "abc-123")
        #expect(hookInput["transcript_path"] as? String == "/t/x.jsonl")
    }
}
