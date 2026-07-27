//
//  WezTermBridge.swift
//  Juggler
//

import AppKit
import Foundation

/// CLI-driven bridge for WezTerm. Sessions are addressed by integer pane id (`$WEZTERM_PANE`
/// inside the pane), so there is no per-session socket to register — `wezterm cli` locates the
/// running GUI instance itself. WezTerm exposes no external mechanism to set a tab/pane color
/// or to stream focus events, so `highlight` is a no-op and focus-sync is unavailable; see
/// `docs/tech/wezterm-bridge.md`.
actor WezTermBridge: TerminalBridge {
    static let shared = WezTermBridge()

    /// Fixed locations WezTerm's CLI commonly installs to — one source of truth shared by the
    /// bridge's `start()` and the setup/settings UI so their "found?" checks can't disagree.
    nonisolated static let cliCandidatePaths = [
        "/opt/homebrew/bin/wezterm",
        "/usr/local/bin/wezterm",
        "/Applications/WezTerm.app/Contents/MacOS/wezterm"
    ]

    /// Mirrors `start()`'s resolution order (candidate paths, then `PATH`) so the UI can't
    /// report a PATH-only install as missing and block setup.
    nonisolated static func locateCLI() -> String? {
        for candidate in cliCandidatePaths where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let full = URL(fileURLWithPath: String(dir)).appendingPathComponent("wezterm").path
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    private var weztermPath: String?

    /// Test seam: when set, `getSessionInfo` reads list output from this closure instead of
    /// spawning `wezterm cli list`, so the three-valued contract can be unit-tested
    /// deterministically. Set to `nil` to restore real subprocess behavior.
    private var listOutputProvider: (@Sendable () async throws -> String)?

    private init() {}

    func setListOutputProviderForTesting(_ provider: (@Sendable () async throws -> String)?) {
        listOutputProvider = provider
    }

    func start() async throws {
        if weztermPath != nil { return }

        for candidate in Self.cliCandidatePaths where FileManager.default.fileExists(atPath: candidate) {
            weztermPath = candidate
            await MainActor.run { logInfo(.daemon, "Found wezterm at \(candidate)") }
            return
        }

        if await (try? runWezTermCommand(["--version"], executableOverride: "/usr/bin/env")) != nil {
            weztermPath = "/usr/bin/env"
            await MainActor.run { logInfo(.daemon, "Found wezterm via PATH") }
            return
        }

        await MainActor.run { logWarning(.daemon, "wezterm binary not found") }
    }

    func stop() async {
        weztermPath = nil
    }

    func activate(sessionID: String) async throws {
        try await start()

        await MainActor.run { logDebug(.daemon, "Activating wezterm pane: \(sessionID)") }

        do {
            _ = try await runWezTermCommand(["cli", "activate-pane", "--pane-id", sessionID])
        } catch {
            await MainActor.run { logWarning(.daemon, "activate-pane failed for \(sessionID): \(error)") }
            throw error
        }

        // Bring the WezTerm app to the foreground — activate-pane may only select the pane
        // within an already-focused window.
        await MainActor.run {
            let script = NSAppleScript(source: #"tell application "WezTerm" to activate"#)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
    }

    /// WezTerm has no external command to color a tab or pane, so highlighting is unavailable.
    func highlight(sessionID _: String, tabConfig _: HighlightConfig?, paneConfig _: HighlightConfig?) async throws {}

    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo? {
        let output: String
        if let listOutputProvider {
            output = try await listOutputProvider()
        } else {
            try await start()
            // A non-zero exit / timeout / missing GUI instance throws from runWezTermCommand —
            // the three-valued contract requires "couldn't determine" to throw, never nil.
            guard let commandOutput = try await runWezTermCommand(["cli", "list", "--format", "json"]) else {
                throw TerminalBridgeError.invalidResponse
            }
            output = commandOutput
        }
        // Exit 0 but output isn't a decodable JSON array is still "couldn't determine" (a
        // transient truncated/empty read), so throw rather than resolve to nil — a nil here
        // would let `TerminalActivation.isSessionGone` evict a live session. Only a well-formed
        // array that lacks the pane is a confirmed removal.
        guard let panes = Self.decodeWezTermPanes(output) else {
            throw TerminalBridgeError.invalidResponse
        }
        return Self.parseWezTermList(panes, paneID: sessionID)
    }

    /// Decodes `wezterm cli list --format json` into the raw pane array, or `nil` if the output
    /// is not a decodable JSON array. `getSessionInfo` relies on the `nil` case to tell
    /// "couldn't determine" (throw) apart from a valid-but-paneless list ("confirmed gone").
    nonisolated static func decodeWezTermPanes(_ output: String) -> [[String: Any]]? {
        guard let data = output.data(using: .utf8),
              let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return panes
    }

    /// `isActive` is best-effort `false` — WezTerm's `list` output carries no active-pane flag.
    nonisolated static func parseWezTermList(_ panes: [[String: Any]], paneID: String) -> TerminalSessionInfo? {
        guard let target = panes.first(where: { paneIDString($0["pane_id"]) == paneID }) else { return nil }

        let windowID = target["window_id"] as? Int
        let tabID = target["tab_id"] as? Int

        // Panes sharing this pane's window AND tab give the pane index/count. Keyed on both
        // dimensions (not tab_id alone) so panes from a different window that happen to share a
        // tab_id value can't inflate the count — matching the window-scoped tab-index logic below.
        let tabPanes = panes.filter {
            ($0["window_id"] as? Int) == windowID && ($0["tab_id"] as? Int) == tabID
        }
        let paneIndex = tabPanes.firstIndex { paneIDString($0["pane_id"]) == paneID } ?? 0

        // Distinct tabs within this window, in list order, give the tab index.
        let windowPanes = panes.filter { ($0["window_id"] as? Int) == windowID }
        var orderedTabIDs: [Int] = []
        for pane in windowPanes {
            if let tid = pane["tab_id"] as? Int, !orderedTabIDs.contains(tid) {
                orderedTabIDs.append(tid)
            }
        }
        let tabIndex = tabID.flatMap { orderedTabIDs.firstIndex(of: $0) } ?? 0

        return TerminalSessionInfo(
            id: paneID,
            tabName: target["title"] as? String ?? "Tab \(tabIndex + 1)",
            windowName: windowID.map { "Window \($0)" } ?? "WezTerm",
            tabIndex: tabIndex,
            paneIndex: paneIndex,
            paneCount: tabPanes.count,
            isActive: false
        )
    }

    /// `pane_id` decodes as `Int` from JSON; normalise to a string for comparison with the
    /// hook-supplied `$WEZTERM_PANE` value.
    private nonisolated static func paneIDString(_ value: Any?) -> String? {
        if let int = value as? Int { return String(int) }
        if let str = value as? String { return str }
        return nil
    }

    /// Drains stdout/stderr on detached tasks to avoid a buffer-full deadlock, with a 5 s
    /// timeout guard. Mirrors `KittyBridge`.
    private func runWezTermCommand(
        _ arguments: [String],
        executableOverride: String? = nil
    ) async throws -> String? {
        let executable = executableOverride ?? weztermPath ?? "/usr/bin/env"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)

        var args: [String] = []
        if executable == "/usr/bin/env" {
            args.append("wezterm")
        }
        args.append(contentsOf: arguments)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }

        let timeoutTask = Task.detached {
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning { process.terminate() }
        }

        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            Int32,
            any Error
        >) in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        timeoutTask.cancel()

        let data = await stdoutTask.value
        let errData = await stderrTask.value

        guard status == 0 else {
            let errOutput = (String(bytes: errData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalBridgeError.commandFailed(
                errOutput.isEmpty ? "wezterm command failed with status \(status)" : errOutput
            )
        }

        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
