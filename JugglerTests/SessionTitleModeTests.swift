import Foundation
@testable import Juggler
import Testing

@Suite("SessionTitleMode")
struct SessionTitleModeTests {
    // MARK: - SessionTitleMode Tests

    @Test func sessionTitleMode_displayName() {
        #expect(SessionTitleMode.tabTitle.displayName == "Tab Title")
        #expect(SessionTitleMode.windowTitle.displayName == "Window Title")
        #expect(SessionTitleMode.windowAndTabTitle.displayName == "Window / Tab Title")
        #expect(SessionTitleMode.folderName.displayName == "Folder Name")
        #expect(SessionTitleMode.parentAndFolderName.displayName == "Parent / Folder Name")
        #expect(SessionTitleMode.agentTitle.displayName == "Agent Session Title")
    }

    @Test func agentTitle_usesAgentSessionTitle() {
        var session = makeSession("c")
        session.details.agentTitle = "Fix the parser"
        #expect(session.title(for: .agentTitle) == "Fix the parser")
    }

    @Test func agentTitle_fallsBackToParentAndFolderName() {
        var session = makeSession("c")
        #expect(session.title(for: .agentTitle) == "test/c")
        session.details.agentTitle = ""
        #expect(session.title(for: .agentTitle) == "test/c")
    }

    @Test func agentTitle_customNameWins() {
        var session = makeSession("c")
        session.details.agentTitle = "Fix the parser"
        session.customName = "Mine"
        #expect(session.title(for: .agentTitle) == "Mine")
    }
}
