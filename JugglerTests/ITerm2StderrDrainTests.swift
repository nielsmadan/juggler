import Foundation
@testable import Juggler
import Testing

/// Tests for `installStderrDrain`, the daemon-stderr reader. The load-bearing
/// contract is that the readability handler removes itself on EOF: without that,
/// GCD re-fires it forever on an empty read and pins a CPU core per dead daemon
/// (the 679%-CPU regression these tests guard against).
@Suite("ITerm2 stderr drain")
struct ITerm2StderrDrainTests {
    // MARK: - Regression: EOF teardown

    @Test func stderrDrain_capturesDataThenRemovesHandlerOnEOF() async throws {
        let pipe = Pipe()
        let buffer = StderrRingBuffer()
        let queue = DispatchQueue(label: "test.stderr.drain")
        installStderrDrain(on: pipe.fileHandleForReading, into: buffer, drainQueue: queue)

        // Normal path: bytes written to the pipe reach the buffer.
        try pipe.fileHandleForWriting.write(contentsOf: Data("boom\n".utf8))
        let captured = await waitUntil { buffer.snapshot().contains("boom") }
        #expect(captured, "drain did not capture data written before EOF")

        // Closing the write end signals EOF. The handler must remove itself rather
        // than busy-loop on repeated empty reads.
        try pipe.fileHandleForWriting.close()
        let toreDown = await waitUntil {
            pipe.fileHandleForReading.readabilityHandler == nil
        }
        #expect(toreDown, "readabilityHandler still installed after EOF — it will busy-loop on read()==0")
    }

    // MARK: - Performance guard: no CPU burn under EOF churn

    /// Drives many drain cycles that all immediately hit EOF, then measures the CPU
    /// this process consumes during a quiet window. Correct teardown leaves nothing
    /// running (~0 CPU); a handler that fails to remove itself on EOF leaves one
    /// thread per cycle spinning on `read()==0`, each burning a full core.
    @Test(.tags(.performance))
    func stderrDrain_idleAfterEOFChurn_consumesNoCPU() async throws {
        // Retain every pipe for the duration, mirroring production: the daemon's
        // Process holds its stderr pipe via terminationHandler, so a leaked reader
        // is NOT deallocated and keeps spinning. Without this retention the pipes
        // would ARC-dealloc between iterations and tear the source down anyway,
        // masking the very leak we guard against.
        var pipes: [Pipe] = []
        let queue = DispatchQueue(label: "test.stderr.churn")
        for _ in 0 ..< 80 {
            let pipe = Pipe()
            let buffer = StderrRingBuffer()
            installStderrDrain(on: pipe.fileHandleForReading, into: buffer, drainQueue: queue)
            try? pipe.fileHandleForWriting.write(contentsOf: Data("x".utf8))
            try? pipe.fileHandleForWriting.close() // EOF: handler must tear down
            pipes.append(pipe)
            try? await Task.sleep(nanoseconds: 3_000_000) // 3ms — pace fd creation
        }

        // Let teardown settle, then measure CPU used across a 1s idle window. One
        // spinning EOF handler burns ~1 core-second per idle second; 80 of them would
        // burn dozens. Correct teardown consumes ~0. The threshold leaves wide margin
        // for scheduler/test-runner noise. `pipes` stays retained through this window
        // because the cleanup loop below references it after the measurement.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let before = processCPUSeconds()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let consumed = processCPUSeconds() - before

        // Stop any leaked spinners before the process moves on to other tests. This
        // also keeps `pipes` alive across the measurement above (production retains
        // the reader via the daemon Process's terminationHandler).
        for pipe in pipes {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }

        #expect(
            consumed < 0.25,
            "burned \(String(format: "%.3f", consumed))s CPU while idle — a stderr handler is spin-looping on EOF"
        )
    }
}

// MARK: - Helpers

/// Polls `condition` until it is true or `timeout` elapses, yielding between checks.
/// Returns the final value of `condition`.
@discardableResult
private func waitUntil(timeout: TimeInterval = 2.0, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }
    return condition()
}

/// Total CPU time (user + system) this process has consumed, in seconds. Monotonic
/// and process-scoped, so a delta over an idle window measures only our own spinning.
private func processCPUSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return user + system
}
