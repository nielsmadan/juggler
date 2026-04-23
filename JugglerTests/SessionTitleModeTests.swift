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
    }
}
