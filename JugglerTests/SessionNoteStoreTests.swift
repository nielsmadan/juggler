import Foundation
@testable import Juggler
import Testing

@Suite("SessionNoteStore")
struct SessionNoteStoreTests {
    private func freshDefaults() -> (UserDefaults, () -> Void) {
        let suite = "SessionNoteStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func saveOverwriteClearAndReload() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        let key = SessionNoteKey(agent: "codex", agentSessionID: "conversation-1")
        let store = SessionNoteStore(defaults: defaults)

        store.setNote("first", for: key)
        store.setNote("second", for: key)
        #expect(SessionNoteStore(defaults: defaults).note(for: key) == "second")

        store.setNote("   ", for: key)
        #expect(store.note(for: key) == nil)
        #expect(SessionNoteStore(defaults: defaults).note(for: key) == nil)
    }

    @Test func equalConversationIDsFromDifferentAgentsRemainIndependent() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        let store = SessionNoteStore(defaults: defaults)
        let codex = SessionNoteKey(agent: "codex", agentSessionID: "same-id")
        let pi = SessionNoteKey(agent: "pi", agentSessionID: "same-id")

        store.setNote("Codex task", for: codex)
        store.setNote("Pi task", for: pi)

        #expect(store.note(for: codex) == "Codex task")
        #expect(store.note(for: pi) == "Pi task")
    }

    @Test func normalizationProducesOneCompleteLine() {
        let longTail = String(repeating: "x", count: 1000)
        let normalized = SessionNoteStore.normalize("  first line\n second line \n\n\(longTail)  ")

        #expect(normalized == "first line second line \(longTail)")
        #expect(normalized?.count == "first line second line ".count + longTail.count)
    }

    @Test func corruptPayloadFallsBackToEmptyStore() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        defaults.set(Data("not-json".utf8), forKey: AppStorageKeys.sessionNotes)

        let store = SessionNoteStore(defaults: defaults)

        #expect(store.notes.isEmpty)
    }

    @Test func emptyIdentityComponentsAreNeverPersisted() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        let store = SessionNoteStore(defaults: defaults)

        store.setNote("No agent", for: .init(agent: "", agentSessionID: "conversation-1"))
        store.setNote("No conversation", for: .init(agent: "codex", agentSessionID: ""))

        #expect(store.notes.isEmpty)
    }

    @Test func encodedRecordsAreDeterministicallySorted() throws {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        let store = SessionNoteStore(defaults: defaults)
        store.setNote("second", for: .init(agent: "pi", agentSessionID: "2"))
        store.setNote("first", for: .init(agent: "codex", agentSessionID: "1"))

        let data = try #require(defaults.data(forKey: AppStorageKeys.sessionNotes))
        let records = try JSONDecoder().decode([SessionNoteRecord].self, from: data)

        #expect(records.map(\.key) == [
            .init(agent: "codex", agentSessionID: "1"),
            .init(agent: "pi", agentSessionID: "2")
        ])
    }
}
