import Foundation
@testable import Juggler
import Testing

/// Drives the client against a stub shell script standing in for the CLI. The stub records its
/// argv and selected environment so the exact command line — which is the contract with
/// hooklinesinker — is asserted rather than assumed.
@Suite("HooklinesinkerClient")
struct HooklinesinkerClientTests {
    // MARK: - Consumer registration

    @Test func installConsumerRegistersJugglerWithItsOwnSinkURL() async throws {
        let stub = try HooklinesinkerStub.make(
            stdout: "registered consumer juggler",
            sinkURL: "http://127.0.0.1:9001/hook"
        )
        defer { stub.remove() }

        let result = await stub.client.installConsumer()

        #expect(result.isSuccess)
        #expect(stub.recordedArguments == [[
            "install", "--consumer", "juggler", "--sink", "http://127.0.0.1:9001/hook"
        ]])
    }

    @Test func defaultSinkURLTargetsTheHookServersOwnPort() {
        let client = HooklinesinkerClient(bundledExecutablePath: "/nonexistent", dataRoot: "/nonexistent")
        #expect(client.sinkURL == "http://127.0.0.1:\(TestInstanceConfig.hookPort())/hook")
    }

    @Test func uninstallConsumerRemovesJuggler() async throws {
        let stub = try HooklinesinkerStub.make()
        defer { stub.remove() }

        _ = await stub.client.uninstallConsumer()

        #expect(stub.recordedArguments == [["uninstall", "--consumer", "juggler"]])
    }

    @Test func failuresExposeExactStderrAndExitStatus() async throws {
        let stub = try HooklinesinkerStub.make(
            stderr: "failed to register consumer juggler: permission denied",
            status: 1
        )
        defer { stub.remove() }

        let result = await stub.client.installConsumer()

        #expect(!result.isSuccess)
        #expect(result.exitStatus == 1)
        #expect(result.standardError == "failed to register consumer juggler: permission denied")
        #expect(result.failureMessage == "failed to register consumer juggler: permission denied")
    }

    @Test func aMissingBinaryReportsItsPathInsteadOfCrashing() async {
        let client = HooklinesinkerClient(
            bundledExecutablePath: "/nonexistent/hooklinesinker", dataRoot: "/nonexistent"
        )

        let result = await client.installConsumer()

        #expect(!result.isSuccess)
        #expect(result.standardError.contains("/nonexistent/hooklinesinker"))
    }

    @Test func xdgOverridesReachTheChildProcess() async throws {
        let stub = try HooklinesinkerStub.make(environmentOverrides: ["XDG_STATE_HOME": "/tmp/hls-state"])
        defer { stub.remove() }

        _ = await stub.client.installConsumer()

        #expect(stub.recordedEnvironment == ["XDG_STATE_HOME=/tmp/hls-state"])
    }

    // MARK: - Agent hooks

    @Test(arguments: HooklinesinkerAgent.allCases)
    func installHooksPassesTheAgentThrough(agent: HooklinesinkerAgent) async throws {
        let stub = try HooklinesinkerStub.make()
        defer { stub.remove() }

        _ = await stub.client.installHooks(agent: agent)

        #expect(stub.recordedArguments == [["hooks", "install", "--agent", agent.rawValue]])
    }

    @Test func hookStatusDecodesTheCommandAndGroupIndexOfEveryEntry() async throws {
        let json = """
        {"protocol":1,"agent":"codex","state":"installed","path":"/home/me/.codex/hooks.json",\
        "entries":[{"event":"SessionStart","groupIndex":1,"command":"/bin/hls ingest --agent codex \
        --event SessionStart"},{"event":"Stop","groupIndex":0,"command":"/bin/hls ingest --agent codex \
        --event Stop"}]}
        """
        let stub = try HooklinesinkerStub.make(stdout: json)
        defer { stub.remove() }

        let status = try await stub.client.hookStatus(agent: .codex)

        #expect(stub.recordedArguments == [["hooks", "status", "--agent", "codex", "--json"]])
        #expect(status.agent == "codex")
        #expect(status.state == .installed)
        #expect(status.path == "/home/me/.codex/hooks.json")
        #expect(status.entries.count == 2)
        #expect(status.entries[0] == HooklinesinkerHookEntry(
            event: "SessionStart",
            groupIndex: 1,
            command: "/bin/hls ingest --agent codex --event SessionStart"
        ))
        #expect(status.entries[1].groupIndex == 0)
    }

    @Test(arguments: [
        ("missing", HooklinesinkerState.missing),
        ("installed", HooklinesinkerState.installed),
        ("drifted", HooklinesinkerState.drifted),
        ("unsupported", HooklinesinkerState.unsupported)
    ])
    func hookStatusDecodesEveryState(raw: String, expected: HooklinesinkerState) async throws {
        let stub = try HooklinesinkerStub.make(
            stdout: #"{"protocol":1,"agent":"claude","state":"\#(raw)","path":"/p","entries":[]}"#
        )
        defer { stub.remove() }

        let status = try await stub.client.hookStatus(agent: .claude)
        #expect(status.state == expected)
    }

    @Test func isInstalledIsTrueOnlyForTheInstalledState() async throws {
        let installed = try HooklinesinkerStub.make(
            stdout: #"{"protocol":1,"agent":"pi","state":"installed","path":"/p","entries":[]}"#
        )
        defer { installed.remove() }
        let drifted = try HooklinesinkerStub.make(
            stdout: #"{"protocol":1,"agent":"pi","state":"drifted","path":"/p","entries":[]}"#
        )
        defer { drifted.remove() }

        #expect(await installed.client.isInstalled(agent: .pi))
        #expect(await drifted.client.isInstalled(agent: .pi) == false)
    }

    @Test func hookStatusSurfacesACommandFailure() async throws {
        let stub = try HooklinesinkerStub.make(stderr: "boom", status: 1)
        defer { stub.remove() }

        await #expect(throws: HooklinesinkerClientError.self) {
            try await stub.client.hookStatus(agent: .claude)
        }
    }

    @Test func hookStatusRejectsAnUnsupportedProtocol() async throws {
        let stub = try HooklinesinkerStub.make(
            stdout: #"{"protocol":2,"agent":"claude","state":"installed","path":"/p","entries":[]}"#
        )
        defer { stub.remove() }

        await #expect(throws: HooklinesinkerClientError.self) {
            try await stub.client.hookStatus(agent: .claude)
        }
    }

    // MARK: - Sessions

    @Test func sessionsDecodesTheEnvelope() async throws {
        let stub = try HooklinesinkerStub.make(stdout: TestFixtures.sessionsEnvelope(
            [
                TestFixtures.statusJSON(bindingId: "b1", terminalSessionID: "s1"),
                TestFixtures.statusJSON(bindingId: "b2", phase: "working", terminalSessionID: "s2")
            ],
            problems: ["sink juggler failed: connection refused"]
        ))
        defer { stub.remove() }

        let sessions = try await stub.client.sessions()

        #expect(stub.recordedArguments == [["sessions", "--json"]])
        #expect(sessions.statuses.map(\.bindingId) == ["b1", "b2"])
        #expect(sessions.statuses[1].phase == .working)
        #expect(sessions.skippedRecordCount == 0)
        #expect(sessions.problems.map(\.message) == ["sink juggler failed: connection refused"])
        #expect(sessions.problems.first?.observedAt == "2026-09-04T12:00:00Z")
        // Log line leads with a local-time stamp, then the framed message (exact time is
        // timezone-dependent, so assert the structure rather than a literal clock value).
        let line = try #require(sessions.problems.first?.logLine)
        #expect(line.hasPrefix("["))
        #expect(line.contains("] hooklinesinker reported: sink juggler failed: connection refused"))
    }

    @Test func sessionsReturnsOnlyProtocolOneRecords() async throws {
        let future = TestFixtures.statusJSON(bindingId: "future")
            .replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":2")
        let stub = try HooklinesinkerStub.make(stdout: TestFixtures.sessionsEnvelope([
            TestFixtures.statusJSON(bindingId: "current"),
            future
        ]))
        defer { stub.remove() }

        let sessions = try await stub.client.sessions()

        #expect(sessions.statuses.map(\.bindingId) == ["current"])
        #expect(sessions.skippedRecordCount == 1)
    }

    @Test func sessionsRejectsAnUnsupportedEnvelopeProtocol() async throws {
        let stub = try HooklinesinkerStub.make(stdout: #"{"protocol":2,"sessions":[],"problems":[]}"#)
        defer { stub.remove() }

        await #expect(throws: HooklinesinkerClientError.self) {
            try await stub.client.sessions()
        }
    }

    @Test func sessionsSurfacesACommandFailure() async throws {
        let stub = try HooklinesinkerStub.make(stderr: "state store unreadable", status: 3)
        defer { stub.remove() }

        await #expect(throws: HooklinesinkerClientError.self) {
            try await stub.client.sessions()
        }
    }

    @Test func outputIsCapturedInFullUpToTheCap() async throws {
        let payload = String(repeating: "x", count: 4096)
        let stub = try HooklinesinkerStub.make(stdout: payload)
        defer { stub.remove() }

        let result = await stub.client.installConsumer()

        #expect(result.standardOutput == payload)
    }
}
