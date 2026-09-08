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
        ("integration_cleanup", "py"),
        ("antigravity-notify", "sh"), // AntigravityHooksInstaller.installHooks
        ("codex_config_cleanup", "py"), // uninstall.sh removes only Juggler trust entries
        ("iterm2_daemon", "py"), // iTerm2Bridge
        // Sibling resources copied by the install scripts above:
        ("juggler_watcher", "py") // install_kitty_watcher.sh copies it to kitty config
    ])
    func resourceIsBundled(resource: String, ext: String) {
        let url = Bundle.main.url(forResource: resource, withExtension: ext)
        let hint = "\(resource).\(ext) is missing from the app bundle. " +
            "Xcode 16's filesystem-synchronized group may be routing this extension to a non-resource " +
            "build phase (e.g. .ts → Compile Sources). Rename to an extension Xcode bundles as a resource."
        #expect(url != nil, Comment(rawValue: hint))
    }

    /// Only the hooks Juggler still ships itself. Claude, Codex, OpenCode and Pi delivery now
    /// lives in hooklinesinker, which pins its own timeouts.
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
