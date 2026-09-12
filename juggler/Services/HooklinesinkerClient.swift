import Foundation

enum HooklinesinkerAgent: String, CaseIterable, Sendable {
    case claude
    case codex
    case opencode
    case pi
    case droid
    case qwen
    case kimi

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .droid: "Factory Droid"
        case .qwen: "Qwen Code"
        case .kimi: "Kimi Code"
        }
    }
}

/// Verbatim exit status and captured streams, so the integration UI can show what the CLI
/// actually said instead of a synthesized message.
struct HooklinesinkerResult: Sendable {
    let exitStatus: Int32
    let standardOutput: String
    let standardError: String

    var isSuccess: Bool { exitStatus == 0 }

    /// The most useful failure text: stderr, else stdout, else the bare exit status.
    var failureMessage: String {
        let stderr = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return stdout }
        return "hooklinesinker exited with status \(exitStatus)"
    }
}

enum HooklinesinkerState: String, Sendable {
    case missing
    case installed
    case drifted
    case unsupported
}

struct HooklinesinkerHookEntry: Sendable, Equatable {
    let event: String
    let groupIndex: Int
    let command: String
}

struct HooklinesinkerHookStatus: Sendable {
    let agent: String
    let state: HooklinesinkerState
    let path: String
    let entries: [HooklinesinkerHookEntry]
}

struct HooklinesinkerSessions: Sendable {
    let statuses: [HooklinesinkerStatus]
    /// Records the CLI returned that this build could not read (wrong protocol or unknown shape).
    let skippedRecordCount: Int
    let problems: [HooklinesinkerProblem]
}

struct HooklinesinkerProblem: Sendable, Equatable {
    let observedAt: String
    let message: String

    /// Leads with when the problem was recorded (not when it was read), in compact local
    /// `yyyy-MM-dd HH:mm:ss` — sortable lexicographically and no UTC math — so a stale replay
    /// reads as old at a glance.
    var logLine: String {
        let stamp: String
        if let date = ISO8601DateFormatter().date(from: observedAt) {
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.dateFormat = "yyyy-MM-dd HH:mm:ss"
            stamp = "[\(local.string(from: date))] "
        } else if !observedAt.isEmpty {
            stamp = "[\(observedAt)] "
        } else {
            stamp = ""
        }
        return "\(stamp)hooklinesinker reported: \(message)"
    }
}

enum HooklinesinkerClientError: LocalizedError, Equatable {
    case commandFailed(command: String, status: Int32, standardError: String)
    case malformedOutput(command: String, detail: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, standardError):
            let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "hooklinesinker \(command) failed with status \(status)"
                : "hooklinesinker \(command) failed with status \(status): \(detail)"
        case let .malformedOutput(command, detail):
            return "hooklinesinker \(command) returned unreadable output: \(detail)"
        }
    }
}

/// Drives the bundled `hooklinesinker` CLI. Every path and root is injectable so tests can
/// point it at a stub binary and a throwaway XDG tree; production callers use `.shared`.
struct HooklinesinkerClient: Sendable {
    static let shared = HooklinesinkerClient()

    static let consumerName = "juggler"

    /// Enough for a doctor dump; a runaway process can't flood memory or the log.
    private static let maxCapturedBytes = 262_144

    let bundledExecutablePath: String
    let dataRoot: String
    let environmentOverrides: [String: String]
    private let sinkURLOverride: String?

    init(
        bundledExecutablePath: String = HooklinesinkerClient.defaultBundledExecutablePath,
        dataRoot: String = HooklinesinkerClient.defaultDataRoot,
        environmentOverrides: [String: String] = [:],
        sinkURL: String? = nil
    ) {
        self.bundledExecutablePath = bundledExecutablePath
        self.dataRoot = dataRoot
        self.environmentOverrides = environmentOverrides
        sinkURLOverride = sinkURL
    }

    /// Task 6 ships the binary into the bundle; until then this path may not exist in dev
    /// builds and every command reports the missing binary rather than crashing.
    static var defaultBundledExecutablePath: String {
        Bundle.main.url(forAuxiliaryExecutable: "hooklinesinker")?.path
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hooklinesinker").path
    }

    static var defaultDataRoot: String {
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return (xdg as NSString).expandingTildeInPath + "/hooklinesinker"
        }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/.local/share/hooklinesinker"
    }

    /// The hook port comes from the same source `HookServer` binds to, so a test instance on
    /// an alternate port registers a sink pointing at itself.
    var sinkURL: String {
        sinkURLOverride ?? "http://127.0.0.1:\(TestInstanceConfig.hookPort())/hook"
    }

    /// `install --consumer` promotes the bundled binary into `<dataRoot>/bin/hooklinesinker`;
    /// everything after that runs the promoted copy, which is the path the installed hooks
    /// themselves invoke.
    var installedExecutablePath: String {
        dataRoot + "/bin/hooklinesinker"
    }

    // MARK: - Consumer registration

    func installConsumer() async -> HooklinesinkerResult {
        await run(
            executable: bundledExecutablePath,
            arguments: ["install", "--consumer", Self.consumerName, "--sink", sinkURL]
        )
    }

    func uninstallConsumer() async -> HooklinesinkerResult {
        await run(
            executable: bundledExecutablePath,
            arguments: ["uninstall", "--consumer", Self.consumerName]
        )
    }

    // MARK: - Agent hooks

    func installHooks(agent: HooklinesinkerAgent) async -> HooklinesinkerResult {
        await run(
            executable: stableExecutablePath,
            arguments: ["hooks", "install", "--agent", agent.rawValue]
        )
    }

    func hookStatus(agent: HooklinesinkerAgent) async throws -> HooklinesinkerHookStatus {
        let result = await run(
            executable: stableExecutablePath,
            arguments: ["hooks", "status", "--agent", agent.rawValue, "--json"]
        )
        let command = "hooks status --agent \(agent.rawValue)"
        guard result.isSuccess else {
            throw HooklinesinkerClientError.commandFailed(
                command: command, status: result.exitStatus, standardError: result.standardError
            )
        }
        guard let root = try? JSONSerialization.jsonObject(
            with: Data(result.standardOutput.utf8)
        ) as? [String: Any] else {
            throw HooklinesinkerClientError.malformedOutput(command: command, detail: "not a JSON object")
        }
        guard root["protocol"] as? Int == HooklinesinkerStatus.supportedProtocol else {
            throw HooklinesinkerClientError.malformedOutput(
                command: command, detail: "unsupported protocol \(root["protocol"] ?? "none")"
            )
        }
        guard let rawState = root["state"] as? String, let state = HooklinesinkerState(rawValue: rawState) else {
            throw HooklinesinkerClientError.malformedOutput(
                command: command, detail: "unknown hook state \(root["state"] ?? "none")"
            )
        }
        let entries = (root["entries"] as? [[String: Any]] ?? []).compactMap { raw -> HooklinesinkerHookEntry? in
            guard let event = raw["event"] as? String,
                  let groupIndex = raw["groupIndex"] as? Int,
                  let command = raw["command"] as? String else { return nil }
            return HooklinesinkerHookEntry(event: event, groupIndex: groupIndex, command: command)
        }
        return HooklinesinkerHookStatus(
            agent: root["agent"] as? String ?? agent.rawValue,
            state: state,
            path: root["path"] as? String ?? "",
            entries: entries
        )
    }

    /// Convenience for install-status UI: an unreadable status reads as "not installed" rather
    /// than surfacing an error on a screen the user only asked to look at.
    func isInstalled(agent: HooklinesinkerAgent) async -> Bool {
        await (try? hookStatus(agent: agent))?.state == .installed
    }

    // MARK: - Session hydration

    func sessions() async throws -> HooklinesinkerSessions {
        let result = await run(executable: stableExecutablePath, arguments: ["sessions", "--json"])
        let command = "sessions --json"
        guard result.isSuccess else {
            throw HooklinesinkerClientError.commandFailed(
                command: command, status: result.exitStatus, standardError: result.standardError
            )
        }
        guard let root = try? JSONSerialization.jsonObject(
            with: Data(result.standardOutput.utf8)
        ) as? [String: Any] else {
            throw HooklinesinkerClientError.malformedOutput(command: command, detail: "not a JSON object")
        }
        guard root["protocol"] as? Int == HooklinesinkerStatus.supportedProtocol else {
            throw HooklinesinkerClientError.malformedOutput(
                command: command, detail: "unsupported protocol \(root["protocol"] ?? "none")"
            )
        }

        let raw = root["sessions"] as? [[String: Any]] ?? []
        var statuses: [HooklinesinkerStatus] = []
        var skipped = 0
        for record in raw {
            guard record["protocol"] as? Int == HooklinesinkerStatus.supportedProtocol,
                  let data = try? JSONSerialization.data(withJSONObject: record),
                  let status = try? JSONDecoder().decode(HooklinesinkerStatus.self, from: data) else {
                skipped += 1
                continue
            }
            statuses.append(status)
        }

        let problems = (root["problems"] as? [[String: Any]] ?? []).compactMap { p -> HooklinesinkerProblem? in
            guard let message = p["message"] as? String else { return nil }
            return HooklinesinkerProblem(observedAt: p["observedAt"] as? String ?? "", message: message)
        }
        return HooklinesinkerSessions(statuses: statuses, skippedRecordCount: skipped, problems: problems)
    }

    // MARK: - Process plumbing

    /// Prefer the promoted binary; fall back to the bundled one so a first run (or a wiped
    /// data root) still reports a real CLI error instead of "not found".
    private var stableExecutablePath: String {
        FileManager.default.isExecutableFile(atPath: installedExecutablePath)
            ? installedExecutablePath
            : bundledExecutablePath
    }

    private func run(executable: String, arguments: [String]) async -> HooklinesinkerResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return HooklinesinkerResult(
                exitStatus: -1,
                standardOutput: "",
                standardError: "hooklinesinker executable not found at \(executable)"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drain both pipes off the cooperative pool; a full buffer would otherwise deadlock
        // the child before it can exit.
        let outputTask = Task.detached { outputPipe.fileHandleForReading.readDataToEndOfFile() }
        let errorTask = Task.detached { errorPipe.fileHandleForReading.readDataToEndOfFile() }

        // The handler must be installed before run(): a process that exits instantly can
        // otherwise fire before the handler exists and strand the continuation.
        let exitStatus = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                try? outputPipe.fileHandleForWriting.close()
                try? errorPipe.fileHandleForWriting.close()
                continuation.resume(returning: -1)
            }
        }

        let standardOutput = await Self.boundedString(outputTask.value)
        let standardError = await Self.boundedString(errorTask.value)
        return HooklinesinkerResult(
            exitStatus: exitStatus,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    private static func boundedString(_ data: Data) -> String {
        String(bytes: data.prefix(maxCapturedBytes), encoding: .utf8)
            ?? "hooklinesinker output contains invalid or truncated UTF-8"
    }
}
