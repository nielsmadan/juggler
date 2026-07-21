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

    // Default (no override) resolves under ~/.pi/agent/extensions/juggler-pi.ts.
    @Test func defaultPath_isUnderPiAgentExtensions() {
        let previous = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        unsetenv("PI_CODING_AGENT_DIR")
        defer { if let previous { setenv("PI_CODING_AGENT_DIR", previous, 1) } }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PiExtensionInstaller.agentDirectory == home + "/.pi/agent")
        #expect(PiExtensionInstaller.extensionsDirectory == home + "/.pi/agent/extensions")
        #expect(PiExtensionInstaller.extensionFilePath == home + "/.pi/agent/extensions/juggler-pi.ts")
    }

    // PI_CODING_AGENT_DIR overrides the config root.
    @Test func honorsPiCodingAgentDirOverride() {
        withPiAgentDir { dir in
            #expect(PiExtensionInstaller.agentDirectory == dir.path)
            #expect(PiExtensionInstaller.extensionFilePath == dir.path + "/extensions/juggler-pi.ts")
        }
    }

    // install() writes the bundled extension as .ts and its contents match the bundle.
    @Test func install_writesExtensionMatchingBundle() throws {
        try withPiAgentDir { _ in
            try PiExtensionInstaller.install()

            let installedPath = PiExtensionInstaller.extensionFilePath
            #expect(installedPath.hasSuffix("/extensions/juggler-pi.ts"))
            #expect(FileManager.default.fileExists(atPath: installedPath))

            let bundled = Bundle.main.url(forResource: "juggler-pi", withExtension: "txt")!
            let expected = try String(contentsOf: bundled, encoding: .utf8)
            let actual = try String(contentsOfFile: installedPath, encoding: .utf8)
            #expect(actual == expected)
        }
    }

    // install() is idempotent — a second run overwrites cleanly.
    @Test func install_isIdempotent() throws {
        try withPiAgentDir { _ in
            try PiExtensionInstaller.install()
            try PiExtensionInstaller.install()
            #expect(FileManager.default.fileExists(atPath: PiExtensionInstaller.extensionFilePath))
        }
    }
}
