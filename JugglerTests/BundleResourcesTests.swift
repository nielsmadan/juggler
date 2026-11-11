import Foundation
import Testing

@Suite("Bundle resources")
struct BundleResourcesTests {
    @Test
    func hooklinesinkerIsEmbeddedAsAnExecutable() throws {
        let executable = try #require(Bundle.main.url(forAuxiliaryExecutable: "hooklinesinker"))
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
    }

    @Test(arguments: [
        // Looked up directly via Bundle.main in Swift:
        ("install_kitty_watcher", "sh"), // ScriptInstaller.installKittyWatcher
        ("uninstall", "sh"), // SettingsView reset / ScriptInstaller
        ("antigravity-notify", "sh"), // AntigravityHooksInstaller.installHooks
        ("iterm2_daemon", "py"), // iTerm2Bridge
        ("juggler_watcher", "py"), // IntegrationSync staleness check; install_kitty_watcher.sh copies it
        // Sibling resources used only by the bundled scripts above:
        ("integration_cleanup", "py"), // run by uninstall.sh
        ("codex_config_cleanup", "py") // imported by integration_cleanup.py
    ])
    func resourceIsBundled(resource: String, ext: String) {
        let url = Bundle.main.url(forResource: resource, withExtension: ext)
        let hint = "\(resource).\(ext) is missing from the app bundle. " +
            "Xcode 16's filesystem-synchronized group may be routing this extension to a non-resource " +
            "build phase (e.g. .ts → Compile Sources). Rename to an extension Xcode bundles as a resource."
        #expect(url != nil, Comment(rawValue: hint))
    }

    /// Hook delivery Juggler ships itself; hooklinesinker pins its own timeouts.
    @Test(arguments: [
        ("antigravity-notify", "sh", "--max-time 2 \\"),
        ("juggler_watcher", "py", "\"--max-time\", \"2\",")
    ])
    func hookDeliveryHasTotalTimeout(resource: String, ext: String, timeoutLine: String) throws {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: ext))
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(lines.contains(timeoutLine))
    }
}
