import Foundation
@testable import Juggler
import Testing

/// Probes `Bundle.main` for every resource the app ships. Catches Xcode-bundling
/// regressions like the `juggler-opencode.ts` bug, where Xcode 16's filesystem-
/// synchronized root group routed `.ts` to "Compile Sources" instead of the
/// resources bundle, so `Bundle.main.url(forResource:withExtension:)` returned
/// nil at runtime.
@Suite("Bundle resources")
struct BundleResourcesTests {
    @Test(arguments: [
        // Looked up directly via Bundle.main in Swift:
        ("install", "sh"), // ScriptInstaller.installHooks
        ("install_kitty_watcher", "sh"), // ScriptInstaller.installKittyWatcher
        ("uninstall", "sh"), // SettingsView reset / ScriptInstaller
        ("codex-notify", "sh"), // CodexHooksInstaller.installHooks
        ("antigravity-notify", "sh"), // AntigravityHooksInstaller.installHooks
        ("codex_config_cleanup", "py"), // uninstall.sh removes only Juggler trust entries
        ("juggler-opencode", "txt"), // OpenCodePluginInstaller.install
        ("juggler-pi", "txt"), // PiExtensionInstaller.install
        ("iterm2_daemon", "py"), // iTerm2Bridge
        // Sibling resources copied by the install scripts above:
        ("notify", "sh"), // install.sh copies it to ~/.claude/hooks/juggler/
        ("juggler_watcher", "py") // install_kitty_watcher.sh copies it to kitty config
    ])
    func resourceIsBundled(resource: String, ext: String) {
        let url = Bundle.main.url(forResource: resource, withExtension: ext)
        let hint = "\(resource).\(ext) is missing from the app bundle. " +
            "Xcode 16's filesystem-synchronized group may be routing this extension to a non-resource " +
            "build phase (e.g. .ts → Compile Sources). Rename to an extension Xcode bundles as a resource."
        #expect(url != nil, Comment(rawValue: hint))
    }

    @Test(arguments: [
        ("notify", "sh", "--max-time 2 \\"),
        ("codex-notify", "sh", "--max-time 2 \\"),
        ("antigravity-notify", "sh", "--max-time 2 \\"),
        ("juggler_watcher", "py", "\"--max-time\", \"2\","),
        ("juggler-opencode", "txt", "signal: AbortSignal.timeout(2000),"),
        ("juggler-pi", "txt", "signal: AbortSignal.timeout(2000),")
    ])
    func hookDeliveryHasTotalTimeout(resource: String, ext: String, timeoutLine: String) throws {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: ext))
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(lines.contains(timeoutLine))
    }
}
