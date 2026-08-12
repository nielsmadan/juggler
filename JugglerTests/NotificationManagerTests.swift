@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct NotificationManagerTests {
    @Test func clickHandoff_earlierCompletionDoesNotClearNewerHandoff() {
        let manager = NotificationManager.shared

        let first = manager.beginClickHandoff(terminalBundleID: TerminalType.iterm2.bundleIdentifier)
        let second = manager.beginClickHandoff(terminalBundleID: TerminalType.kitty.bundleIdentifier)
        manager.endClickHandoff(first)

        #expect(manager.isHandlingNotificationClick)
        #expect(manager.pendingTerminalBundleID == TerminalType.kitty.bundleIdentifier)

        manager.endClickHandoff(second)

        #expect(!manager.isHandlingNotificationClick)
        #expect(manager.pendingTerminalBundleID == nil)
    }
}
