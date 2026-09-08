import Foundation
@testable import Juggler
import Testing

@Suite("OpenCodePluginInstaller", .serialized)
struct OpenCodePluginInstallerTests {
    /// Runs `body` with `OPENCODE_CONFIG_DIR` set to a fresh temp dir, restoring the previous
    /// value afterward. The `.serialized` suite orders these tests relative to each other; the
    /// env restore in `defer` keeps the process-global mutation from leaking to other suites.
    private func withOpenCodeConfigDir(_ body: (URL) throws -> Void) rethrows {
        let previous = ProcessInfo.processInfo.environment["OPENCODE_CONFIG_DIR"]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("OPENCODE_CONFIG_DIR", dir.path, 1)
        defer {
            if let previous {
                setenv("OPENCODE_CONFIG_DIR", previous, 1)
            } else {
                unsetenv("OPENCODE_CONFIG_DIR")
            }
            try? FileManager.default.removeItem(at: dir)
        }
        try body(dir)
    }

    @Test func defaultPath_isUnderTheOpenCodeConfigDirectory() {
        let previous = ProcessInfo.processInfo.environment["OPENCODE_CONFIG_DIR"]
        unsetenv("OPENCODE_CONFIG_DIR")
        defer { if let previous { setenv("OPENCODE_CONFIG_DIR", previous, 1) } }

        #expect(OpenCodePluginInstaller.configDirectory == XDGPaths.configHome + "/opencode")
        #expect(OpenCodePluginInstaller.pluginFilePath
            == XDGPaths.configHome + "/opencode/plugins/hooklinesinker-opencode.ts")
    }

    @Test func honorsOpenCodeConfigDirOverride() {
        withOpenCodeConfigDir { dir in
            #expect(OpenCodePluginInstaller.configDirectory == dir.path)
            #expect(OpenCodePluginInstaller.pluginFilePath == dir.path + "/plugins/hooklinesinker-opencode.ts")
        }
    }

    @Test func install_delegatesToTheSharedInstaller() async throws {
        let stub = try HooklinesinkerStub.make()
        defer { stub.remove() }

        try await OpenCodePluginInstaller.install(client: stub.client)

        #expect(stub.recordedArguments == [["hooks", "install", "--agent", "opencode"]])
    }

    @Test func install_surfacesTheCLIsFailure() async throws {
        let stub = try HooklinesinkerStub.make(stderr: "plugins directory is read-only", status: 1)
        defer { stub.remove() }

        await #expect(throws: HooklinesinkerClientError.self) {
            try await OpenCodePluginInstaller.install(client: stub.client)
        }
    }
}
