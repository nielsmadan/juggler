//
//  KittyBridge.swift
//  Juggler
//

import AppKit
import Foundation

actor KittyBridge: TerminalBridge {
    static let shared = KittyBridge()

    // Populated from hook payloads
    private var socketPaths: [String: String] = [:]
    private var originalColors: [String: String] = [:]
    private var activeTabResetTasks: [String: Task<Void, Never>] = [:]
    private var activePaneResetTasks: [String: Task<Void, Never>] = [:]

    private var kittenPath: String?

    private init() {}

    func registerSocket(windowID: String, socketPath: String) {
        socketPaths[windowID] = socketPath
    }

    /// Lists candidate kitty control sockets on disk (`unix:/tmp/kitty-*`). Injectable so
    /// socket selection is testable without a live /tmp scan.
    private var socketCandidatesProvider: @Sendable () -> [String] = KittyBridge.defaultSocketCandidates

    /// Test-only: override the socket-candidate discovery.
    func setSocketCandidatesProvider(_ provider: @escaping @Sendable () -> [String]) {
        socketCandidatesProvider = provider
    }

    nonisolated static func defaultSocketCandidates() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/tmp"),
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("kitty-") }
            .map { "unix:\($0.path)" }
    }

    /// Test-only: read the socket mapped to a window id.
    func socketPath(forWindowID windowID: String) -> String? {
        socketPaths[windowID]
    }

    /// Sets up local addressing for a kitty session from a hook event. Remote sessions'
    /// `KITTY_LISTEN_ON` is a remote path — unusable locally and it would clobber the
    /// socket the watcher discovers — so they resolve a local socket instead.
    func prepareAddressing(sessionID: String, context: HookAddressingContext) async {
        try? await start() // ensure kitten is located for later activation / probing
        if context.isRemote {
            await registerLocalSocket(forWindowID: sessionID)
        } else if let socket = context.listenSocket, socket.hasPrefix("unix:"), socket.contains("kitty") {
            registerSocket(windowID: sessionID, socketPath: socket)
        } else {
            await MainActor.run {
                logWarning(.kitty, "Kitty hook without usable kittyListenOn (window \(sessionID))")
            }
        }
    }

    /// Maps a locally-discovered kitty control socket to `windowID`. Used for live window
    /// ids reported by the local watcher and for remote sessions, whose hook-supplied
    /// `KITTY_LISTEN_ON` is a remote, unusable path. With multiple kitty instances, picks
    /// the instance that actually owns the window so activation can't hit the wrong one.
    func registerLocalSocket(forWindowID windowID: String) async {
        let candidates = socketCandidatesProvider()
        guard !candidates.isEmpty else {
            await MainActor.run { logWarning(.kitty, "No local kitty socket found for window \(windowID)") }
            return
        }
        if candidates.count == 1 {
            socketPaths[windowID] = candidates[0]
            return
        }
        for candidate in candidates where await socketOwnsWindow(candidate, windowID: windowID) {
            socketPaths[windowID] = candidate
            return
        }
        await MainActor.run {
            logWarning(.kitty, "No kitty instance owns window \(windowID) among \(candidates.count) sockets")
        }
    }

    /// Whether the kitty instance behind `socketPath` currently has a window with `windowID`.
    private func socketOwnsWindow(_ socketPath: String, windowID: String) async -> Bool {
        guard let json = try? await runKittenCommand(["@", "ls"], socketPath: socketPath) else { return false }
        return parseKittyLsOutput(json, windowID: windowID) != nil
    }

    func start() async throws {
        if kittenPath != nil { return }

        let candidates = [
            "/Applications/kitty.app/Contents/MacOS/kitten",
            "/usr/local/bin/kitten",
            "/opt/homebrew/bin/kitten"
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            kittenPath = candidate
            await MainActor.run {
                logInfo(.kitty, "Found kitten at \(candidate)")
            }
            return
        }

        let result = try? await runKittenCommand(["--version"], socketPath: nil, kittenOverride: "/usr/bin/env")
        if result != nil {
            kittenPath = "/usr/bin/env"
            await MainActor.run {
                logInfo(.kitty, "Found kitten via PATH")
            }
            return
        }

        await MainActor.run {
            logWarning(.kitty, "kitten binary not found")
        }
    }

    func testConnection() async throws {
        try await start()

        guard kittenPath != nil else {
            throw TerminalBridgeError.commandFailed("Could not find the kitten binary")
        }

        let isRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "net.kovidgoyal.kitty" }
        }
        guard isRunning else {
            throw TerminalBridgeError.commandFailed("Kitty is not running. Please start Kitty and try again.")
        }

        // GUI apps don't inherit KITTY_LISTEN_ON, so kitten @ ls without --to hangs.
        // Discover a socket on disk instead.
        let socketPath = try discoverKittySocket()
        _ = try await runKittenCommand(["@", "ls"], socketPath: socketPath)
    }

    private func discoverKittySocket() throws -> String {
        guard let socket = socketCandidatesProvider().first else {
            throw TerminalBridgeError.commandFailed(
                "No Kitty socket found. Ensure listen_on is configured in kitty.conf and restart Kitty."
            )
        }
        return socket
    }

    func stop() async {
        for (_, task) in activeTabResetTasks {
            task.cancel()
        }
        for (_, task) in activePaneResetTasks {
            task.cancel()
        }
        activeTabResetTasks.removeAll()
        activePaneResetTasks.removeAll()
        socketPaths.removeAll()
        originalColors.removeAll()
        kittenPath = nil
    }

    func activate(sessionID: String) async throws {
        guard let socketPath = socketPaths[sessionID] else {
            let registeredKeys = Array(socketPaths.keys)
            await MainActor.run {
                logWarning(.kitty, "No socket path for window \(sessionID). Registered: \(registeredKeys)")
            }
            // Use connectionFailed, not sessionNotFound — the session exists but we can't reach it.
            // sessionNotFound would cause the cycling loop to remove the session and retry infinitely.
            throw TerminalBridgeError.connectionFailed
        }

        await MainActor.run {
            logDebug(.kitty, "Activating kitty window: \(sessionID) via \(socketPath)")
        }

        do {
            _ = try await runKittenCommand(
                ["@", "focus-window", "--match", "id:\(sessionID)"],
                socketPath: socketPath
            )
        } catch {
            await MainActor.run {
                logWarning(.kitty, "focus-window failed for \(sessionID): \(error)")
            }
            throw error
        }

        await MainActor.run {
            let script = NSAppleScript(source: #"tell application "kitty" to activate"#)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }

        await MainActor.run {
            logDebug(.kitty, "Kitty window activated: \(sessionID)")
        }
    }

    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws {
        guard let socketPath = socketPaths[sessionID] else { return }

        if let tabConfig, tabConfig.enabled {
            activeTabResetTasks[sessionID]?.cancel()

            let hexColor = rgbToHex(tabConfig.color)
            _ = try? await runKittenCommand(
                ["@", "set-tab-color", "--match", "window_id:\(sessionID)", "active_bg=\(hexColor)"],
                socketPath: socketPath
            )

            if tabConfig.duration > 0 {
                let sid = sessionID
                let sock = socketPath
                activeTabResetTasks[sessionID] = Task {
                    try? await Task.sleep(nanoseconds: UInt64(tabConfig.duration * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    _ = try? await self.runKittenCommand(
                        ["@", "set-tab-color", "--match", "window_id:\(sid)", "active_bg=none"],
                        socketPath: sock
                    )
                }
            }
        }

        if let paneConfig, paneConfig.enabled {
            activePaneResetTasks[sessionID]?.cancel()

            if originalColors[sessionID] == nil {
                if let lsOutput = try? await runKittenCommand(
                    ["@", "get-colors", "--match", "id:\(sessionID)"],
                    socketPath: socketPath
                ) {
                    for line in lsOutput.split(separator: "\n") {
                        let parts = line.split(separator: " ")
                        if parts.first == "background", parts.count >= 2 {
                            originalColors[sessionID] = String(parts[1])
                        }
                    }
                }
            }

            let hexColor = rgbToHex(paneConfig.color)
            _ = try? await runKittenCommand(
                ["@", "set-colors", "--match", "id:\(sessionID)", "background=\(hexColor)"],
                socketPath: socketPath
            )

            if paneConfig.duration > 0 {
                let sid = sessionID
                let sock = socketPath
                activePaneResetTasks[sessionID] = Task {
                    try? await Task.sleep(nanoseconds: UInt64(paneConfig.duration * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    if let original = await self.originalColors.removeValue(forKey: sid) {
                        _ = try? await self.runKittenCommand(
                            ["@", "set-colors", "--match", "id:\(sid)", "background=\(original)"],
                            socketPath: sock
                        )
                    }
                }
            }
        }
    }

    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo? {
        guard let socketPath = socketPaths[sessionID] else { return nil }

        guard let output = try await runKittenCommand(
            ["@", "ls"],
            socketPath: socketPath
        ) else { return nil }

        return parseKittyLsOutput(output, windowID: sessionID)
    }

    func rgbToHex(_ color: [Int]) -> String {
        guard color.count >= 3 else { return "#FF0000" }
        return String(format: "#%02X%02X%02X", color[0], color[1], color[2])
    }

    nonisolated func parseKittyLsOutput(_ output: String, windowID: String) -> TerminalSessionInfo? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        // Kitty ls output is an array of OS windows, each containing tabs, each containing windows (panes)
        for osWindow in json {
            guard let tabs = osWindow["tabs"] as? [[String: Any]] else { continue }
            for (tabIndex, tab) in tabs.enumerated() {
                guard let windows = tab["windows"] as? [[String: Any]] else { continue }
                for (paneIndex, window) in windows.enumerated() {
                    guard let id = window["id"] as? Int, String(id) == windowID else { continue }

                    let tabTitle = tab["title"] as? String ?? "Tab \(tabIndex + 1)"
                    let windowTitle = osWindow["platform_window_id"] as? Int
                    let isFocused = window["is_focused"] as? Bool ?? false

                    return TerminalSessionInfo(
                        id: windowID,
                        tabName: tabTitle,
                        windowName: windowTitle.map { "Window \($0)" } ?? "Kitty",
                        tabIndex: tabIndex,
                        paneIndex: paneIndex,
                        paneCount: windows.count,
                        isActive: isFocused
                    )
                }
            }
        }

        return nil
    }

    private func runKittenCommand(
        _ arguments: [String],
        socketPath: String?,
        kittenOverride: String? = nil
    ) async throws -> String? {
        let executable = kittenOverride ?? kittenPath ?? "/usr/bin/env"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)

        var args: [String] = []
        if executable == "/usr/bin/env", kittenOverride == nil {
            args.append("kitten")
        }

        if let atIdx = arguments.firstIndex(of: "@") {
            args.append("@")
            if let socketPath {
                args.append(contentsOf: ["--to", socketPath])
            }
            args.append(contentsOf: arguments[(atIdx + 1)...])
        } else {
            if let socketPath {
                args.append(contentsOf: ["--to", socketPath])
            }
            args.append(contentsOf: arguments)
        }
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Drain pipes on detached tasks to prevent buffer-full deadlock
        let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }

        let timeoutTask = Task.detached {
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning {
                process.terminate()
            }
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
                errOutput.isEmpty
                    ? "kitten command failed with status \(status)"
                    : errOutput
            )
        }

        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
