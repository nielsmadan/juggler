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

    var allComplete: Bool { hooksInstalled && featureFlagEnabled && enabledInCodex }

    func refresh() {
        hooksInstalled = FileManager.default.fileExists(atPath: CodexHooksInstaller.notifyScriptPath)
        featureFlagEnabled = CodexHooksInstaller.isFeatureFlagEnabled()
        enabledInCodex = CodexHooksInstaller.isEnabledInCodex()
    }

    func installHooks() {
        isInstallingHooks = true
        errorMessage = nil
        Task {
            let result = CodexHooksInstaller.installHooks()
            if let result {
                errorMessage = result
            }
            refresh()
            isInstallingHooks = false
        }
    }

    func enableFlag() {
        isEnablingFlag = true
        errorMessage = nil
        do {
            try CodexHooksInstaller.enableFeatureFlag()
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        isEnablingFlag = false
    }

    func enableInCodex() {
        isEnablingInCodex = true
        errorMessage = nil
        do {
            try CodexHooksInstaller.enableInCodex()
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        isEnablingInCodex = false
    }
}
