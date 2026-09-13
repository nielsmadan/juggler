//
//  iTerm2Bridge.swift
//  Juggler
//

import AppKit
import Foundation
import SwiftUI

nonisolated enum DaemonState: Equatable {
    case stopped
    case starting
    case waitingForITerm2
    case ready
    case failed(reason: String)
}

@Observable
@MainActor
final class ITerm2DaemonStatus {
    static let shared = ITerm2DaemonStatus()

    var state: DaemonState = .stopped

    var lastStderrTail: String?

    private init() {}
}

// The lock protects stderr writes from the drain queue and reads from the bridge actor.
final nonisolated class StderrRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private var data = Data()
    private let lock = NSLock()

    init(capacity: Int = 64 * 1024) {
        self.capacity = capacity
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        if data.count > capacity {
            data.removeFirst(data.count - capacity)
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

// EOF remains readable; detach immediately to prevent a busy loop before the termination handler runs.
nonisolated func installStderrDrain(
    on fileHandle: FileHandle,
    into buffer: StderrRingBuffer,
    drainQueue: DispatchQueue
) {
    fileHandle.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            return
        }
        drainQueue.async { buffer.append(chunk) }
    }
}

actor ITerm2Bridge: TerminalBridge {
    static let shared = ITerm2Bridge()

    private let lifecycle = ITerm2DaemonLifecycle()
    private var daemonProcess: Process?
    private var stderrBuffer: StderrRingBuffer?
    private let socketPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Juggler")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(TestInstanceConfig.daemonSocketFilename()).path
    }()

    private nonisolated var pidFilePath: String { socketPath + ".pid" }

    private var eventReadSource: DispatchSourceRead?
    private var eventListenerID: UUID?
    private let eventQueue = DispatchQueue(label: "com.juggler.eventlistener")
    private let stderrQueue = DispatchQueue(label: "com.juggler.daemon.stderr")
    private var eventLineBuffer = Data()

    private var healthCheckTask: Task<Void, Never>?
    private var startupMonitorTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectID: UUID?

    // Waiting notifies once per app session; failures can notify again after a restart.
    private var hasNotifiedWaiting = false
    private var hasNotifiedFailed = false

    private var iterm2LaunchObserver: NSObjectProtocol?
    private var iterm2TerminateObserver: NSObjectProtocol?

    private let activateTimeout: TimeInterval = 2.0
    private let highlightTimeout: TimeInterval = 1.0
    private let initialReadinessWait: TimeInterval = 3.0
    private let extendedReadinessWait: TimeInterval = 60.0
    private let iterm2BundleID = "com.googlecode.iterm2"

    private init() {}

    func start() async throws {
        try await lifecycle.enqueue(.start) { try await self.startDaemon() }.value
    }

    private func startDaemon() async throws {
        guard daemonProcess == nil else { return }

        try Task.checkCancellation()
        await killOrphanedDaemon()
        try Task.checkCancellation()
        installLifecycleObservers()
        await setDaemonState(.starting)

        await MainActor.run { logInfo(.daemon, "Starting iTerm2 daemon...") }

        // Triggers Automation permission dialog on first run
        let cookieAndKey: String
        do {
            cookieAndKey = try await requestCookie()
        } catch {
            try Task.checkCancellation()
            await MainActor.run { logError(.daemon, "Failed to get iTerm2 cookie: \(error)") }
            await setDaemonState(.failed(reason: "Failed to get iTerm2 cookie: \(error)"))
            throw error
        }
        try Task.checkCancellation()
        let parts = cookieAndKey.split(separator: " ")
        let cookie = String(parts[0])
        let key = parts.count > 1 ? String(parts[1]) : ""

        let daemonPath = Bundle.main.path(forResource: "iterm2_daemon", ofType: "py")
        let python = resolveDaemonPython()

        guard let daemonPath else {
            await MainActor.run { logError(.daemon, "iterm2_daemon.py not found in bundle") }
            await setDaemonState(.failed(reason: "iterm2_daemon.py not found in bundle"))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [daemonPath, socketPath]

        var env = ProcessInfo.processInfo.environment
        env["ITERM2_COOKIE"] = cookie
        env["ITERM2_KEY"] = key
        process.environment = env

        // Install the drain before launch so retry diagnostics cannot fill the pipe and block the daemon.
        let stderrPipe = Pipe()
        let buffer = StderrRingBuffer()
        stderrBuffer = buffer
        installStderrDrain(on: stderrPipe.fileHandleForReading, into: buffer, drainQueue: stderrQueue)

        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] terminated in
            let trailing = stderrPipe.fileHandleForReading.availableData
            if !trailing.isEmpty {
                buffer.append(trailing)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let status = terminated.terminationStatus
            let stderrTail = buffer.snapshot()
            Task { [weak self] in
                await self?.handleDaemonExit(process: terminated, status: status, stderrTail: stderrTail)
            }
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stderrBuffer = nil
            await setDaemonState(.failed(reason: "Failed to launch daemon: \(error)"))
            throw error
        }
        daemonProcess = process
        await lifecycle.trackProcess(process)

        if try await waitForDaemonReady(process: process, deadline: Date().addingTimeInterval(initialReadinessWait)) {
            await finishStartupReady()
            return
        }
        try Task.checkCancellation()
        guard process.isRunning else { return }

        // Continue readiness checks in the background so start() returns after the initial wait.
        await transitionToWaiting()
        startupMonitorTask?.cancel()
        startupMonitorTask = Task { [weak self] in
            await self?.runStartupMonitor(process: process)
        }
    }

    /// iTerm2's bundled Python has the `iterm2` module pre-installed; prefer the newest
    /// such version over the system interpreter.
    private func resolveDaemonPython() -> String {
        let iterm2PythonBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iTerm2/iterm2env/versions")

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: iterm2PythonBase.path) {
            for version in contents.sorted().reversed() {
                let candidate = iterm2PythonBase
                    .appendingPathComponent(version)
                    .appendingPathComponent("bin/python3")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }
        return "/usr/bin/python3"
    }

    private func waitForDaemonReady(process: Process, deadline: Date) async throws -> Bool {
        while Date() < deadline {
            try Task.checkCancellation()
            if !process.isRunning {
                return false
            }
            let ready = await daemonPingSucceeds()
            try Task.checkCancellation()
            if ready, process.isRunning {
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000) // 250ms
        }
        return false
    }

    private func runStartupMonitor(process: Process) async {
        let deadline = Date().addingTimeInterval(extendedReadinessWait - initialReadinessWait)
        while Date() < deadline {
            if Task.isCancelled || daemonProcess !== process { return }
            if !process.isRunning {
                return
            }
            if await daemonPingSucceeds() {
                guard !Task.isCancelled else { return }
                try? await lifecycle.enqueue(.update) {
                    await self.finishStartupReady(process: process)
                }.value
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        }
        if Task.isCancelled { return }
        try? await lifecycle.enqueue(.update) {
            await self.handleStartupTimeout(process: process)
        }.value
    }

    private func handleStartupTimeout(process: Process) async {
        guard daemonProcess === process, process.isRunning else { return }
        let tail = stderrBuffer?.snapshot() ?? ""
        let reason = tail.isEmpty
            ? "iTerm2 didn't respond within \(Int(extendedReadinessWait))s"
            : "iTerm2 didn't respond within \(Int(extendedReadinessWait))s.\n\(tail.suffix(500))"
        await setDaemonState(.failed(reason: reason))
        await postFailedNotification(tail: tail)
    }

    private func finishStartupReady(process: Process) async {
        guard daemonProcess === process, process.isRunning else { return }
        await finishStartupReady()
    }

    private func finishStartupReady() async {
        await MainActor.run { logInfo(.daemon, "Daemon ready") }
        startEventListener()
        startHealthCheck()
        await setDaemonState(.ready)
    }

    private func transitionToWaiting() async {
        await setDaemonState(.waitingForITerm2)
        if !hasNotifiedWaiting {
            hasNotifiedWaiting = true
            await MainActor.run {
                NotificationManager.shared.sendSystemNotification(
                    title: "Waiting for iTerm2",
                    body: "Juggler is trying to connect. Make sure iTerm2 is running and the Python API is enabled."
                )
            }
        }
    }

    /// A full ping round-trip, not a socket-file existence check — the latter gives false
    /// positives for stale sockets and dead-but-just-started daemons.
    private nonisolated func daemonPingSucceeds() async -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
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
        guard connectResult == 0 else { return false }

        let request = "{\"command\": \"ping\"}\n"
        let sent = request.withCString { ptr in
            send(sock, ptr, strlen(ptr), 0)
        }
        guard sent > 0 else { return false }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = recv(sock, &buffer, buffer.count, 0)
            if n <= 0 { break }
            responseData.append(contentsOf: buffer[0 ..< n])
            if let last = responseData.last, last == UInt8(ascii: "\n") { break }
        }
        guard !responseData.isEmpty,
              let response = try? JSONDecoder().decode(DaemonResponse.self, from: responseData)
        else { return false }
        return response.status == "ok"
    }

    private func setDaemonState(_ newState: DaemonState) async {
        await MainActor.run {
            ITerm2DaemonStatus.shared.state = newState
        }
    }

    private func handleDaemonExit(process: Process, status: Int32, stderrTail: String) async {
        await lifecycle.exited(process) {
            await self.recordDaemonExit(status: status, stderrTail: stderrTail)
        }
    }

    private func recordDaemonExit(status: Int32, stderrTail: String) async {
        await MainActor.run {
            ITerm2DaemonStatus.shared.lastStderrTail = stderrTail
        }
        await MainActor.run { logWarning(.daemon, "Daemon exited (status \(status)). stderr tail: \(stderrTail)") }
        let currentState = await MainActor.run { ITerm2DaemonStatus.shared.state }
        switch currentState {
        case .ready, .starting, .waitingForITerm2:
            let reason = stderrTail.isEmpty
                ? "Daemon exited (status \(status))"
                : "Daemon exited (status \(status)).\n\(stderrTail.suffix(500))"
            await setDaemonState(.failed(reason: reason))
            await postFailedNotification(tail: stderrTail)
        case .failed, .stopped:
            break
        }
    }

    private func postFailedNotification(tail: String) async {
        guard !hasNotifiedFailed else { return }
        hasNotifiedFailed = true
        await MainActor.run {
            let body: String
            if tail.isEmpty {
                body = "Open iTerm2 and ensure the Python API is enabled (Settings → General → Magic)."
            } else {
                let truncated = tail.suffix(300)
                body = "iTerm2 isn't responding. \(truncated)"
            }
            NotificationManager.shared.sendSystemNotification(
                title: "iTerm2 integration unavailable",
                body: body
            )
        }
    }

    // MARK: - iTerm2 Lifecycle Observation

    /// Register for NSWorkspace iTerm2 launch/quit notifications. Idempotent.
    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let bundleID = iterm2BundleID

        if iterm2LaunchObserver == nil {
            iterm2LaunchObserver = center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == bundleID else { return }
                Task { await self?.handleITerm2Launched() }
            }
        }

        if iterm2TerminateObserver == nil {
            iterm2TerminateObserver = center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == bundleID else { return }
                Task { await self?.handleITerm2Terminated() }
            }
        }
    }

    private func removeLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if let observer = iterm2LaunchObserver {
            center.removeObserver(observer)
            iterm2LaunchObserver = nil
        }
        if let observer = iterm2TerminateObserver {
            center.removeObserver(observer)
            iterm2TerminateObserver = nil
        }
    }

    private func handleITerm2Launched() async {
        let currentState = await MainActor.run { ITerm2DaemonStatus.shared.state }
        switch currentState {
        case .waitingForITerm2, .failed, .stopped:
            await MainActor.run { logInfo(.daemon, "iTerm2 launched — restarting daemon") }
            try? await restart()
        case .starting, .ready:
            break
        }
    }

    private func handleITerm2Terminated() async {
        let currentState = await MainActor.run { ITerm2DaemonStatus.shared.state }
        if currentState == .ready {
            await MainActor.run { logInfo(.daemon, "iTerm2 terminated — entering waitingForITerm2") }
            // Update the status bar immediately while the daemon handles its lost iTerm2 connection.
            await setDaemonState(.waitingForITerm2)
        }
    }

    // MARK: - Event Listener (DispatchSource-based, non-blocking)

    private func startEventListener() {
        guard eventListenerID == nil, daemonProcess != nil else { return }
        let listenerID = UUID()
        eventListenerID = listenerID
        eventQueue.async { [self] in
            do {
                let sock = try connectEventSocket()

                let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: eventQueue)

                source.setEventHandler { [self] in
                    handleSocketData(socket: sock, listenerID: listenerID)
                }

                source.setCancelHandler {
                    close(sock)
                    Task { @MainActor in
                        logInfo(.daemon, "Focus event listener disconnected")
                    }
                }

                Task { await self.setEventReadSource(source, listenerID: listenerID) }
                source.resume()

                Task { @MainActor in
                    logInfo(.daemon, "Focus event listener connected")
                }
            } catch {
                Task { await self.cancelEventListener(listenerID: listenerID) }
                Task { @MainActor in
                    logWarning(.daemon, "Event listener failed to connect: \(error)")
                }
            }
        }
    }

    private func setEventReadSource(_ source: DispatchSourceRead, listenerID: UUID) {
        guard eventListenerID == listenerID else {
            source.cancel()
            return
        }
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

    private nonisolated func handleSocketData(socket sock: Int32, listenerID: UUID) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(sock, &buffer, buffer.count, Int32(MSG_DONTWAIT))

        if bytesRead == 0 {
            Task { await self.cancelEventListener(listenerID: listenerID) }
            return
        }
        if bytesRead < 0 {
            // EAGAIN/EWOULDBLOCK = no data available (normal for non-blocking recv)
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            Task { await self.cancelEventListener(listenerID: listenerID) }
            return
        }

        Task { await self.processReceivedData(Data(buffer[0 ..< bytesRead]), listenerID: listenerID) }
    }

    private func cancelEventListener(listenerID: UUID) {
        guard eventListenerID == listenerID else { return }
        eventListenerID = nil
        eventReadSource?.cancel()
        eventReadSource = nil
        if daemonProcess != nil {
            scheduleEventListenerReconnect()
        }
    }

    private func scheduleEventListenerReconnect() {
        guard reconnectTask == nil else { return }
        let id = UUID()
        reconnectID = id
        reconnectTask = Task {
            defer {
                if reconnectID == id {
                    reconnectTask = nil
                    reconnectID = nil
                }
            }
            await MainActor.run { logWarning(.daemon, "Event listener disconnected, attempting reconnect...") }
            for delay in [2.0, 5.0, 10.0, 15.0] {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch { return }
                guard daemonProcess != nil else { return }
                guard eventReadSource == nil else { return } // already reconnected

                guard FileManager.default.fileExists(atPath: socketPath) else { continue }

                await MainActor.run { logInfo(.daemon, "Reconnecting event listener...") }
                startEventListener()
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch { return }
                if eventReadSource != nil {
                    await MainActor.run { logInfo(.daemon, "Event listener reconnected") }
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { logWarning(.daemon, "Event listener reconnect failed, restarting daemon...") }
            try? await restart()
        }
    }

    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                } catch { return }
                guard daemonProcess != nil else { continue }

                let request = DaemonRequest(command: "ping")
                do {
                    _ = try await sendRequest(request)
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { logWarning(.daemon, "Health check failed: \(error)") }
                    if eventReadSource == nil {
                        scheduleEventListenerReconnect()
                    }
                }
            }
        }
    }

    private func processReceivedData(_ data: Data, listenerID: UUID) async {
        guard eventListenerID == listenerID else { return }
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
        try? await lifecycle.enqueue(.stop) { await self.stopDaemon() }.value
    }

    private func stopDaemon() async {
        // Clear daemon process first so cancelEventListener doesn't trigger reconnect
        let process = daemonProcess
        daemonProcess = nil
        await lifecycle.trackProcess(nil)
        startupMonitorTask?.cancel()
        startupMonitorTask = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectID = nil
        eventReadSource?.cancel()
        eventReadSource = nil
        eventListenerID = nil
        eventLineBuffer.removeAll()
        // Intentional shutdown must not report a daemon failure.
        process?.terminationHandler = nil
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
        stderrBuffer = nil
        removeLifecycleObservers()
        await setDaemonState(.stopped)
        await MainActor.run { logInfo(.daemon, "Daemon stopped") }
    }

    private func killOrphanedDaemon() async {
        guard let pidString = try? String(contentsOfFile: pidFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(pidString), pid > 0
        else { return }

        guard kill(pid, 0) == 0 else { return }

        // The shared PID may belong to another live build or have been reused by an unrelated process.
        guard isOrphanedDaemon(pid: pid) else { return }

        kill(pid, SIGTERM)
        for _ in 0 ..< 10 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if kill(pid, 0) != 0 { break }
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    // KERN_PROCARGS2 includes the environment, so match both the script name and socket path.
    private nonisolated func isOrphanedDaemon(pid: Int32) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return false }
        guard info.kp_eproc.e_ppid == 1 else { return false }

        var argsMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var argsSize = 0
        guard sysctl(&argsMib, 3, nil, &argsSize, nil, 0) == 0, argsSize > 0 else { return false }
        var argsBuf = [UInt8](repeating: 0, count: argsSize)
        guard sysctl(&argsMib, 3, &argsBuf, &argsSize, nil, 0) == 0 else { return false }
        let args = Data(argsBuf)
        return args.range(of: Data("iterm2_daemon.py".utf8)) != nil
            && args.range(of: Data(socketPath.utf8)) != nil
    }

    // MARK: - Connection Recovery

    func shouldAttemptRecovery(_ error: Error) -> Bool {
        if let bridgeError = error as? TerminalBridgeError {
            switch bridgeError {
            case .daemonNotRunning, .connectionFailed, .connectionTimeout,
                 .commandTimeout, .invalidResponse:
                return true
            case .commandFailed, .authenticationFailed, .sessionNotFound, .bridgeNotAvailable:
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
        try await lifecycle.enqueue(.restart) { try await self.restartDaemon() }.value
    }

    private func restartDaemon() async throws {
        await MainActor.run { logWarning(.daemon, "Restarting daemon...") }
        await stopDaemon()
        hasNotifiedFailed = false
        try await Task.sleep(nanoseconds: 500_000_000)
        try await startDaemon()
    }

    @MainActor
    private func handleDaemonEvent(_ event: DaemonEvent) {
        switch event.event {
        case "focus_changed":
            logDebug(.daemon, "Focus changed to: \(event.sessionID ?? "nil")")
            // FocusMonitor reports a bare UUID; hooks supply `w1t0p0:UUID` — match with hasSuffix, never ==.
            SessionManager.shared.updateFocusedSession(terminalSessionID: event.sessionID, focusTerminalType: .iterm2)
        case "session_terminated":
            guard let sessionID = event.sessionID else { return }
            logInfo(.daemon, "Session terminated in iTerm2: \(sessionID)")
            SessionManager.shared.removeSessionsByTerminalID(sessionID)
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

    private func requestCookie() async throws -> String {
        let script = """
        tell application "iTerm2" to request cookie and key for app named "Juggler"
        """

        return try await MainActor.run {
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

            let parts = cookieAndKey.split(separator: " ")
            guard parts.count >= 1 else {
                throw TerminalBridgeError.authenticationFailed("Invalid cookie format")
            }

            return cookieAndKey
        }
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
                    await MainActor.run { logInfo(.daemon, "Session activated after recovery: \(sessionID)") }
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

    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo? {
        await MainActor.run { logDebug(.daemon, "getSessionInfo: starting for \(sessionID)") }
        let request = DaemonRequest(command: "get_session_info", sessionID: sessionID)
        let response: DaemonResponse
        do {
            await MainActor.run { logDebug(.daemon, "getSessionInfo: calling sendRequest") }
            response = try await sendRequest(request)
            await MainActor.run { logDebug(.daemon, "getSessionInfo: sendRequest returned, status=\(response.status)") }
        } catch let error as TerminalBridgeError {
            if shouldAttemptRecovery(error) {
                await MainActor
                    .run { logWarning(.daemon, "Stale connection in getSessionInfo, attempting recovery...") }
                try await restart()
                response = try await sendRequest(request)
            } else if case let .commandFailed(message) = error,
                      message.localizedCaseInsensitiveContains("session not found") {
                return nil
            } else {
                await MainActor.run { logWarning(.daemon, "Get session info failed: \(error)") }
                throw error
            }
        }

        guard response.status == "ok",
              let tabName = response.tabName,
              let windowName = response.windowName,
              let paneIndex = response.paneIndex,
              let paneCount = response.paneCount
        else {
            throw TerminalBridgeError.invalidResponse
        }

        return TerminalSessionInfo(
            id: sessionID,
            tabName: tabName,
            windowName: windowName,
            tabIndex: 0,
            paneIndex: paneIndex,
            paneCount: paneCount,
            isActive: false
        )
    }

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
        let requestString = (String(bytes: requestData, encoding: .utf8) ?? "") + "\n"

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

struct DaemonRequest: Sendable {
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

struct DaemonResponse: Sendable {
    let status: String
    var message: String?
    var tabName: String?
    var windowName: String?
    var paneIndex: Int?
    var paneCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case message
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
        tabName = try container.decodeIfPresent(String.self, forKey: .tabName)
        windowName = try container.decodeIfPresent(String.self, forKey: .windowName)
        paneIndex = try container.decodeIfPresent(Int.self, forKey: .paneIndex)
        paneCount = try container.decodeIfPresent(Int.self, forKey: .paneCount)
    }
}

struct DaemonEvent: Sendable {
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
