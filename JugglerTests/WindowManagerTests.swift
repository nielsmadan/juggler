import AppKit
import Foundation
@testable import Juggler
import Testing

@Suite("WindowManager", .serialized)
@MainActor
struct WindowManagerTests {
    private final class TerminationRecorder {
        var terminations = 0
    }

    private struct Harness {
        let manager: WindowManager
        let window: NSWindow
        let recorder: TerminationRecorder
        let suiteName: String
    }

    private func makeHarness() -> Harness {
        let suiteName = "WindowManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: AppStorageKeys.quitOnMonitorClose)
        let mainWindowID = "test-main-\(UUID().uuidString)"
        let recorder = TerminationRecorder()
        let manager = WindowManager(defaults: defaults, mainWindowID: mainWindowID) { recorder.terminations += 1 }
        manager.observeWindows()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.identifier = NSUserInterfaceItemIdentifier(mainWindowID)
        window.isReleasedWhenClosed = false
        return Harness(manager: manager, window: window, recorder: recorder, suiteName: suiteName)
    }

    @Test func userClosingMonitorQuitsWhenQuitOnCloseIsOn() {
        let harness = makeHarness()
        defer { UserDefaults.standard.removePersistentDomain(forName: harness.suiteName) }

        harness.window.close()

        #expect(harness.recorder.terminations == 1)
    }

    @Test func appInitiatedMonitorCloseDoesNotQuit() {
        let harness = makeHarness()
        defer { UserDefaults.standard.removePersistentDomain(forName: harness.suiteName) }

        harness.manager.closeMainWindow()

        #expect(harness.recorder.terminations == 0)
        #expect(harness.window.isVisible == false)
    }
}
