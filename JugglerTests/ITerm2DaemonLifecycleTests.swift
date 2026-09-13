import Foundation
@testable import Juggler
import Testing

@Suite("ITerm2 daemon lifecycle", .timeLimit(.minutes(1)))
struct ITerm2DaemonLifecycleTests {
    @Test(arguments: [ITerm2DaemonLifecycle.Operation.start, .restart])
    func overlappingLaunchesShareOneOperation(operation: ITerm2DaemonLifecycle.Operation) async throws {
        let lifecycle = ITerm2DaemonLifecycle()
        let release = LifecycleSignal()
        let events = LifecycleEvents()
        var tasks: [Task<Void, Error>] = []
        for _ in 0 ..< 8 {
            let task = await lifecycle.enqueue(operation) {
                await events.append("launch")
                await release.wait()
            }
            tasks.append(task)
        }
        await release.signal()
        for task in tasks {
            try await task.value
        }
        #expect(await events.values == ["launch"])
    }

    @Test func stopCancelsPreparationBeforeALateLaunch() async throws {
        let lifecycle = ITerm2DaemonLifecycle()
        let entered = LifecycleSignal()
        let release = LifecycleSignal()
        let events = LifecycleEvents()
        let start = await lifecycle.enqueue(.start) {
            await events.append("preparing")
            await entered.signal()
            await release.wait()
            try Task.checkCancellation()
            await events.append("launched")
        }
        await entered.wait()
        let stop = await lifecycle.enqueue(.stop) { await events.append("stopped") }
        await release.signal()
        await #expect(throws: CancellationError.self) { try await start.value }
        try await stop.value
        #expect(await events.values == ["preparing", "stopped"])
    }

    @Test func startWaitsForAnInProgressStop() async throws {
        let lifecycle = ITerm2DaemonLifecycle()
        let entered = LifecycleSignal()
        let release = LifecycleSignal()
        let events = LifecycleEvents()
        let stop = await lifecycle.enqueue(.stop) {
            await events.append("stopping")
            await entered.signal()
            await release.wait()
            await events.append("stopped")
        }
        await entered.wait()
        let start = await lifecycle.enqueue(.start) { await events.append("launched") }
        await release.signal()
        try await stop.value
        try await start.value
        #expect(await events.values == ["stopping", "stopped", "launched"])
    }

    @Test func stopCancelsARestartQueuedBehindAnUpdate() async throws {
        let lifecycle = ITerm2DaemonLifecycle()
        let release = LifecycleSignal()
        let events = LifecycleEvents()
        let update = await lifecycle.enqueue(.update) { await release.wait() }
        let restart = await lifecycle.enqueue(.restart) { await events.append("launched") }
        let stop = await lifecycle.enqueue(.stop) { await events.append("stopped") }
        await release.signal()
        try await update.value
        await #expect(throws: CancellationError.self) { try await restart.value }
        try await stop.value
        #expect(await events.values == ["stopped"])
    }

    @Test func aFailedLaunchCanBeRetried() async throws {
        let lifecycle = ITerm2DaemonLifecycle()
        let events = LifecycleEvents()
        let failed = await lifecycle.enqueue(.start) { throw LaunchFailure() }
        await #expect(throws: LaunchFailure.self) { try await failed.value }
        let retry = await lifecycle.enqueue(.start) { await events.append("launched") }
        try await retry.value
        #expect(await events.values == ["launched"])
    }

    @Test func lateExitsCannotReportFailureForAReplacement() async {
        let lifecycle = ITerm2DaemonLifecycle()
        let old = Process()
        let replacement = Process()
        let events = LifecycleEvents()
        await lifecycle.trackProcess(old)
        await lifecycle.trackProcess(replacement)
        await lifecycle.exited(old) { await events.append("old failed") }
        await lifecycle.exited(replacement) { await events.append("current failed") }
        #expect(await events.values == ["current failed"])
    }

    @Test func stoppedProcessesCannotReportFailure() async {
        let lifecycle = ITerm2DaemonLifecycle()
        let process = Process()
        let events = LifecycleEvents()
        await lifecycle.trackProcess(process)
        await lifecycle.trackProcess(nil)
        await lifecycle.exited(process) { await events.append("failed") }
        await events.append("stopped")
        #expect(await events.values == ["stopped"])
    }

    private struct LaunchFailure: Error {}
}

private actor LifecycleSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        signaled = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

private actor LifecycleEvents {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}
