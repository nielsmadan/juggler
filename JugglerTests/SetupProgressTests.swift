import CoreGraphics
@testable import Juggler
import Testing

@Suite("Setup progress")
@MainActor
struct SetupProgressTests {
    private func progress(_ configure: (IntegrationSetupProgress) -> Void) -> IntegrationSetupProgress {
        let progress = IntegrationSetupProgress()
        configure(progress)
        return progress
    }

    @Test func integrationSetupNeedsATerminalAndAnAgent() {
        #expect([
            progress { $0.iterm2 = true; $0.claudeCode = true }.isComplete,
            progress { $0.kitty = true; $0.hookAgents = [.claude] }.isComplete,
            progress { $0.iterm2 = true }.isComplete,
            progress { $0.codex = true }.isComplete
        ] == [true, true, false, false])
    }

    @Test func kittyConnectionTestNeedsAllThreeSteps() {
        let ready = KittyConfigParser.Status(
            remoteControlEnabled: true,
            listenOnConfigured: true,
            watcherInstalled: true
        )
        let noWatcher = KittyConfigParser.Status(
            remoteControlEnabled: true,
            listenOnConfigured: true,
            watcherInstalled: false
        )
        #expect(KittySetupController.canTestConnection(ready))
        #expect(KittySetupController.canTestConnection(noWatcher) == false)
    }

    @Test func settingsOpenAtContentHeightWhenItFits() {
        #expect(SettingsLayout.initialContentHeight(fitting: 500, screenVisibleHeight: 900) == 500)
    }

    @Test func settingsHeightIsCappedForTallContent() {
        #expect(SettingsLayout.initialContentHeight(fitting: 1318, screenVisibleHeight: 1400) == 760)
    }

    @Test func settingsHeightFitsAShortScreen() {
        #expect(SettingsLayout.initialContentHeight(fitting: 1318, screenVisibleHeight: 600) == 560)
    }

    @Test func settingsHeightIgnoresAMissingScreen() {
        #expect(SettingsLayout.initialContentHeight(fitting: 700, screenVisibleHeight: nil) == 700)
    }
}
