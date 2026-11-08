import Foundation
@testable import Juggler
import Testing

@Suite("Session disposition hydration evidence", .serialized)
struct SessionDispositionHydrationTests {
    private let key = AgentSessionIdentity(agent: "codex", agentSessionID: "conversation")
    private let shelvedAt = TestFixtures.date("2026-09-04T12:00:30Z")

    private func body(
        binding: String = "binding-a",
        pane: String = "pane-a",
        activity: String = #"{"turns":4}"#,
        observedAt: String = "2026-09-04T12:00:00Z"
    ) -> String {
        TestFixtures.statusJSON(
            bindingId: binding, agent: "codex", event: "Stop", phase: "idle", observedAt: observedAt,
            sessionID: "conversation", terminalSessionID: pane, activity: activity
        )
    }

    private func manager(defaults: UserDefaults, function: String = #function) -> SessionManager {
        TestFixtures.isolatedSessionManager(
            dispositionStore: SessionDispositionStore(defaults: defaults), function: function
        )
    }

    private func server(for manager: SessionManager) -> HookServer {
        HookServer(sessionManager: manager, notificationSink: { _, _ in })
    }

    private func hydrate(_ server: HookServer, body: String) async throws {
        let status = try JSONDecoder().decode(HooklinesinkerStatus.self, from: Data(body.utf8))
        await server.hydrate([status])
    }

    @Test(arguments: [false, true], [-10.0, 0.0])
    func olderOrEqualTimestampCannotProveAnIncreasedCount(restart: Bool, offset: TimeInterval) async throws {
        let defaults = TestDefaults.fresh("\(restart)-\(offset)")
        let initial = manager(defaults: defaults)
        await server(for: initial).handleStatusForTesting(body())
        initial.setSessionHidden(sessionID: "pane-a", isHidden: true)
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        let expected = SessionDisposition(isHidden: true, backburner: .init(
            wasAwaitingUser: true, backburneredAt: shelvedAt, turnsByBinding: ["binding-a": 4]
        ))
        #expect(initial.dispositionStore.disposition(for: key) == expected)

        let hydrated = restart ? manager(defaults: defaults) : initial
        try await hydrate(server(for: hydrated), body: body(
            activity: #"{"turns":5}"#, observedAt: shelvedAt.addingTimeInterval(offset).formatted(.iso8601)
        ))

        #expect(hydrated.sessions.map(\.state) == [.backburner])
        #expect(hydrated.sessions[0].disposition == expected)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test func missingTimestampCannotProveAnIncreasedCount() async throws {
        let defaults = TestDefaults.fresh()
        let initial = manager(defaults: defaults)
        await server(for: initial).handleStatusForTesting(body())
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        let expected = initial.dispositionStore.disposition(for: key)
        let hydrated = manager(defaults: defaults)

        try await hydrate(server(for: hydrated), body: body(activity: #"{"turns":5}"#, observedAt: "unreadable"))

        #expect(hydrated.sessions.map(\.state) == [.backburner])
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test func increaseOnLowerCountBindingWakesEveryDuplicateAndWritesOnce() async throws {
        let suite = "JugglerTests.BindingWakeWrites.\(UUID().uuidString)"
        let defaults = try #require(DispositionCountingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = manager(defaults: defaults)
        let ingress = server(for: initial)
        await ingress.handleStatusForTesting(body())
        await ingress.handleStatusForTesting(body(binding: "binding-b", pane: "pane-b", activity: #"{"turns":8}"#))
        initial.setSessionHidden(sessionID: "pane-a", isHidden: true)
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key).backburner?.turnsByBinding
            == ["binding-a": 4, "binding-b": 8])
        #expect(defaults.dispositionWrites == 2)

        let hydrated = manager(defaults: defaults)
        let hydration = server(for: hydrated)
        try await hydrate(hydration, body: body(
            binding: "binding-b", pane: "pane-b", activity: #"{"turns":8}"#, observedAt: "2026-09-04T12:00:31Z"
        ))
        #expect(hydrated.sessions.map(\.state) == [.backburner])
        try await hydrate(hydration, body: body(activity: #"{"turns":5}"#, observedAt: "2026-09-04T12:00:32Z"))

        #expect(hydrated.sessions.count == 2)
        #expect(hydrated.sessions.allSatisfy { $0.state == .idle && $0.disposition == .init(isHidden: true) })
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == .init(isHidden: true))
        #expect(defaults.dispositionWrites == 3)
    }

    @Test func unknownBindingCannotProveWakeFromLargerHistoricalCounts() async throws {
        let defaults = TestDefaults.fresh()
        let initial = manager(defaults: defaults)
        await server(for: initial).handleStatusForTesting(body())
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        let expected = initial.dispositionStore.disposition(for: key)
        let hydrated = manager(defaults: defaults)
        let hydration = server(for: hydrated)

        try await hydrate(hydration, body: body(
            binding: "unknown", activity: #"{"turns":100}"#, observedAt: "2026-09-04T12:00:31Z"
        ))
        try await hydrate(hydration, body: body(
            binding: "unknown", activity: #"{"turns":101}"#, observedAt: "2026-09-04T12:00:32Z"
        ))

        #expect(hydrated.sessions.map(\.state) == [.backburner])
        #expect(hydrated.sessions[0].disposition == expected)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test(arguments: [
        #"{"tool":"Bash"}"#, #"{"turns":"4"}"#, #"{"turns":-1}"#,
        #"{"turns":null}"#, #"{"turns":false}"#, #"{"turns":1.5}"#, #"{"turns":0}"#
    ])
    func onlyExplicitNonnegativeIntegerBaselinesCanProveWake(activity: String) async throws {
        let defaults = TestDefaults.fresh(activity)
        let initial = manager(defaults: defaults)
        await server(for: initial).handleStatusForTesting(body(activity: activity))
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        let isKnownZero = activity == #"{"turns":0}"#
        let baseline: [String: Int] = isKnownZero ? ["binding-a": 0] : [:]
        let shelved = SessionDisposition(isHidden: false, backburner: .init(
            wasAwaitingUser: true, backburneredAt: shelvedAt, turnsByBinding: baseline
        ))
        #expect(initial.sessions[0].details.reportedTurns == (isKnownZero ? 0 : nil))
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == shelved)
        let hydrated = manager(defaults: defaults)

        try await hydrate(server(for: hydrated), body: body(observedAt: "2026-09-04T12:00:31Z"))

        let expected: SessionDisposition = isKnownZero ? .empty : shelved
        #expect(hydrated.sessions.map(\.state) == [isKnownZero ? .idle : .backburner])
        #expect(hydrated.sessions[0].disposition == expected)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test(arguments: [#"{}"#, #"{"turns":"5"}"#, #"{"turns":-1}"#])
    func invalidIncomingCountCannotProveWake(activity: String) async throws {
        let defaults = TestDefaults.fresh(activity)
        let initial = manager(defaults: defaults)
        await server(for: initial).handleStatusForTesting(body(activity: #"{"turns":0}"#))
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        let expected = initial.dispositionStore.disposition(for: key)
        let hydrated = manager(defaults: defaults)

        try await hydrate(server(for: hydrated), body: body(activity: activity, observedAt: "2026-09-04T12:00:31Z"))

        #expect(hydrated.sessions.map(\.state) == [.backburner])
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }

    @Test func multipleBindingsOnOneRowRetainSeparateBaselines() async throws {
        let defaults = TestDefaults.fresh()
        let initial = manager(defaults: defaults)
        let ingress = server(for: initial)
        await ingress.handleStatusForTesting(body())
        await ingress.handleStatusForTesting(body(binding: "binding-b", activity: #"{"turns":8}"#))
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key).backburner?.turnsByBinding
            == ["binding-a": 4, "binding-b": 8])

        try await hydrate(server(for: initial), body: body(
            activity: #"{"turns":5}"#, observedAt: "2026-09-04T12:00:31Z"
        ))

        #expect(initial.sessions.map(\.state) == [.idle])
        #expect(SessionDispositionStore(defaults: defaults).dispositions.isEmpty)
    }

    @Test func newerInvalidCountMakesTheBindingBaselineAmbiguous() async throws {
        let defaults = TestDefaults.fresh()
        let initial = manager(defaults: defaults)
        let ingress = server(for: initial)
        await ingress.handleStatusForTesting(body())
        await ingress.handleStatusForTesting(body(activity: #"{"turns":"5"}"#, observedAt: "2026-09-04T12:00:29Z"))
        initial.backburnerSession(terminalSessionID: "pane-a", now: shelvedAt)
        let expected = SessionDisposition(isHidden: false, backburner: .init(
            wasAwaitingUser: true, backburneredAt: shelvedAt
        ))
        #expect(initial.dispositionStore.disposition(for: key) == expected)

        let hydrated = manager(defaults: defaults)
        try await hydrate(server(for: hydrated), body: body(
            activity: #"{"turns":5}"#, observedAt: "2026-09-04T12:00:31Z"
        ))

        #expect(hydrated.sessions.map(\.state) == [.backburner])
        #expect(SessionDispositionStore(defaults: defaults).disposition(for: key) == expected)
    }
}
