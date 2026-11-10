import Foundation
@testable import Juggler
import Testing

@Suite("SessionDispositionStore")
struct SessionDispositionStoreTests {
    private let key = AgentSessionIdentity(agent: "codex", agentSessionID: "conversation")

    @Test func roundTripPreservesEveryIndependentFieldAndClearsEmptyRecords() throws {
        let defaults = TestDefaults.fresh()
        let store = SessionDispositionStore(defaults: defaults)
        let backburner = BackburnerDisposition(
            wasAwaitingUser: true, backburneredAt: Date(timeIntervalSince1970: 1234), turnsByBinding: ["binding": 7]
        )
        let expected = SessionDisposition(isHidden: true, isPrioritized: true, backburner: backburner)
        store.setDisposition(expected, for: key)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)

        store.setDisposition(.init(isHidden: false, backburner: backburner), for: key)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key).backburner == backburner)
        store.setDisposition(.empty, for: key)
        #expect(SessionDispositionStore(defaults: defaults).dispositions.isEmpty)
        let data = try #require(defaults.data(forKey: AppStorageKeys.sessionDispositions))
        #expect(try JSONDecoder().decode(SessionDispositionEnvelope.self, from: data).records.isEmpty)
    }

    @Test func recordsWithoutThePrioFieldReadAsNotPrioritized() throws {
        let legacy = #"{"isHidden":true}"#
        let decoded = try JSONDecoder().decode(SessionDisposition.self, from: Data(legacy.utf8))
        #expect(decoded == SessionDisposition(isHidden: true, isPrioritized: false))
    }

    @Test func encodingIsVersionedSortedAndIndependentOfInsertionOrder() throws {
        let firstDefaults = TestDefaults.fresh("first")
        let secondDefaults = TestDefaults.fresh("second")
        let first = SessionDispositionStore(defaults: firstDefaults)
        let second = SessionDispositionStore(defaults: secondDefaults)
        let keys = [
            AgentSessionIdentity(agent: "pi", agentSessionID: "a"),
            AgentSessionIdentity(agent: "codex", agentSessionID: "z"),
            AgentSessionIdentity(agent: "codex", agentSessionID: "a")
        ]
        for key in keys {
            first.setDisposition(.init(isHidden: true), for: key)
        }
        for key in keys.reversed() {
            second.setDisposition(.init(isHidden: true), for: key)
        }
        let data = try #require(firstDefaults.data(forKey: AppStorageKeys.sessionDispositions))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        let envelope = try JSONDecoder().decode(SessionDispositionEnvelope.self, from: data)
        #expect(envelope.records.map(\.key) == [keys[2], keys[1], keys[0]])
        #expect(secondDefaults.data(forKey: AppStorageKeys.sessionDispositions) == data)
    }

    @Test func decodingSkipsMalformedAndInvalidRecordsAndLastValidDuplicateWins() {
        let defaults = TestDefaults.fresh()
        let json = """
        {"schemaVersion":1,"records":[
          {"key":{"agent":"codex","agentSessionID":"conversation"},"disposition":{"isHidden":false}},
          null,
          12,
          {"key":{"agent":"","agentSessionID":"empty-agent"},"disposition":{"isHidden":true}},
          {"key":{"agent":"codex","agentSessionID":"   "},"disposition":{"isHidden":true}},
          {"key":{"agent":"codex","agentSessionID":"conversation"},"disposition":{"isHidden":true}},
          {"key":{"agent":"codex","agentSessionID":"conversation"},"disposition":{"isHidden":"wrong"}},
          {"key":{"agent":"pi","agentSessionID":"bad-backburner"},"disposition":{
            "isHidden":true,"backburner":{"wasAwaitingUser":true,"backburneredAt":"invalid"}
          }},
          {"key":{"agent":"pi","agentSessionID":"cleared"},"disposition":{"isHidden":true}},
          {"key":{"agent":"pi","agentSessionID":"cleared"},"disposition":{"isHidden":false}}
        ]}
        """
        defaults.set(Data(json.utf8), forKey: AppStorageKeys.sessionDispositions)
        let store = SessionDispositionStore(defaults: defaults)
        #expect(store.dispositions == [key: .init(isHidden: true)])
    }

    @Test(arguments: ["not-json", #"{"schemaVersion":9,"records":[]}"#, #"{"schemaVersion":1,"records":{}}"#])
    func corruptOrUnknownDataFallsBackAndReportsTheProblem(json: String) {
        let defaults = TestDefaults.fresh(json)
        let data = Data(json.utf8)
        defaults.set(data, forKey: AppStorageKeys.sessionDispositions)
        var errors: [String] = []
        let store = SessionDispositionStore(defaults: defaults, reportError: { errors.append($0) })
        #expect(store.dispositions.isEmpty)
        #expect(errors.count == 1)
        #expect(defaults.data(forKey: AppStorageKeys.sessionDispositions) == data)
    }

    @Test func invalidIdentitiesCannotBeSaved() {
        let store = SessionDispositionStore()
        let keys = [
            AgentSessionIdentity(agent: "", agentSessionID: "id"),
            AgentSessionIdentity(agent: "codex", agentSessionID: ""),
            AgentSessionIdentity(agent: " ", agentSessionID: "id"),
            AgentSessionIdentity(agent: "codex", agentSessionID: "\n")
        ]
        for key in keys {
            store.setDisposition(.init(isHidden: true), for: key)
        }
        #expect(store.dispositions.isEmpty)
    }

    @Test func invalidBindingCountsDoNotDiscardTheDispositionOrValidBaselines() {
        let defaults = TestDefaults.fresh()
        let json = """
        {"schemaVersion":1,"records":[{
          "key":{"agent":"codex","agentSessionID":"conversation"},
          "disposition":{"isHidden":true,"backburner":{
            "wasAwaitingUser":true,"backburneredAt":0,
            "turnsByBinding":{"valid":7,"zero":0,"negative":-1,"string":"4","null":null,"bool":false,"":9}
          }}
        }]}
        """
        defaults.set(Data(json.utf8), forKey: AppStorageKeys.sessionDispositions)
        let expected = SessionDisposition(isHidden: true, backburner: .init(
            wasAwaitingUser: true, backburneredAt: Date(timeIntervalSinceReferenceDate: 0),
            turnsByBinding: ["valid": 7, "zero": 0]
        ))
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test func legacyScalarBaselineRestoresBackburnerWithoutInventingABinding() {
        let defaults = TestDefaults.fresh()
        let json = """
        {"schemaVersion":1,"records":[{
          "key":{"agent":"codex","agentSessionID":"conversation"},
          "disposition":{"isHidden":true,"backburner":{
            "wasAwaitingUser":true,"backburneredAt":0,"turnsAtBackburner":7
          }}
        }]}
        """
        defaults.set(Data(json.utf8), forKey: AppStorageKeys.sessionDispositions)
        let expected = SessionDisposition(isHidden: true, backburner: .init(
            wasAwaitingUser: true, backburneredAt: Date(timeIntervalSinceReferenceDate: 0)
        ))
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test func bindingBaselineEncodingIsDeterministic() throws {
        let firstDefaults = TestDefaults.fresh("first")
        let secondDefaults = TestDefaults.fresh("second")
        let first = SessionDispositionStore(defaults: firstDefaults)
        let second = SessionDispositionStore(defaults: secondDefaults)
        let time = Date(timeIntervalSinceReferenceDate: 0)
        first.setDisposition(.init(isHidden: true, backburner: .init(
            wasAwaitingUser: true, backburneredAt: time, turnsByBinding: ["z": 8, "a": 4]
        )), for: key)
        second.setDisposition(.init(isHidden: true, backburner: .init(
            wasAwaitingUser: true, backburneredAt: time, turnsByBinding: ["a": 4, "z": 8]
        )), for: key)
        let firstData = try #require(firstDefaults.data(forKey: AppStorageKeys.sessionDispositions))
        #expect(secondDefaults.data(forKey: AppStorageKeys.sessionDispositions) == firstData)
    }

    @Test func managerDefaultsAreIndependentInMemoryStores() {
        let before = UserDefaults.standard.data(forKey: AppStorageKeys.sessionDispositions)
        let first = SessionManager()
        let second = SessionManager()
        first.dispositionStore.setDisposition(.init(isHidden: true), for: key)
        #expect(first.dispositionStore.disposition(for: key).isHidden)
        #expect(second.dispositionStore.dispositions.isEmpty)
        #expect(UserDefaults.standard.data(forKey: AppStorageKeys.sessionDispositions) == before)
    }

    @Test func sessionEqualityIncludesDispositionWhileCodableOmitsIt() throws {
        let original = makeSession("pane")
        var hidden = original
        hidden.disposition.isHidden = true
        #expect(hidden != original)
        var shelved = original
        shelved.disposition.backburner = BackburnerDisposition(
            wasAwaitingUser: true, backburneredAt: Date()
        )
        #expect(shelved != original)
        hidden.transientDispositionOverrides.isHidden = true
        let encoded = try JSONEncoder().encode(hidden)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["disposition"] == nil)
        #expect(json["transientDispositionOverrides"] == nil)
        #expect(try JSONDecoder().decode(Session.self, from: encoded).disposition == .empty)
    }
}
