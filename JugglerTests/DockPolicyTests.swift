@testable import Juggler
import Testing

@Suite("DockPolicy")
struct DockPolicyTests {
    @Test func userClosingMonitorQuitsWhenQuitOnCloseIsOn() {
        #expect(DockPolicy.closeOutcome(
            closing: .main(appInitiated: false), quitOnMonitorClose: true, otherWindowOpen: true
        ) == .quit)
    }

    @Test func appInitiatedMonitorCloseHidesDockIconInsteadOfQuitting() {
        #expect(DockPolicy.closeOutcome(
            closing: .main(appInitiated: true), quitOnMonitorClose: true, otherWindowOpen: false
        ) == .hideDockIcon)
    }

    @Test func appInitiatedMonitorCloseKeepsDockIconWhileSettingsIsOpen() {
        #expect(DockPolicy.closeOutcome(
            closing: .main(appInitiated: true), quitOnMonitorClose: true, otherWindowOpen: true
        ) == .keepDockIcon)
    }

    @Test func closingSettingsWithQuitOnCloseOnHidesDockIcon() {
        #expect(DockPolicy.closeOutcome(
            closing: .other, quitOnMonitorClose: true, otherWindowOpen: false
        ) == .hideDockIcon)
    }

    @Test func closingAWindowKeepsDockIconWhileAnotherIsOpen() {
        #expect(DockPolicy.closeOutcome(
            closing: .main(appInitiated: false), quitOnMonitorClose: false, otherWindowOpen: true
        ) == .keepDockIcon)
    }

    @Test func titledWindowIsAnAppWindow() {
        #expect(DockPolicy.isAppWindow(isTitled: true, isPanel: false, isSheet: false))
    }

    @Test func panelsSheetsAndUntitledWindowsAreNotAppWindows() {
        #expect([
            DockPolicy.isAppWindow(isTitled: true, isPanel: true, isSheet: false),
            DockPolicy.isAppWindow(isTitled: true, isPanel: false, isSheet: true),
            DockPolicy.isAppWindow(isTitled: false, isPanel: false, isSheet: false)
        ] == [false, false, false])
    }

    @Test func minimizedAppWindowKeepsDockIcon() {
        #expect(DockPolicy.keepsDockIcon(isAppWindow: true, isVisible: false, isMiniaturized: true))
    }

    @Test func visibleAppWindowKeepsDockIcon() {
        #expect(DockPolicy.keepsDockIcon(isAppWindow: true, isVisible: true, isMiniaturized: false))
    }

    @Test func closedAppWindowReleasesDockIcon() {
        #expect(DockPolicy.keepsDockIcon(isAppWindow: true, isVisible: false, isMiniaturized: false) == false)
    }

    @Test func visiblePanelReleasesDockIcon() {
        #expect(DockPolicy.keepsDockIcon(isAppWindow: false, isVisible: true, isMiniaturized: false) == false)
    }
}
