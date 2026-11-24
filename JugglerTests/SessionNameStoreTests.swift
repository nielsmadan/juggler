import Foundation
@testable import Juggler
import Testing

@Suite("SessionNameStore")
struct SessionNameStoreTests {
    private let key = AgentSessionIdentity(agent: "codex", agentSessionID: "conversation")

    @Test func namesRoundTripThroughFreshStoreOnTheSameDefaults() {
        let defaults = TestDefaults.fresh()
        let store = SessionNameStore(defaults: defaults)
        #expect(store.setName("Parser work", for: key) == "Parser work")
        #expect(store.name(for: key) == "Parser work")
        #expect(SessionNameStore(defaults: defaults).name(for: key) == "Parser work")

        store.setName("   ", for: key)
        #expect(store.name(for: key) == nil)
        #expect(SessionNameStore(defaults: defaults).names.isEmpty)
    }

    @Test func nonPersistentIdentitiesAreIgnored() {
        let store = SessionNameStore()
        let keys = [
            AgentSessionIdentity(agent: "", agentSessionID: "id"),
            AgentSessionIdentity(agent: "codex", agentSessionID: "")
        ]
        for key in keys {
            #expect(store.setName("name", for: key) == nil)
            #expect(store.name(for: key) == nil)
        }
        #expect(store.names.isEmpty)
    }
}
