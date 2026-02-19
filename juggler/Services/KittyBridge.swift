//
//  KittyBridge.swift
//  Juggler
//

import Foundation

actor KittyBridge: TerminalBridge {
    static let shared = KittyBridge()

    // Maps window ID → Unix socket path (populated from hook payloads)
    private var socketPaths: [String: String] = [:]
    // Tracks original background colors for highlight reset
    private var originalColors: [String: String] = [:]
    // Manages timed highlight resets (separate for tab and pane)
    private var activeTabResetTasks: [String: Task<Void, Never>] = [:]
    private var activePaneResetTasks: [String: Task<Void, Never>] = [:]

    private var kittenPath: String?

    private init() {}

    func registerSocket(windowID: String, socketPath: String) {
        socketPaths[windowID] = socketPath
    }

    func start() async throws {
        // Already started
        if kittenPath != nil { return }

        // Find kitten binary
        let candidates = [
            "/Applications/kitty.app/Contents/MacOS/kitten",
            "/usr/local/bin/kitten",
            "/opt/homebrew/bin/kitten",
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            kittenPath = candidate
            await MainActor.run {
                logInfo(.kitty, "Found kitten at \(candidate)")
            }
            return
        }

        // Try PATH lookup
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

        // Focus the window via kitten remote control
        _ = try await runKittenCommand(
            ["@", "focus-window", "--match", "id:\(sessionID)"],
            socketPath: socketPath
        )

        // Bring Kitty app to front via AppleScript
        let script = NSAppleScript(source: #"tell application "kitty" to activate"#)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        await MainActor.run {
            logDebug(.kitty, "Kitty window activated: \(sessionID)")
        }
    }

    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws {
        guard let socketPath = socketPaths[sessionID] else { return }

        // Tab highlight via set-tab-color
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

        // Pane highlight via set-colors
        if let paneConfig, paneConfig.enabled {
            activePaneResetTasks[sessionID]?.cancel()

            // Save original color if not already saved
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

        guard let output = try? await runKittenCommand(
            ["@", "ls"],
            socketPath: socketPath
        ) else { return nil }

        return parseKittyLsOutput(output, windowID: sessionID)
    }

    // MARK: - Helpers

    private func rgbToHex(_ color: [Int]) -> String {
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

        // Build args: kitten @ --to <socket> <subcommand> <args...>
        // The @ must come first, then --to, then the rest of the arguments
        var args: [String] = []
        if executable == "/usr/bin/env", kittenOverride == nil {
            args.append("kitten")
        }

        // Split arguments: first element should be "@", rest are subcommand + flags
        if let atIdx = arguments.firstIndex(of: "@") {
            args.append("@")
            if let socketPath {
                args.append(contentsOf: ["--to", socketPath])
            }
            args.append(contentsOf: arguments[(atIdx + 1)...])
        } else {
            // No @ prefix (e.g. --version), just pass through
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

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalBridgeError.commandFailed(
                errOutput.isEmpty
                    ? "kitten command failed with status \(process.terminationStatus)"
                    : errOutput
            )
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
