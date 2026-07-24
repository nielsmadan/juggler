import Foundation
@testable import Juggler
import Testing

@Suite("IntegrationSync")
@MainActor
struct IntegrationSyncTests {
    // MARK: - contentsAreStale

    @Test func contentsAreStale_identicalContent_false() {
        let data = Data("same".utf8)
        #expect(IntegrationSync.contentsAreStale(installed: data, bundled: data) == false)
    }

    @Test func contentsAreStale_differentContent_true() {
        #expect(
            IntegrationSync.contentsAreStale(installed: Data("old".utf8), bundled: Data("new".utf8)) == true
        )
    }

    @Test func contentsAreStale_missingInstalled_false() {
        // Can't read the installed file → don't reinstall on a guess.
        #expect(IntegrationSync.contentsAreStale(installed: nil, bundled: Data("new".utf8)) == false)
    }

    @Test func contentsAreStale_missingBundled_false() {
        #expect(IntegrationSync.contentsAreStale(installed: Data("old".utf8), bundled: nil) == false)
    }

    // MARK: - isStale (file-existence guard)

    @Test func isStale_notInstalled_false() {
        // A path that doesn't exist means the integration was never installed — nothing to heal.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-nonexistent-\(UUID().uuidString).sh").path
        #expect(IntegrationSync.isStale(installedPath: missing, bundledResource: "notify", ext: "sh") == false)
    }
}
