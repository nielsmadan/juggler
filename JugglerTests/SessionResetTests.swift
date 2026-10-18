import Foundation
@testable import Juggler
import Testing

@Suite("SessionReset")
struct SessionResetTests {
    private let beforeHiding = TestFixtures.date("2026-09-04T12:00:00Z")

    @MainActor
    private func managerWithRowAndHiddenBinding(
        _ hidden: HiddenBindingStore,
        function: String = #function
    ) -> SessionManager {
        let manager = TestFixtures.isolatedSessionManager(hiddenBindings: hidden, function: function)
        manager.addOrUpdateSession(
            claudeSessionID: "native",
            terminalSessionID: "s1",
            projectPath: "/test/project",
            state: .idle,
            bindingID: "b1"
        )
        hidden.hide(["b2"], at: TestFixtures.date("2026-09-04T12:00:30Z"))
        return manager
    }

    @Test @MainActor func successfulResetClearsRowsAndHiddenBindings() async throws {
        let stub = try HooklinesinkerStub.make(stdout: #"{"protocol":1,"removed":3,"problems":[]}"#)
        defer { stub.remove() }
        let hidden = HiddenBindingStore(defaults: TestDefaults.fresh("hidden"))
        let manager = managerWithRowAndHiddenBinding(hidden)

        try await SessionReset.run(client: stub.client, sessionManager: manager)

        #expect(stub.recordedArguments == [["sessions", "reset", "--json"]])
        #expect(manager.sessions.isEmpty)
        #expect(hidden.hides("b2", observedAt: beforeHiding) == false)
    }

    @Test @MainActor func failedResetLeavesRowsAndHiddenBindingsUntouched() async throws {
        let stub = try HooklinesinkerStub.make(stderr: "problem: failed to reset sessions", status: 1)
        defer { stub.remove() }
        let hidden = HiddenBindingStore(defaults: TestDefaults.fresh("hidden"))
        let manager = managerWithRowAndHiddenBinding(hidden)

        await #expect(throws: HooklinesinkerClientError.self) {
            try await SessionReset.run(client: stub.client, sessionManager: manager)
        }

        #expect(manager.sessions.map(\.id) == ["s1"])
        #expect(hidden.hides("b2", observedAt: beforeHiding))
    }
}
