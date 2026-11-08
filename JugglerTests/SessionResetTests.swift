import Foundation
@testable import Juggler
import Testing

@Suite("SessionReset")
struct SessionResetTests {
    private let beforeHiding = TestFixtures.date("2026-09-04T12:00:00Z")

    @MainActor
    private func managerWithRowAndHiddenBinding(
        _ hidden: HiddenBindingStore,
        dispositionStore: SessionDispositionStore,
        function: String = #function
    ) -> SessionManager {
        let manager = TestFixtures.isolatedSessionManager(
            hiddenBindings: hidden, dispositionStore: dispositionStore, function: function
        )
        manager.addOrUpdateSession(
            agentSessionID: "native",
            terminalSessionID: "s1",
            projectPath: "/test/project",
            state: .idle,
            bindingID: "b1"
        )
        manager.setSessionHidden(sessionID: "s1", isHidden: true)
        manager.backburnerSession(terminalSessionID: "s1", now: beforeHiding)
        manager.updateNote(for: manager.sessions[0], note: "Keep this note")
        hidden.hide(["b2"], at: TestFixtures.date("2026-09-04T12:00:30Z"))
        return manager
    }

    @Test @MainActor func successfulResetClearsRowsBindingsAndDispositionsButKeepsNotes() async throws {
        let stub = try HooklinesinkerStub.make(stdout: #"{"protocol":1,"removed":3,"problems":[]}"#)
        defer { stub.remove() }
        let hidden = HiddenBindingStore(defaults: TestDefaults.fresh("hidden"))
        let defaults = TestDefaults.fresh("dispositions")
        let manager = managerWithRowAndHiddenBinding(
            hidden, dispositionStore: SessionDispositionStore(defaults: defaults)
        )

        try await SessionReset.run(client: stub.client, sessionManager: manager)

        #expect(stub.recordedArguments == [["sessions", "reset", "--json"]])
        #expect(manager.sessions.isEmpty)
        #expect(hidden.hides("b2", observedAt: beforeHiding) == false)
        #expect(manager.dispositionStore.dispositions.isEmpty)
        #expect(SessionDispositionStore(defaults: defaults).dispositions.isEmpty)
        #expect(manager.noteStore.note(for: .init(agent: "claude-code", agentSessionID: "native")) == "Keep this note")
    }

    @Test @MainActor func failedResetLeavesRowsBindingsAndDispositionsUntouched() async throws {
        let stub = try HooklinesinkerStub.make(stderr: "problem: failed to reset sessions", status: 1)
        defer { stub.remove() }
        let hidden = HiddenBindingStore(defaults: TestDefaults.fresh("hidden"))
        let defaults = TestDefaults.fresh("dispositions")
        let manager = managerWithRowAndHiddenBinding(
            hidden, dispositionStore: SessionDispositionStore(defaults: defaults)
        )
        let rowsBefore = manager.sessions
        let dispositionsBefore = manager.dispositionStore.dispositions

        await #expect(throws: HooklinesinkerClientError.self) {
            try await SessionReset.run(client: stub.client, sessionManager: manager)
        }

        #expect(manager.sessions.map(\.id) == ["s1"])
        #expect(manager.sessions == rowsBefore)
        #expect(manager.dispositionStore.dispositions == dispositionsBefore)
        #expect(SessionDispositionStore(defaults: defaults).dispositions == dispositionsBefore)
        #expect(manager.noteStore.note(for: .init(agent: "claude-code", agentSessionID: "native")) == "Keep this note")
        #expect(hidden.hides("b2", observedAt: beforeHiding))
    }
}
