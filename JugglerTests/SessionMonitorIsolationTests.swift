@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct SessionMonitorIsolationTests {
    @Test func hidingTheLastRowClearsOnlyTheSuppliedManagersColor() {
        let originalColor = SessionManager.shared.activeColorIndex
        defer { SessionManager.shared.setColorIndex(to: originalColor) }
        SessionManager.shared.setColorIndex(to: 1)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("A")])
        manager.setColorIndex(to: 2)
        let controller = SessionListController()
        controller.selectedSessionID = "A"

        controller.toggleHidden(sessionID: "A", sessionManager: manager)

        #expect(manager.listedSessions.isEmpty)
        #expect(controller.selectedSessionID == nil)
        #expect(manager.activeColorIndex == 0)
        #expect(SessionManager.shared.activeColorIndex == 1)
    }
}
