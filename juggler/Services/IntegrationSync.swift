//
//  IntegrationSync.swift
//  Juggler
//

import Foundation

/// Keeps already-installed integration scripts in sync with the ones bundled in the current app.
/// Settings' green "installed" check only proves the file exists, not that it's current — without
/// this, an upgrade leaves the user running a stale `notify.sh` behind a green check.
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

    /// Whether an installed Codex integration needs reinstalling. `scriptInstalled` is the
    /// decisive guard: without it a user who has their own hooks.json but never installed
    /// Juggler's hooks would score as drifted, and we'd install ourselves uninvited.
    static func codexNeedsReinstall(
        scriptInstalled: Bool,
        scriptStale: Bool,
        hasUnregisteredEvents: Bool
    ) -> Bool {
        guard scriptInstalled else { return false }
        return scriptStale || hasUnregisteredEvents
    }

    private static func syncCodex() {
        let scriptStale = isStale(
            installedPath: CodexHooksInstaller.notifyScriptPath,
            bundledResource: "codex-notify",
            ext: "sh"
        )
        guard codexNeedsReinstall(
            scriptInstalled: FileManager.default.fileExists(atPath: CodexHooksInstaller.notifyScriptPath),
            scriptStale: scriptStale,
            hasUnregisteredEvents: CodexHooksInstaller.hasUnregisteredEvents()
        ) else { return }
        // Sample consent before reinstalling: the re-merge can shift group indices, which are
        // part of the trust key, so afterwards the old entries no longer resolve.
        let wasTrusted = CodexHooksInstaller.hasExistingTrustEntries()
        logInfo(.hooks, "Codex hook is out of date — reinstalling")
        if let error = CodexHooksInstaller.installHooks() {
            logWarning(.hooks, "Auto-reinstall of Codex hook failed: \(error)")
            return
        }
        // The trust hash covers the event name, command and timeout — never the script's bytes.
        // Re-apply it because a newly registered event has no trust key yet, and because the
        // re-merge can shift a group index (which is part of the key). Only when the hooks
        // feature flag is on, so we never newly trust hooks for a partial or abandoned install.
        guard CodexHooksInstaller.isFeatureFlagEnabled() else {
            logInfo(.hooks, "Codex hook refreshed (feature flag off — skipping re-trust)")
            return
        }
        // Writing the first trust entry on the user's behalf would bypass the `/hooks` review
        // they chose. Refresh only what they already granted; the setup UI surfaces the rest.
        guard wasTrusted else {
            logInfo(.hooks, "Codex hooks re-registered — not previously trusted, leaving trust to the user")
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
