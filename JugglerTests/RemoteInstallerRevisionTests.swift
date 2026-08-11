import Foundation
import Testing

@Suite("Remote installer revision")
struct RemoteInstallerRevisionTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func embeddedRevisionsMatch() throws {
        let settings = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("juggler/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let installer = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("scripts/install-remote.sh"),
            encoding: .utf8
        )

        let settingsRevision = try #require(Self.revision(in: settings, after: "installRevision = \""))
        let installerRevision = try #require(Self.revision(in: installer, after: "JUGGLER_REVISION:-"))

        #expect(settingsRevision == installerRevision)
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
