import AppKit
@testable import Juggler
import Testing

@Suite("SessionNoteEditorManager", .serialized)
@MainActor
struct SessionNoteEditorManagerTests {
    private func idlessSession(_ id: String) -> Session {
        Session(
            agentSessionID: "",
            terminalSessionID: id,
            terminalType: .iterm2,
            agent: "codex",
            projectPath: "/test/\(id)",
            state: .idle,
            startedAt: Date()
        )
    }

    @Test func noFocusedTrackedSessionForcesNoActiveSessionBeacon() {
        let sessionManager = SessionManager()
        sessionManager.testSetSessions([makeSession("available")])
        sessionManager.isTerminalAppActive = true
        sessionManager.testSetFocusedSessionID("unknown")
        sessionManager.frontmostTerminalTypeProvider = { .iterm2 }
        let editor = SessionNoteEditorManager()
        var presented: [(String, Bool)] = []

        editor.editFocusedSession(in: sessionManager) {
            presented.append(($0, $1))
        }

        #expect(presented.count == 1)
        #expect(presented[0].0 == "No Active Session")
        #expect(presented[0].1 == true)
    }

    @Test func focusedSessionPresentationSavesThroughSessionManager() throws {
        let sessionManager = SessionManager()
        sessionManager.testSetSessions([idlessSession("focused")])
        sessionManager.isTerminalAppActive = true
        sessionManager.testSetFocusedSessionID("focused")
        sessionManager.frontmostTerminalTypeProvider = { .iterm2 }
        var presentations: [SessionNoteEditorPresentation] = []
        let editor = SessionNoteEditorManager { presentations.append($0) }

        editor.editFocusedSession(in: sessionManager)
        let presentation = try #require(presentations.first)
        presentation.onSave("Finish parser")

        #expect(sessionManager.sessions[0].note == "Finish parser")
    }

    @Test func cancelClearsPresentationSoShortcutCanOpenAgain() throws {
        let sessionManager = SessionManager()
        sessionManager.testSetSessions([idlessSession("focused")])
        sessionManager.isTerminalAppActive = true
        sessionManager.testSetFocusedSessionID("focused")
        sessionManager.frontmostTerminalTypeProvider = { .iterm2 }
        var presentations: [SessionNoteEditorPresentation] = []
        let editor = SessionNoteEditorManager { presentations.append($0) }

        editor.editFocusedSession(in: sessionManager)
        let presentation = try #require(presentations.first)
        presentation.onCancel()
        editor.editFocusedSession(in: sessionManager)

        #expect(presentations.count == 2)
    }

    @Test func reinvokingShortcutFromDifferentFocusedSessionRetargetsEditor() throws {
        let sessionManager = SessionManager()
        sessionManager.testSetSessions([idlessSession("first"), idlessSession("second")])
        sessionManager.isTerminalAppActive = true
        sessionManager.frontmostTerminalTypeProvider = { .iterm2 }
        var presentations: [SessionNoteEditorPresentation] = []
        let editor = SessionNoteEditorManager { presentations.append($0) }

        sessionManager.testSetFocusedSessionID("first")
        editor.editFocusedSession(in: sessionManager)
        sessionManager.testSetFocusedSessionID("second")
        editor.editFocusedSession(in: sessionManager)
        let presentation = try #require(presentations.last)
        presentation.onSave("Second task")

        #expect(presentations.count == 2)
        #expect(sessionManager.sessions.map(\.note) == [nil, "Second task"])
    }
}
