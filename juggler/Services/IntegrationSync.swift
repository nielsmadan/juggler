//
//  IntegrationSync.swift
//  Juggler
//

import Foundation

/// Keeps already-installed integrations in sync with the current app. Settings' green
/// "installed" check only proves something is registered, not that it's current — without this,
/// an upgrade leaves the user running a stale hook behind a green check.
enum IntegrationSync {
    /// Reinstall any installed integration that has drifted from what the current version
    /// writes. Best-effort: a failure for one integration is logged and never blocks the
    /// others or launch.
    static func run(client: HooklinesinkerClient = .shared) async {
        await syncAgentHooks(client: client)
        await syncKittyWatcher()
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

    /// `drifted` is the only state that earns a reinstall. `missing` means the user never
    /// installed this agent's hooks — installing them here would be uninvited — and
    /// `unsupported` means the config has a shape we must not rewrite behind their back.
    static func needsReinstall(state: HooklinesinkerState) -> Bool {
        state == .drifted
    }

    private static func syncAgentHooks(client: HooklinesinkerClient) async {
        for agent in HooklinesinkerAgent.allCases {
            await syncAgentHooks(agent, client: client)
        }
    }

    private static func syncAgentHooks(_ agent: HooklinesinkerAgent, client: HooklinesinkerClient) async {
        guard let status = try? await client.hookStatus(agent: agent) else { return }

        // Codex trust keys embed the group index, so a foreign hook coexisting on an event we
        // already hook can shift our index and silently un-trust us without any drift. Reconcile
        // trust when it is stale, even though the hooks themselves need no reinstall.
        if agent == .codex, status.state == .installed {
            await reconcileCodexTrust(status: status)
        }

        guard needsReinstall(state: status.state) else { return }
        await MainActor.run { logInfo(.hooks, "\(agent.displayName) hooks are out of date — reinstalling") }

        // Sample consent before reinstalling: the re-merge can shift group indices, which are
        // part of the trust key, so afterwards the old entries no longer resolve.
        let wasTrusted = agent == .codex && CodexHooksInstaller.hasExistingTrustEntries(
            hooksJSONPath: status.path, entries: status.entries
        )

        let result = await client.installHooks(agent: agent)
        guard result.isSuccess else {
            await MainActor.run {
                logWarning(.hooks, "Auto-reinstall of \(agent.displayName) hooks failed: \(result.failureMessage)")
            }
            return
        }
        await MainActor.run { logInfo(.hooks, "\(agent.displayName) hooks updated to the current version") }

        if agent == .codex {
            await retrustCodex(wasTrusted: wasTrusted, client: client)
        }
    }

    /// Re-trust an already-installed Codex whose group indices shifted under it. Only when the
    /// feature flag is on and the user had already trusted these hooks — never newly trusting on
    /// their behalf — and only when something is actually stale, so a fully-trusted install does
    /// no work.
    private static func reconcileCodexTrust(status: HooklinesinkerHookStatus) async {
        guard CodexHooksInstaller.isFeatureFlagEnabled(),
              CodexHooksInstaller.hasExistingTrustEntries(
                  hooksJSONPath: status.path, entries: status.entries
              ),
              !CodexHooksInstaller.allEntriesTrusted(
                  hooksJSONPath: status.path, entries: status.entries
              )
        else { return }
        do {
            try CodexHooksInstaller.enableInCodex(
                hooksJSONPath: status.path, entries: status.entries
            )
            await MainActor.run { logInfo(.hooks, "Codex trust re-reconciled after a group-index shift") }
        } catch {
            await MainActor.run { logWarning(.hooks, "Codex trust reconcile failed: \(error)") }
        }
    }

    /// The trust hash covers the event name, command and timeout — never the hook's bytes.
    /// Re-apply it because a newly registered event has no trust key yet, and because the
    /// re-merge can shift a group index (which is part of the key). Only when the hooks
    /// feature flag is on, so we never newly trust hooks for a partial or abandoned install.
    private static func retrustCodex(wasTrusted: Bool, client: HooklinesinkerClient) async {
        guard CodexHooksInstaller.isFeatureFlagEnabled() else {
            await MainActor.run {
                logInfo(.hooks, "Codex hooks refreshed (feature flag off — skipping re-trust)")
            }
            return
        }
        // Writing the first trust entry on the user's behalf would bypass the `/hooks` review
        // they chose. Refresh only what they already granted; the setup UI surfaces the rest.
        guard wasTrusted else {
            await MainActor.run {
                logInfo(.hooks, "Codex hooks re-registered — not previously trusted, leaving trust to the user")
            }
            return
        }
        guard let refreshed = try? await client.hookStatus(agent: .codex) else { return }
        do {
            try CodexHooksInstaller.enableFeatureFlag()
            try CodexHooksInstaller.enableInCodex(
                hooksJSONPath: refreshed.path, entries: refreshed.entries
            )
            await MainActor.run { logInfo(.hooks, "Codex hooks updated and re-trusted") }
        } catch {
            await MainActor.run { logWarning(.hooks, "Codex re-trust after update failed: \(error)") }
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
}
