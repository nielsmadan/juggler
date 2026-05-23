//
//  WezTermBridge.swift
//  Juggler
//

import AppKit
import Foundation

actor WezTermBridge: TerminalBridge {
    static let shared = WezTermBridge()

    private var wezTermPath: String?
    private var activeTabResetTasks: [String: Task<Void, Never>] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var trackedPaneIDs: Set<String> = []

    private init() {}

    func registerPane(paneID: String) {
        trackedPaneIDs.insert(paneID)
    }

    func start() async throws {
        if wezTermPath != nil { return }

        let candidates = [
            "/Applications/WezTerm.app/Contents/MacOS/wezterm",
            "/usr/local/bin/wezterm",
            "/opt/homebrew/bin/wezterm"
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            wezTermPath = candidate
            await MainActor.run {
                logInfo(.daemon, "Found wezterm at \(candidate)")
            }
            startReconcileLoop()
            return
        }

        let result = try? await runWezTermCommand(["--version"], executableOverride: "/usr/bin/env")
        if result != nil {
            wezTermPath = "/usr/bin/env"
            await MainActor.run {
                logInfo(.daemon, "Found wezterm via PATH")
            }
            startReconcileLoop()
            return
        }

        await MainActor.run {
            logWarning(.daemon, "wezterm binary not found")
        }
    }

    private func startReconcileLoop() {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.reconcile()
            }
        }
    }

    func reconcile() async {
        guard wezTermPath != nil else { return }
        guard let output = try? await runWezTermCommand(["cli", "list", "--format", "json"]) else { return }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let livePaneIDs = Set(json.compactMap { ($0["pane_id"] as? Int).map(String.init) })
        let stalePaneIDs = trackedPaneIDs.subtracting(livePaneIDs)

        guard !stalePaneIDs.isEmpty else { return }

        for sid in stalePaneIDs {
            trackedPaneIDs.remove(sid)
        }

        await MainActor.run { [stalePaneIDs] in
            logDebug(.daemon, "WezTerm reconcile: removing \(stalePaneIDs.count) stale pane(s)")
            for sid in stalePaneIDs {
                SessionManager.shared.removeSessionsByTerminalID(sid)
            }
        }
    }

    func stop() async {
        for (_, task) in activeTabResetTasks {
            task.cancel()
        }
        activeTabResetTasks.removeAll()
        reconcileTask?.cancel()
        reconcileTask = nil
        trackedPaneIDs.removeAll()
        wezTermPath = nil
    }

    func testConnection() async throws {
        try await start()

        guard wezTermPath != nil else {
            throw TerminalBridgeError.commandFailed("Could not find the wezterm binary")
        }

        let isRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.github.wez.wezterm" }
        }
        guard isRunning else {
            throw TerminalBridgeError.commandFailed("WezTerm is not running. Please start WezTerm and try again.")
        }

        _ = try await runWezTermCommand(["cli", "list", "--format", "json"])
    }

    private func runWezTermCommand(
        _ arguments: [String],
        executableOverride: String? = nil,
        stdinData: Data? = nil
    ) async throws -> String? {
        let executable = executableOverride ?? wezTermPath ?? "/usr/bin/env"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)

        var args: [String] = []
        if executable == "/usr/bin/env", executableOverride == nil {
            args.append("wezterm")
        }
        args.append(contentsOf: arguments)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe? = stdinData != nil ? Pipe() : nil
        if let stdinPipe {
            process.standardInput = stdinPipe
        }

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
                if let stdinPipe, let stdinData {
                    try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                    try? stdinPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        timeoutTask.cancel()

        let data = await stdoutTask.value
        let errData = await stderrTask.value

        guard status == 0 else {
            let errOutput = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalBridgeError.commandFailed(
                errOutput.isEmpty
                    ? "wezterm command failed with status \(status)"
                    : errOutput
            )
        }

        return String(decoding: data, as: UTF8.self)
    }

    func activate(sessionID: String) async throws {
        try await start()
        guard wezTermPath != nil else {
            throw TerminalBridgeError.commandFailed("wezterm binary not found")
        }

        await MainActor.run {
            logDebug(.daemon, "Activating WezTerm pane: \(sessionID)")
        }

        do {
            _ = try await runWezTermCommand(["cli", "activate-pane", "--pane-id", sessionID])
        } catch let error as TerminalBridgeError {
            // If wezterm reports the pane doesn't exist, surface sessionNotFound so
            // TerminalActivation can clean up the stale session.
            if case let .commandFailed(message) = error,
               message.localizedCaseInsensitiveContains("no pane") ||
               message.localizedCaseInsensitiveContains("not found") {
                throw TerminalBridgeError.sessionNotFound(sessionID)
            }
            await MainActor.run {
                logWarning(.daemon, "activate-pane failed for \(sessionID): \(error)")
            }
            throw error
        }

        await MainActor.run {
            let script = NSAppleScript(source: #"tell application "WezTerm" to activate"#)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }

        await MainActor.run {
            logDebug(.daemon, "WezTerm pane activated: \(sessionID)")
        }
    }

    func rgbToHex(_ color: [Int]) -> String {
        guard color.count >= 3 else { return "FF0000" }
        return String(format: "%02X%02X%02X", color[0], color[1], color[2])
    }

    func userVarOSCPayload(name: String, value: String) -> String {
        let encoded = Data(value.utf8).base64EncodedString()
        return "\u{1B}]1337;SetUserVar=\(name)=\(encoded)\u{07}"
    }

    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws {
        // Pane background highlighting is not supported by WezTerm at runtime.
        // Silently skip the pane portion; UI surfaces this in the description.
        _ = paneConfig

        try await start()
        guard wezTermPath != nil else { return }

        guard let tabConfig, tabConfig.enabled else { return }

        activeTabResetTasks[sessionID]?.cancel()

        let hex = rgbToHex(tabConfig.color)
        let setPayload = userVarOSCPayload(name: "juggler_color", value: hex)
        _ = try? await runWezTermCommand(
            ["cli", "send-text", "--pane-id", sessionID, "--no-paste"],
            stdinData: Data(setPayload.utf8)
        )

        if tabConfig.duration > 0 {
            let sid = sessionID
            activeTabResetTasks[sessionID] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(tabConfig.duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let clearPayload = await userVarOSCPayload(name: "juggler_color", value: "")
                _ = try? await runWezTermCommand(
                    ["cli", "send-text", "--pane-id", sid, "--no-paste"],
                    stdinData: Data(clearPayload.utf8)
                )
            }
        }
    }

    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo? {
        try await start()
        guard wezTermPath != nil else { return nil }

        do {
            guard let output = try await runWezTermCommand(["cli", "list", "--format", "json"])
            else { return nil }
            return parseWezTermListOutput(output, paneID: sessionID)
        } catch {
            await MainActor.run {
                logDebug(.daemon, "getSessionInfo failed for \(sessionID): \(error)")
            }
            return nil
        }
    }

    // MARK: - Parsing

    nonisolated func parseWezTermListOutput(_ output: String, paneID: String) -> TerminalSessionInfo? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        guard let target = json.first(where: { ($0["pane_id"] as? Int).map(String.init) == paneID })
        else { return nil }

        let windowID = (target["window_id"] as? Int) ?? 0
        let tabID = (target["tab_id"] as? Int) ?? 0
        let tabTitle = (target["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let tabPanes = json.filter {
            ($0["window_id"] as? Int) == windowID && ($0["tab_id"] as? Int) == tabID
        }
        let sortedPanes = tabPanes.sorted { lhs, rhs in
            ((lhs["pane_id"] as? Int) ?? 0) < ((rhs["pane_id"] as? Int) ?? 0)
        }
        let paneIndex = sortedPanes.firstIndex { ($0["pane_id"] as? Int).map(String.init) == paneID } ?? 0

        // Tab-index computation assumes wezterm cli list returns entries in pane-id-ordered groups per tab
        var seenTabs: [Int] = []
        for entry in json where (entry["window_id"] as? Int) == windowID {
            if let t = entry["tab_id"] as? Int, !seenTabs.contains(t) {
                seenTabs.append(t)
            }
        }
        let tabIndex = seenTabs.firstIndex(of: tabID) ?? 0

        let isActive = (target["is_active"] as? Bool) ?? false

        return TerminalSessionInfo(
            id: paneID,
            tabName: tabTitle ?? "Tab \(tabIndex + 1)",
            windowName: tabTitle == nil ? "WezTerm" : "Window \(windowID)",
            tabIndex: tabIndex,
            paneIndex: paneIndex,
            paneCount: sortedPanes.count,
            isActive: isActive
        )
    }
}
