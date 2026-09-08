import Foundation
@testable import Juggler
import Testing

@Suite("PiExtensionInstaller", .serialized)
struct PiExtensionInstallerTests {
    /// Runs `body` with `PI_CODING_AGENT_DIR` set to a fresh temp dir, restoring the
    /// previous value afterward. The `.serialized` suite orders these tests relative to
    /// each other; the env restore in `defer` keeps the process-global mutation from
    /// leaking to other suites. No other suite reads this var.
    private func withPiAgentDir(_ body: (URL) throws -> Void) rethrows {
        let previous = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("PI_CODING_AGENT_DIR", dir.path, 1)
        defer {
            if let previous {
                setenv("PI_CODING_AGENT_DIR", previous, 1)
            } else {
                unsetenv("PI_CODING_AGENT_DIR")
            }
            try? FileManager.default.removeItem(at: dir)
        }
        try body(dir)
    }

    @Test func defaultPath_isUnderPiAgentExtensions() {
        let previous = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        unsetenv("PI_CODING_AGENT_DIR")
        defer { if let previous { setenv("PI_CODING_AGENT_DIR", previous, 1) } }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PiExtensionInstaller.agentDirectory == home + "/.pi/agent")
        #expect(PiExtensionInstaller.extensionsDirectory == home + "/.pi/agent/extensions")
        #expect(PiExtensionInstaller.extensionFilePath == home + "/.pi/agent/extensions/hooklinesinker-pi.ts")
    }

    @Test func honorsPiCodingAgentDirOverride() {
        withPiAgentDir { dir in
            #expect(PiExtensionInstaller.agentDirectory == dir.path)
            #expect(PiExtensionInstaller.extensionFilePath == dir.path + "/extensions/hooklinesinker-pi.ts")
        }
    }

    @Test func install_delegatesToTheSharedInstaller() async throws {
        let stub = try HooklinesinkerStub.make()
        defer { stub.remove() }

        try await PiExtensionInstaller.install(client: stub.client)

        #expect(stub.recordedArguments == [["hooks", "install", "--agent", "pi"]])
    }

    @Test func install_surfacesTheCLIsFailure() async throws {
        let stub = try HooklinesinkerStub.make(stderr: "extensions directory is read-only", status: 1)
        defer { stub.remove() }

        await #expect(throws: HooklinesinkerClientError.self) {
            try await PiExtensionInstaller.install(client: stub.client)
        }
    }
}
