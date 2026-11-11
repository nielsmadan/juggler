import SwiftUI

/// Backing state for the Kitty setup flow, used by `KittySetupView` and the Kitty section of
/// `IntegrationSettingsView`. Each view holds its own instance.
@MainActor
@Observable
final class KittySetupController {
    private(set) var status = KittyConfigParser.Status()
    private(set) var isInstallingWatcher = false
    private(set) var configError: String?
    private(set) var watcherError: String?

    var canTestConnection: Bool {
        Self.canTestConnection(status)
    }

    static func canTestConnection(_ status: KittyConfigParser.Status) -> Bool {
        status.remoteControlEnabled && status.listenOnConfigured && status.watcherInstalled
    }

    func refresh() {
        status = KittyConfigParser.status()
    }

    func append(_ directive: String) {
        configError = KittyConfigParser.appendToConf(directive)
        announce(configError)
        refresh()
    }

    func installWatcher() async {
        isInstallingWatcher = true
        watcherError = await ScriptInstaller.installKittyWatcher()
        announce(watcherError)
        refresh()
        isInstallingWatcher = false
    }

    private func announce(_ message: String?) {
        if let message {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
