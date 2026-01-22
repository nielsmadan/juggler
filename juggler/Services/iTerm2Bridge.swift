//
//  iTerm2Bridge.swift
//  Juggler
//

import Foundation
import SwiftUI

actor ITerm2Bridge: TerminalBridge {
    static let shared = ITerm2Bridge()

    private var daemonProcess: Process?
    private let socketPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Juggler")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("iterm2_daemon.sock").path
    }()

    private var eventReadSource: DispatchSourceRead?
    private var eventSocket: Int32 = -1
    private let eventQueue = DispatchQueue(label: "com.juggler.eventlistener")
    private var eventLineBuffer = Data()

    private var healthCheckTask: Task<Void, Never>?

    private let connectionTimeout: TimeInterval = 1.0
    private let activateTimeout: TimeInterval = 2.0
    private let listTimeout: TimeInterval = 3.0
    private let highlightTimeout: TimeInterval = 1.0

    private init() {}

    func start() async throws {
        guard daemonProcess == nil else { return }

        await MainActor.run { logInfo(.daemon, "Starting iTerm2 daemon...") }

        // Triggers Automation permission dialog on first run
        let cookieAndKey: String
        do {
            cookieAndKey = try requestCookie()
        } catch {
            await MainActor.run { logError(.daemon, "Failed to get iTerm2 cookie: \(error)") }
            throw error
        }
        let parts = cookieAndKey.split(separator: " ")
        let cookie = String(parts[0])
        let key = parts.count > 1 ? String(parts[1]) : ""

        let daemonPath = Bundle.main.path(forResource: "iterm2_daemon", ofType: "py")

        // iTerm2's bundled Python has the iterm2 module pre-installed
        let iterm2PythonBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iTerm2/iterm2env/versions")

        var pythonPath: String?
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: iterm2PythonBase.path) {
            for version in contents.sorted().reversed() {
                let candidate = iterm2PythonBase
                    .appendingPathComponent(version)
                    .appendingPathComponent("bin/python3")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    pythonPath = candidate.path
                    break
                }
            }
        }

        let python = pythonPath ?? "/usr/bin/python3"

        guard let daemonPath else {
            await MainActor.run { logError(.daemon, "iterm2_daemon.py not found in bundle") }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [daemonPath, socketPath]

        var env = ProcessInfo.processInfo.environment
        env["ITERM2_COOKIE"] = cookie
        env["ITERM2_KEY"] = key
        process.environment = env

        process.standardOutput = FileHandle.nullDevice
        // Keep stderr visible for debugging daemon issues
        process.standardError = FileHandle.standardError

        try process.run()
        daemonProcess = process

        for _ in 0 ..< 50 {
            if FileManager.default.fileExists(atPath: socketPath) {
                await MainActor.run { logInfo(.daemon, "Daemon socket ready") }
                startEventListener()
                startHealthCheck()
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        await MainActor.run { logWarning(.daemon, "Daemon socket not found after 5 seconds") }
    }

    // MARK: - Event Listener (DispatchSource-based, non-blocking)

    private nonisolated func startEventListener() {
        eventQueue.async { [self] in
            do {
                let sock = try connectEventSocket()

                Task { await self.setEventSocket(sock) }

                let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: eventQueue)

                source.setEventHandler { [self] in
                    handleSocketData(socket: sock)
                }

                source.setCancelHandler {
                    close(sock)
                    Task { @MainActor in
                        logInfo(.daemon, "Focus event listener disconnected")
                    }
                }

                Task { await self.setEventReadSource(source) }
                source.resume()

                Task { @MainActor in
                    logInfo(.daemon, "Focus event listener connected")
                }
            } catch {
                Task { @MainActor in
                    logWarning(.daemon, "Event listener failed to connect: \(error)")
                }
            }
        }
    }

    private func setEventSocket(_ sock: Int32) {
        eventSocket = sock
    }

    private func setEventReadSource(_ source: DispatchSourceRead) {
        eventReadSource = source
    }

    private nonisolated func connectEventSocket() throws -> Int32 {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw TerminalBridgeError.daemonNotRunning
        }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw TerminalBridgeError.connectionFailed
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            close(sock)
            throw TerminalBridgeError.connectionFailed
        }

        let subscribeRequest = "{\"command\": \"subscribe\"}\n"
        _ = subscribeRequest.withCString { ptr in
            send(sock, ptr, strlen(ptr), 0)
        }

        // Read acknowledgment with timeout to avoid hanging if daemon is stuck
        var ackTimeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &ackTimeout, socklen_t(MemoryLayout<timeval>.size))

        var ackBuffer = [UInt8](repeating: 0, count: 1024)
        let ackBytes = recv(sock, &ackBuffer, ackBuffer.count, 0)
        guard ackBytes > 0 else {
            close(sock)
            throw TerminalBridgeError.invalidResponse
        }

        return sock
    }

    private nonisolated func handleSocketData(socket sock: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(sock, &buffer, buffer.count, Int32(MSG_DONTWAIT))

        if bytesRead == 0 {
            // Connection closed by peer
            Task { await self.cancelEventListener() }
            return
        }
        if bytesRead < 0 {
            // EAGAIN/EWOULDBLOCK = no data available (normal for non-blocking recv)
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            // Actual error — connection is broken
            Task { await self.cancelEventListener() }
            return
        }

        Task { await self.processReceivedData(Data(buffer[0 ..< bytesRead])) }
    }

    private func cancelEventListener() {
        eventReadSource?.cancel()
        eventReadSource = nil
        eventSocket = -1
        if daemonProcess != nil {
            scheduleEventListenerReconnect()
        }
    }

    private func scheduleEventListenerReconnect() {
        Task {
            await MainActor.run { logWarning(.daemon, "Event listener disconnected, attempting reconnect...") }
            for delay in [2.0, 5.0, 10.0, 15.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard daemonProcess != nil else { return }
                guard eventReadSource == nil else { return } // already reconnected

                guard FileManager.default.fileExists(atPath: socketPath) else { continue }

                await MainActor.run { logInfo(.daemon, "Reconnecting event listener...") }
                startEventListener()
                try? await Task.sleep(nanoseconds: 500_000_000)
                if eventReadSource != nil {
                    await MainActor.run { logInfo(.daemon, "Event listener reconnected") }
                    return
                }
            }
            // All retries exhausted — full daemon restart
            await MainActor.run { logWarning(.daemon, "Event listener reconnect failed, restarting daemon...") }
            try? await restart()
        }
    }

    private func startHealthCheck() {
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                guard daemonProcess != nil else { continue }

                let request = DaemonRequest(command: "ping")
                do {
                    _ = try await sendRequest(request)
                } catch {
                    await MainActor.run { logWarning(.daemon, "Health check failed: \(error)") }
                    if eventReadSource == nil {
                        scheduleEventListenerReconnect()
                    }
                }
            }
        }
    }

    private func processReceivedData(_ data: Data) async {
        eventLineBuffer.append(data)

        while let newlineIndex = eventLineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = eventLineBuffer[eventLineBuffer.startIndex ..< newlineIndex]
            eventLineBuffer.removeSubrange(eventLineBuffer.startIndex ... newlineIndex)

            if let event = try? JSONDecoder().decode(DaemonEvent.self, from: Data(lineData)) {
                await handleDaemonEvent(event)
            }
        }
    }

    func stop() async {
        // Clear daemon process first so cancelEventListener doesn't trigger reconnect
        let process = daemonProcess
        daemonProcess = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        eventReadSource?.cancel()
        eventReadSource = nil
        eventSocket = -1
        eventLineBuffer.removeAll()
        process?.terminate()
        if let process, process.isRunning {
            let deadline = Date().addingTimeInterval(1.0)
            while process.isRunning, Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
            if process.isRunning {
                process.interrupt()
            }
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        await MainActor.run { logInfo(.daemon, "Daemon stopped") }
    }

    // MARK: - Connection Recovery

    private func shouldAttemptRecovery(_ error: Error) -> Bool {
        if let bridgeError = error as? TerminalBridgeError {
            switch bridgeError {
            case .daemonNotRunning, .connectionFailed, .connectionTimeout,
                 .commandTimeout, .invalidResponse:
                return true
            case .commandFailed, .authenticationFailed:
                return false
            }
        }
        let message = String(describing: error)
        return message.contains("Input/output error")
            || message.contains("Errno 5")
            || message.contains("Broken pipe")
            || message.contains("Connection reset")
    }

    func restart() async throws {
        await MainActor.run { logWarning(.daemon, "Restarting daemon due to stale connection...") }
        await stop()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms grace period
        try await start()
    }

    @MainActor
    private func handleDaemonEvent(_ event: DaemonEvent) {
        switch event.event {
        case "focus_changed":
            logDebug(.daemon, "Focus changed to: \(event.sessionID ?? "nil")")
            SessionManager.shared.updateFocusedSession(terminalSessionID: event.sessionID)
        case "terminal_info":
            guard let sessionID = event.sessionID else { return }
            logDebug(.daemon, "Terminal info update for: \(sessionID)")
            SessionManager.shared.updateSessionTerminalInfo(
                terminalSessionID: sessionID,
                tabName: event.tabName ?? "Tab",
                windowName: event.windowName ?? "Window",
                paneIndex: event.paneIndex ?? 0,
                paneCount: event.paneCount ?? 1
            )
        default:
            logDebug(.daemon, "Unknown event: \(event.event)")
        }
    }

    private nonisolated func requestCookie() throws -> String {
        let script = """
        tell application "iTerm2" to request cookie and key for app named "Juggler"
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw TerminalBridgeError.authenticationFailed("Failed to create AppleScript")
        }

        let result = appleScript.executeAndReturnError(&error)

        if let error {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw TerminalBridgeError.authenticationFailed(errorMessage)
        }

        guard let cookieAndKey = result.stringValue else {
            throw TerminalBridgeError.authenticationFailed("No cookie returned")
        }

        // Format is "cookie key" - we need both
        let parts = cookieAndKey.split(separator: " ")
        guard parts.count >= 1 else {
            throw TerminalBridgeError.authenticationFailed("Invalid cookie format")
        }

        return cookieAndKey
    }

    func activate(sessionID: String) async throws {
        await MainActor.run { logDebug(.daemon, "Activating session: \(sessionID)") }
        let request = DaemonRequest(command: "activate", sessionID: sessionID)
        do {
            _ = try await withTimeout(activateTimeout) {
                try await self.sendRequest(request)
            }
            await MainActor.run { logDebug(.daemon, "Session activated: \(sessionID)") }
        } catch {
            if shouldAttemptRecovery(error) {
                await MainActor.run { logWarning(.daemon, "Stale connection detected, attempting recovery...") }
                do {
                    try await restart()
                    _ = try await withTimeout(activateTimeout) {
                        try await self.sendRequest(request)
                    }
                    await MainActor.run { logDebug(.daemon, "Session activated after recovery: \(sessionID)") }
                    return
                } catch {
                    await MainActor.run { logError(.daemon, "Recovery failed: \(error)") }
                    throw error
                }
            }
            await MainActor.run { logError(.daemon, "Activate failed: \(error)") }
            throw error
        }
    }

    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws {
        let request = DaemonRequest(
            command: "highlight",
            sessionID: sessionID,
            tab: tabConfig,
            pane: paneConfig
        )
        do {
            _ = try await withTimeout(highlightTimeout) {
                try await self.sendRequest(request)
            }
        } catch {
            // Silent fail for highlight - cosmetic only
            await MainActor.run { logDebug(.daemon, "Highlight failed (cosmetic): \(error)") }
        }
    }

    func resetHighlight(sessionID: String) async throws {
        let request = DaemonRequest(command: "reset", sessionID: sessionID)
        _ = try? await withTimeout(highlightTimeout) {
            try await self.sendRequest(request)
        }
    }

    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo? {
        await MainActor.run { logDebug(.daemon, "getSessionInfo: starting for \(sessionID)") }
        let request = DaemonRequest(command: "get_session_info", sessionID: sessionID)
        let response: DaemonResponse
        do {
            await MainActor.run { logDebug(.daemon, "getSessionInfo: calling sendRequest") }
            response = try await sendRequest(request)
            await MainActor.run { logDebug(.daemon, "getSessionInfo: sendRequest returned, status=\(response.status)") }
        } catch {
            if shouldAttemptRecovery(error) {
                await MainActor
                    .run { logWarning(.daemon, "Stale connection in getSessionInfo, attempting recovery...") }
                do {
                    try await restart()
                    response = try await sendRequest(request)
                } catch {
                    await MainActor.run { logWarning(.daemon, "Get session info failed after recovery: \(error)") }
                    return nil
                }
            } else {
                await MainActor.run { logWarning(.daemon, "Get session info failed: \(error)") }
                return nil
            }
        }

        guard response.status == "ok",
              let tabName = response.tabName,
              let windowName = response.windowName,
              let paneIndex = response.paneIndex,
              let paneCount = response.paneCount
        else {
            return nil
        }

        return TerminalSessionInfo(
            id: sessionID,
            tabName: tabName,
            windowName: windowName,
            windowIndex: 0,
            tabIndex: 0,
            paneIndex: paneIndex,
            paneCount: paneCount,
            isActive: false
        )
    }

    // MARK: - Timeout Helper

    private func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TerminalBridgeError.commandTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private nonisolated func sendRequest(_ request: DaemonRequest) async throws -> DaemonResponse {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw TerminalBridgeError.daemonNotRunning
        }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw TerminalBridgeError.connectionFailed
        }
        defer { close(sock) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            throw TerminalBridgeError.connectionFailed
        }

        let requestData = try JSONEncoder().encode(request)
        let requestString = String(decoding: requestData, as: UTF8.self) + "\n"

        _ = requestString.withCString { ptr in
            send(sock, ptr, strlen(ptr), 0)
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = recv(sock, &buffer, buffer.count, 0)
            if bytesRead <= 0 {
                break
            }
            responseData.append(contentsOf: buffer[0 ..< bytesRead])

            if let lastByte = responseData.last, lastByte == UInt8(ascii: "\n") {
                break
            }
        }

        guard !responseData.isEmpty else {
            throw TerminalBridgeError.invalidResponse
        }

        let response = try JSONDecoder().decode(DaemonResponse.self, from: responseData)

        if response.status == "error" {
            throw TerminalBridgeError.commandFailed(response.message ?? "Unknown error")
        }

        return response
    }
}

// MARK: - Daemon Protocol Types

private struct DaemonRequest: Sendable {
    let command: String
    var sessionID: String?
    var tab: HighlightConfig?
    var pane: HighlightConfig?

    enum CodingKeys: String, CodingKey {
        case command
        case sessionID = "session_id"
        case tab
        case pane
    }
}

extension DaemonRequest: Encodable {
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(tab, forKey: .tab)
        try container.encodeIfPresent(pane, forKey: .pane)
    }
}

private struct DaemonResponse: Sendable {
    let status: String
    var message: String?
    var sessionID: String?
    var tabName: String?
    var windowName: String?
    var paneIndex: Int?
    var paneCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case sessionID = "session_id"
        case tabName = "tab_name"
        case windowName = "window_name"
        case paneIndex = "pane_index"
        case paneCount = "pane_count"
    }
}

extension DaemonResponse: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        tabName = try container.decodeIfPresent(String.self, forKey: .tabName)
        windowName = try container.decodeIfPresent(String.self, forKey: .windowName)
        paneIndex = try container.decodeIfPresent(Int.self, forKey: .paneIndex)
        paneCount = try container.decodeIfPresent(Int.self, forKey: .paneCount)
    }
}

private struct DaemonEvent: Sendable {
    let event: String
    let sessionID: String?
    let tabName: String?
    let windowName: String?
    let paneIndex: Int?
    let paneCount: Int?

    enum CodingKeys: String, CodingKey {
        case event
        case sessionID = "session_id"
        case tabName = "tab_name"
        case windowName = "window_name"
        case paneIndex = "pane_index"
        case paneCount = "pane_count"
    }
}

extension DaemonEvent: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        tabName = try container.decodeIfPresent(String.self, forKey: .tabName)
        windowName = try container.decodeIfPresent(String.self, forKey: .windowName)
        paneIndex = try container.decodeIfPresent(Int.self, forKey: .paneIndex)
        paneCount = try container.decodeIfPresent(Int.self, forKey: .paneCount)
    }
}
