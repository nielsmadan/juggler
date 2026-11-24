import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct SessionNamePersistenceTests {
    private let key = AgentSessionIdentity(agent: "codex", agentSessionID: "conversation")

    @discardableResult
    private func receive(
        _ manager: SessionManager,
        pane: String = "pane",
        conversation: String = "conversation",
        state: SessionState = .idle,
        event: String? = "Stop"
    ) -> Bool {
        manager.addOrUpdateSession(
            agentSessionID: conversation, terminalSessionID: pane, agent: "codex",
            projectPath: "/test", state: state, event: event
        )
    }

    @Test func nameFollowsTheConversationIntoANewPane() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager)
        manager.renameSession(terminalSessionID: "pane", customName: "Parser")
        manager.removeSession(sessionID: "pane")

        receive(manager, pane: "new-pane")

        #expect(manager.sessions[0].customName == "Parser")
    }

    @Test func renamingOneRowRenamesEveryRowOfTheConversation() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager)
        receive(manager, pane: "duplicate")

        manager.renameSession(terminalSessionID: "pane", customName: "Shared")

        #expect(manager.sessions.allSatisfy { $0.customName == "Shared" })
    }

    @Test func newManagerOnTheSameStoreDefaultsRestoresTheName() {
        let defaults = TestDefaults.fresh()
        let first = TestFixtures.isolatedSessionManager(nameStore: SessionNameStore(defaults: defaults))
        receive(first)
        first.renameSession(terminalSessionID: "pane", customName: "Kept")

        let second = TestFixtures.isolatedSessionManager(nameStore: SessionNameStore(defaults: defaults))
        receive(second, pane: "other")

        #expect(second.sessions[0].customName == "Kept")
    }

    @Test func replacedConversationDoesNotInheritTheOldName() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager)
        manager.renameSession(terminalSessionID: "pane", customName: "Old")

        receive(manager, conversation: "new", event: "SessionStart")

        #expect(manager.sessions[0].customName == nil)
    }

    @Test func transientRowNameIsStoredOnceTheIdentityArrives() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager, conversation: "")
        manager.renameSession(terminalSessionID: "pane", customName: "Draft")

        receive(manager)

        #expect(manager.nameStore.name(for: key) == "Draft")
        #expect(manager.sessions[0].customName == "Draft")
    }

    @Test func nonPersistentIdentityKeepsTheNameOnTheRowOnly() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager, conversation: "")
        manager.renameSession(terminalSessionID: "pane", customName: "Row only")

        #expect(manager.sessions[0].customName == "Row only")
        #expect(manager.nameStore.names.isEmpty)
    }
}
