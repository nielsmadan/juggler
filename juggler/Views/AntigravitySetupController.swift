import Foundation
import SwiftUI

/// Backing state for the Antigravity setup flow — used by `AntigravitySetupView` (the
/// onboarding sheet) and the Antigravity section of `IntegrationSettingsView`. Each view
/// holds its own instance: the two surfaces have independent lifecycles and must not share
/// state. Simpler than Codex — Antigravity has no feature flag or trust step, so installing
/// the hooks is the only action.
@MainActor
@Observable
final class AntigravitySetupController {
    var hooksInstalled = false
    var isInstallingHooks = false
    var errorMessage: String?

    var allComplete: Bool { hooksInstalled }

    func refresh() {
        hooksInstalled = FileManager.default.fileExists(atPath: AntigravityHooksInstaller.notifyScriptPath)
            && AntigravityHooksInstaller.areHooksRegistered()
    }

    func installHooks() {
        isInstallingHooks = true
        errorMessage = nil
        Task {
            let result = AntigravityHooksInstaller.installHooks()
            if let result {
                errorMessage = result
            }
            refresh()
            isInstallingHooks = false
        }
    }
}
