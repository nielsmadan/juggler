//
//  IntegrationSync.swift
//  Juggler
//

import Foundation

/// Keeps already-installed integration scripts in sync with the ones bundled in the current app.
///
/// The "installed" checkmark in Settings only checks that a hook/plugin file *exists*, not that
/// it's *current*. So when Juggler ships a changed `notify.sh` (e.g. adding a new terminal or
/// agent), a user who upgrades keeps running the old script on disk behind a green check, and the
/// new behavior silently never happens. On launch we compare each installed integration's script
/// against the bundled version and silently reinstall the ones that changed, so an upgrade can't
/// leave a user stranded on a stale hook.
enum IntegrationSync {
    /// Reinstall any installed integration whose on-disk script differs from the bundled one.
    /// Best-effort: a failure for one integration is logged and never blocks the others or launch.
    static func run() async {
        await syncClaudeCode()
        await syncKittyWatcher()
        syncCodex()
        syncOpenCode()
        syncPi()
    }

    /// Whether `installedPath` exists and differs byte-for-byte from the bundled resource.
    /// Returns false when the integration isn't installed (nothing to heal) or the bundled
    /// resource is missing.
    static func isStale(installedPath: String, bundledResource: String, ext: String) -> Bool {
        guard FileManager.default.fileExists(atPath: installedPath) else { return false }
        let bundled = Bundle.main.url(forResource: bundledResource, withExtension: ext)
            .flatMap { try? Data(contentsOf: $0) }
        let installed = try? Data(contentsOf: URL(fileURLWithPath: installedPath))
        return contentsAreStale(installed: installed, bundled: bundled)
    }

    /// Pure staleness comparison on already-loaded contents. A missing side (`nil`) means
    /// "can't tell" and is treated as not-stale, so a failed read never triggers a reinstall.
    static func contentsAreStale(installed: Data?, bundled: Data?) -> Bool {
        guard let installed, let bundled else { return false }
        return installed != bundled
    }

    private static func syncClaudeCode() async {
        guard isStale(installedPath: ScriptInstaller.claudeNotifyScriptPath, bundledResource: "notify", ext: "sh")
        else { return }
        logInfo(.hooks, "Claude Code hook is out of date — reinstalling")
        if let error = await ScriptInstaller.installHooks() {
            logWarning(.hooks, "Auto-reinstall of Claude Code hook failed: \(error)")
        } else {
            logInfo(.hooks, "Claude Code hook updated to the current version")
        }
    }

    private static func syncKittyWatcher() async {
        guard isStale(installedPath: ScriptInstaller.kittyWatcherPath, bundledResource: "juggler_watcher", ext: "py")
        else { return }
        logInfo(.kitty, "Kitty watcher is out of date — reinstalling")
        if let error = await ScriptInstaller.installKittyWatcher() {
            logWarning(.kitty, "Auto-reinstall of Kitty watcher failed: \(error)")
        } else {
            logInfo(.kitty, "Kitty watcher updated to the current version")
        }
    }

    private static func syncCodex() {
        guard isStale(installedPath: CodexHooksInstaller.notifyScriptPath, bundledResource: "codex-notify", ext: "sh")
        else { return }
        logInfo(.hooks, "Codex hook is out of date — reinstalling")
        if let error = CodexHooksInstaller.installHooks() {
            logWarning(.hooks, "Auto-reinstall of Codex hook failed: \(error)")
            return
        }
        // Codex trusts the hook by a content hash, so a changed script invalidates the old trust.
        // Re-apply it — but only when the hooks feature flag is on (the user completed Codex
        // setup), so we never newly trust hooks for a partial or abandoned install.
        guard CodexHooksInstaller.isFeatureFlagEnabled() else {
            logInfo(.hooks, "Codex hook refreshed (feature flag off — skipping re-trust)")
            return
        }
        do {
            try CodexHooksInstaller.enableFeatureFlag()
            try CodexHooksInstaller.enableInCodex()
            logInfo(.hooks, "Codex hook updated and re-trusted")
        } catch {
            logWarning(.hooks, "Codex re-trust after update failed: \(error)")
        }
    }

    private static func syncOpenCode() {
        guard isStale(
            installedPath: OpenCodePluginInstaller.pluginFilePath,
            bundledResource: "juggler-opencode",
            ext: "txt"
        ) else { return }
        logInfo(.hooks, "OpenCode plugin is out of date — reinstalling")
        do {
            try OpenCodePluginInstaller.install()
            logInfo(.hooks, "OpenCode plugin updated to the current version")
        } catch {
            logWarning(.hooks, "Auto-update of OpenCode plugin failed: \(error)")
        }
    }

    private static func syncPi() {
        guard isStale(
            installedPath: PiExtensionInstaller.extensionFilePath,
            bundledResource: "juggler-pi",
            ext: "txt"
        ) else { return }
        logInfo(.hooks, "Pi extension is out of date — reinstalling")
        do {
            try PiExtensionInstaller.install()
            logInfo(.hooks, "Pi extension updated to the current version")
        } catch {
            logWarning(.hooks, "Auto-update of Pi extension failed: \(error)")
        }
    }
}
