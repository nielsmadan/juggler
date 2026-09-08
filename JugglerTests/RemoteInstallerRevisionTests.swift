import Foundation
@testable import Juggler
import Testing

@Suite("Remote installer revision")
struct RemoteInstallerRevisionTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func installerScript() throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-remote.sh"),
            encoding: .utf8
        )
    }

    @Test func embeddedRevisionsMatch() throws {
        let settings = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("juggler/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let installer = try Self.installerScript()

        let settingsRevision = try #require(Self.revision(in: settings, after: "installRevision = \""))
        let installerRevision = try #require(Self.revision(in: installer, after: "JUGGLER_REVISION:-"))

        #expect(settingsRevision == installerRevision)
    }

    /// The one-liner and the script live in different files and are edited for different
    /// reasons. This pins that every knob the one-liner sets is one the script actually
    /// reads — the check that would have caught `JUGGLER_BASE_URL` outliving the script
    /// that consumed it.
    @Test func everyEnvVarTheOneLinerSetsIsReadByTheScript() throws {
        let installer = try Self.installerScript()
        let oneLiner = RemoteSetupSnippets.installOneLiner(
            revision: String(repeating: "a", count: 40),
            sink: "http://127.0.0.1:7483/hook"
        )

        let assigned = Self.envAssignments(in: oneLiner)
        #expect(!assigned.isEmpty)
        for name in assigned {
            #expect(
                installer.contains("${\(name):-") || installer.contains("${\(name)}")
                    || installer.contains("\"$\(name)\""),
                Comment(rawValue: "install-remote.sh never reads $\(name), but the one-liner sets it")
            )
        }
    }

    @Test func theOneLinerPointsTheRemoteAtThisJugglersSink() {
        let sink = HooklinesinkerClient.shared.sinkURL
        let oneLiner = RemoteSetupSnippets.installOneLiner(revision: "abc", sink: sink)

        #expect(oneLiner.contains("JUGGLER_SINK=\(sink)"))
        #expect(oneLiner.hasSuffix(" bash"))
        #expect(oneLiner.contains("/juggler/abc/scripts/install-remote.sh"))
    }

    /// The tunnel has to forward the port Juggler actually listens on, or the sink the
    /// one-liner hands the remote resolves to a closed port back on this machine.
    @Test(arguments: [UInt16(7483), UInt16(7900)])
    func theTunnelForwardsThePortTheSinkNames(port: UInt16) {
        let snippet = RemoteSetupSnippets.sshConfig(marker: "# marker", port: port)
        let oneLiner = RemoteSetupSnippets.installOneLiner(
            revision: "abc",
            sink: "http://127.0.0.1:\(port)/hook"
        )

        #expect(snippet.contains("RemoteForward \(port) localhost:\(port)"))
        #expect(snippet.hasPrefix("# marker\n"))
        #expect(oneLiner.contains(":\(port)/hook"))
    }

    /// `NAME=value` pairs sitting between the pipe and `bash` — the env the script inherits.
    private static func envAssignments(in oneLiner: String) -> [String] {
        guard let pipe = oneLiner.range(of: "| ") else { return [] }
        return oneLiner[pipe.upperBound...]
            .split(separator: " ")
            .compactMap { token in
                guard let equals = token.firstIndex(of: "=") else { return nil }
                let name = String(token[..<equals])
                let valid = !name.isEmpty
                    && name.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
                return valid ? name : nil
            }
    }

    private static func revision(in contents: String, after marker: String) -> String? {
        guard let markerRange = contents.range(of: marker) else { return nil }
        let revision = contents[markerRange.upperBound...].prefix(40)
        guard revision.count == 40, revision.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            return nil
        }
        return String(revision)
    }
}
