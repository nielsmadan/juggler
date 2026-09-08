import Foundation
import SwiftUI

/// Backing state for the Codex setup flow — used by `CodexSetupView` (the onboarding sheet)
/// and the Codex section of `IntegrationSettingsView`. Each view holds its own instance:
/// the two surfaces have independent lifecycles and must not share state.
@MainActor
@Observable
final class CodexSetupController {
    var hooksInstalled = false
    var featureFlagEnabled = false
    var enabledInCodex = false
    var isInstallingHooks = false
    var isEnablingFlag = false
    var isEnablingInCodex = false
    var errorMessage: String?

    /// The canonical hooks.json path and per-event group indexes the CLI reports. Trust keys
    /// and hashes are derived from these rather than re-parsing hooks.json here, so the two
    /// implementations cannot disagree about what is registered.
    private var hooksJSONPath = CodexHooksInstaller.hooksJSONPath
    private var hookEntries: [HooklinesinkerHookEntry] = []

    private let client: HooklinesinkerClient

    init(client: HooklinesinkerClient = .shared) {
        self.client = client
    }

    var allComplete: Bool { hooksInstalled && featureFlagEnabled && enabledInCodex }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        do {
            let status = try await client.hookStatus(agent: .codex)
            if !status.path.isEmpty { hooksJSONPath = status.path }
            hookEntries = status.entries
            hooksInstalled = status.state == .installed
            if status.state == .unsupported {
                errorMessage = CodexHooksError.hooksUnsupported(hooksJSONPath).errorDescription
            }
        } catch {
            hookEntries = []
            hooksInstalled = false
            errorMessage = error.localizedDescription
        }
        featureFlagEnabled = CodexHooksInstaller.isFeatureFlagEnabled()
        enabledInCodex = CodexHooksInstaller.isEnabledInCodex(
            hooksJSONPath: hooksJSONPath, entries: hookEntries
        )
    }

    func initializePermissionEventPreference(
        defaults: UserDefaults = .standard,
        configTOMLPath: String = CodexHooksInstaller.configTOMLPath
    ) {
        guard defaults.object(forKey: AppStorageKeys.codexIgnorePermissionEvents) == nil,
              CodexHooksInstaller.isAutoReviewEnabled(at: configTOMLPath) else {
            return
        }
        defaults.set(true, forKey: AppStorageKeys.codexIgnorePermissionEvents)
    }

    func installHooks() {
        isInstallingHooks = true
        errorMessage = nil
        Task {
            if let failure = await CodexHooksInstaller.installHooks(client: client) {
                errorMessage = failure
            }
            await refreshAsync()
            isInstallingHooks = false
        }
    }

    func enableFlag() {
        isEnablingFlag = true
        errorMessage = nil
        Task {
            do {
                try CodexHooksInstaller.enableFeatureFlag()
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshAsync()
            isEnablingFlag = false
        }
    }

    func enableInCodex() {
        isEnablingInCodex = true
        errorMessage = nil
        Task {
            // Re-read the registration first: an install that ran since the last refresh can
            // have moved the group index the trust key is built from.
            await refreshAsync()
            do {
                try CodexHooksInstaller.enableInCodex(
                    hooksJSONPath: hooksJSONPath, entries: hookEntries
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshAsync()
            isEnablingInCodex = false
        }
    }
}
