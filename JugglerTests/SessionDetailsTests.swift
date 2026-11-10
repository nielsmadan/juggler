import Foundation
@testable import Juggler
import Testing

private func detailStatus(
    bindingId: String = "b-1",
    event: String = "PreToolUse",
    phase: String = "working",
    observedAt: String = "2026-09-04T12:00:00Z",
    sessionID: String = "native",
    sessionExtras: String = "",
    activity: String? = nil
) -> String {
    TestFixtures.statusJSON(
        bindingId: bindingId,
        agent: "codex",
        event: event,
        phase: phase,
        observedAt: observedAt,
        sessionID: sessionID,
        terminalSessionID: "s1",
        sessionExtras: sessionExtras,
        activity: activity
    )
}

@Suite("Status details decoding")
struct StatusDetailsDecodingTests {
    private func decode(_ body: String) throws -> HooklinesinkerStatus {
        try JSONDecoder().decode(HooklinesinkerStatus.self, from: Data(body.utf8))
    }

    @Test func decodesAllDetailFields() throws {
        let status = try decode(detailStatus(
            sessionExtras: ",\"title\":\"Fix bug\",\"model\":\"gpt-5.5\",\"effort\":\"high\","
                + "\"permissionMode\":\"plan\"",
            activity: "{\"tool\":\"Bash\",\"problem\":\"rate_limit_error\",\"subagents\":2,"
                + "\"contextPercent\":41,\"turns\":3}"
        ))
        #expect(status.session.title == "Fix bug")
        #expect(status.session.model == "gpt-5.5")
        #expect(status.session.effort == "high")
        #expect(status.session.permissionMode == "plan")
        #expect(status.activity == HooklinesinkerStatus.Activity(
            tool: "Bash", problem: "rate_limit_error", subagents: 2, contextPercent: 41, turns: 3
        ))
        #expect(status.sessionDetails.turns == 3)
        #expect(status.sessionDetails.reportedTurns == 3)
        #expect(status.sessionDetails.processStartedAt == Date(timeIntervalSince1970: 1_788_519_600))
    }

    @Test func decodesWithoutActivity() throws {
        let status = try decode(detailStatus())
        #expect(status.activity == nil)
        #expect(status.session.model == nil)
        #expect(status.sessionDetails.subagentCount == 0)
        #expect(status.sessionDetails.turns == nil)
        #expect(status.sessionDetails.reportedTurns == nil)
    }

    @Test(arguments: ["{\"tool\":\"Bash\"}", "{\"turns\":\"4\"}"])
    func missingOrWrongTypedTurnsDecodeAsZero(activity: String) throws {
        let status = try decode(detailStatus(activity: activity))
        #expect(status.activity?.turns == 0)
        #expect(status.sessionDetails.turns == 0)
        #expect(status.activity?.reportedTurns == nil)
        #expect(status.sessionDetails.reportedTurns == nil)
    }

    @Test(arguments: [-1, 0, 4])
    func onlyNonnegativeIntegerCountsAreEvidence(turns: Int) throws {
        let status = try decode(detailStatus(activity: "{\"turns\":\(turns)}"))
        #expect(status.activity?.turns == turns)
        #expect(status.sessionDetails.reportedTurns == (turns >= 0 ? turns : nil))
    }

    @Test func stringContextPercentDegradesToNil() throws {
        let status = try decode(detailStatus(activity: "{\"tool\":\"Bash\",\"contextPercent\":\"41\"}"))
        #expect(status.activity?.contextPercent == nil)
        #expect(status.activity?.tool == "Bash")
        #expect(status.phase == .working)
    }

    @Test(arguments: [(150, 100), (-5, 0)])
    func contextPercentIsClamped(raw: Int, clamped: Int) throws {
        let status = try decode(detailStatus(activity: "{\"contextPercent\":\(raw)}"))
        #expect(status.activity?.contextPercent == clamped)
    }

    @Test func wrongTypedSessionDetailDegradesToNil() throws {
        let status = try decode(detailStatus(sessionExtras: ",\"model\":7,\"title\":\"T\""))
        #expect(status.session.model == nil)
        #expect(status.session.title == "T")
    }
}

@Suite("Session details", .serialized)
struct SessionDetailsApplicationTests {
    @Test @MainActor func detailsReachTheSession() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(
            sessionExtras: ",\"model\":\"gpt-5.5\"", activity: "{\"tool\":\"Bash\",\"subagents\":1}"
        ))
        #expect(manager.sessions[0].details.model == "gpt-5.5")
        #expect(manager.sessions[0].details.currentTool == "Bash")
        #expect(manager.sessions[0].details.subagentCount == 1)
    }

    @Test @MainActor func detailsApplyToBackburnerRowWithoutChangingState() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(phase: "idle"))
        manager.updateSessionState(terminalSessionID: "s1", state: .backburner)

        await server.handleStatusForTesting(detailStatus(
            observedAt: "2026-09-04T12:00:05Z", sessionExtras: ",\"model\":\"m2\""
        ))
        #expect(manager.sessions[0].state == .backburner)
        #expect(manager.sessions[0].details.model == "m2")
    }

    @Test @MainActor func olderObservedAtDoesNotOverwriteNewerDetails() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(
            observedAt: "2026-09-04T12:00:10Z", sessionExtras: ",\"model\":\"new\""
        ))
        await server.handleStatusForTesting(detailStatus(
            observedAt: "2026-09-04T12:00:00Z", sessionExtras: ",\"model\":\"old\""
        ))
        #expect(manager.sessions[0].details.model == "new")
    }

    @Test @MainActor func emptyAgentSessionIDLeavesDetailsUntouched() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(sessionExtras: ",\"model\":\"m1\""))
        await server.handleStatusForTesting(detailStatus(
            event: "Stop",
            phase: "idle",
            observedAt: "2026-09-04T12:00:09Z",
            sessionID: "",
            sessionExtras: ",\"model\":\"m2\""
        ))
        #expect(manager.sessions[0].state == .idle)
        #expect(manager.sessions[0].details.model == "m1")
    }
}

@Suite("SessionDetails merging")
struct SessionDetailsMergingTests {
    @Test func replacementWithoutProcessStartKeepsTheKnownStart() {
        let started = Date(timeIntervalSince1970: 1000)
        let current = SessionDetails(model: "old", processStartedAt: started)
        let replaced = current.replaced(by: SessionDetails(model: "new"))
        #expect(replaced.model == "new")
        #expect(replaced.processStartedAt == started)
    }

    @Test @MainActor func antigravityEmptyModelKeepsTheKnownModel() {
        let current = SessionDetails(model: "gemini-3")
        let updated = HookEventMapper.antigravityDetails(
            current, event: "PreInvocation", model: "", terminationReason: nil
        )
        #expect(updated.model == "gemini-3")
    }
}

@Suite("Turn counting")
struct TurnCountingTests {
    @Test func idleToWorkingIsATurn() {
        #expect(SessionManager.isNewTurn(old: .idle, new: .working, event: "UserPromptSubmit"))
    }

    @Test func idleToWorkingWithoutATurnStartEventIsNotATurn() {
        #expect(!SessionManager.isNewTurn(old: .idle, new: .working, event: "PostToolUse"))
        #expect(!SessionManager.isNewTurn(old: .idle, new: .working, event: "child:UserPromptSubmit"))
    }

    @Test func rowCreatedWorkingByATurnStartIsATurn() {
        #expect(SessionManager.isNewTurn(old: nil, new: .working, event: "PreInvocation"))
        #expect(!SessionManager.isNewTurn(old: nil, new: .idle, event: "SessionStart"))
    }

    @Test func permissionToWorkingIsNotATurn() {
        #expect(!SessionManager.isNewTurn(old: .permission, new: .working, event: "PostToolUse"))
    }

    @Test func compactingTransitionsAreNotTurns() {
        #expect(!SessionManager.isNewTurn(old: .idle, new: .compacting, event: "PreCompact"))
        #expect(!SessionManager.isNewTurn(old: .compacting, new: .idle, event: "Stop"))
    }

    @Test func backburnerUserPromptSubmitIsATurn() {
        #expect(SessionManager.isNewTurn(old: .backburner, new: .working, event: "UserPromptSubmit"))
        #expect(!SessionManager.isNewTurn(old: .backburner, new: .working, event: "PreToolUse"))
    }

    @Test func cursorPromptSubmitIsATurnFromIdleAndBackburner() {
        #expect(SessionManager.isNewTurn(old: .idle, new: .working, event: "beforeSubmitPrompt"))
        #expect(SessionManager.isNewTurn(old: .backburner, new: .working, event: "beforeSubmitPrompt"))
        #expect(!SessionManager.isNewTurn(old: .backburner, new: .working, event: "PreInvocation"))
    }

    @Test @MainActor func workingPermissionWorkingCountsOneTurn() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(event: "SessionStart", phase: "idle"))
        await server.handleStatusForTesting(detailStatus(event: "UserPromptSubmit", phase: "working"))
        await server.handleStatusForTesting(detailStatus(event: "PermissionRequest", phase: "permission"))
        await server.handleStatusForTesting(detailStatus(event: "PostToolUse", phase: "working"))
        #expect(manager.sessions[0].turnCount == 1)
    }

    @Test @MainActor func answeredQuestionIsNotATurn() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(event: "PreToolUse", phase: "idle"))
        await server.handleStatusForTesting(detailStatus(event: "PostToolUse", phase: "working"))
        #expect(manager.sessions[0].state == .working)
        #expect(manager.sessions[0].turnCount == 0)
    }

    @Test @MainActor func hydrationDoesNotCountATurn() async throws {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(phase: "idle"))
        let working = try JSONDecoder().decode(
            HooklinesinkerStatus.self,
            from: Data(detailStatus(bindingId: "b-2", event: "UserPromptSubmit", phase: "working").utf8)
        )
        await server.hydrate([working])
        #expect(manager.sessions[0].state == .working)
        #expect(manager.sessions[0].turnCount == 0)
    }

    @Test @MainActor func backburnerUserPromptSubmitCountsATurn() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(phase: "idle"))
        manager.updateSessionState(terminalSessionID: "s1", state: .backburner)
        await server.handleStatusForTesting(detailStatus(event: "UserPromptSubmit", phase: "working"))
        #expect(manager.sessions[0].turnCount == 1)
    }

    @Test @MainActor func hooklinesinkerTurnsReplaceJugglersCount() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await server.handleStatusForTesting(detailStatus(
            event: "UserPromptSubmit", phase: "working", activity: "{\"subagents\":0,\"turns\":4}"
        ))
        let session = manager.sessions[0]
        #expect(session.turnCount == 1)
        #expect(session.details.turns == 4)
        #expect(RowSlot.turns.value(for: session, now: Date(), abbreviateHome: false) == "4 turns")
    }
}

@Suite("Antigravity details", .serialized)
struct AntigravityDetailsTests {
    private func body(event: String, hookInput: String) -> String {
        """
        {"agent":"antigravity","event":"\(event)","hookInput":{"session_id":"c1"\(hookInput)},\
        "terminal":{"sessionId":"s1","cwd":"/p","terminalType":"iterm2"}}
        """
    }

    private func post(_ server: HookServer, _ body: String) async {
        _ = await server.processRequest(HTTPRequest(method: "POST", path: "/hook", body: body))
    }

    @Test @MainActor func modelNameSetsModel() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await post(server, body(event: "PreInvocation", hookInput: ",\"model\":\"gemini-3\""))
        #expect(manager.sessions[0].details.model == "gemini-3")
    }

    @Test @MainActor func nonModelStopReasonSetsProblemAndPreInvocationClearsIt() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await post(server, body(event: "PreInvocation", hookInput: ""))
        await post(server, body(event: "Stop", hookInput: ",\"termination_reason\":\"max_steps_exceeded\""))
        #expect(manager.sessions[0].details.lastProblem == "max_steps_exceeded")
        await post(server, body(event: "PreInvocation", hookInput: ""))
        #expect(manager.sessions[0].details.lastProblem == nil)
    }

    @Test @MainActor func modelStopLeavesProblemEmpty() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await post(server, body(event: "Stop", hookInput: ",\"termination_reason\":\"model_stop\""))
        #expect(manager.sessions[0].details.lastProblem == nil)
        #expect(manager.sessions[0].state == .idle)
    }

    @Test @MainActor func firstTurnOfARowCreatedWorkingIsCounted() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await post(server, body(event: "PreInvocation", hookInput: ""))
        #expect(manager.sessions[0].turnCount == 1)
        await post(server, body(event: "Stop", hookInput: ""))
        await post(server, body(event: "PreInvocation", hookInput: ""))
        #expect(manager.sessions[0].turnCount == 2)
        #expect(RowSlot.turns.value(for: manager.sessions[0], now: Date(), abbreviateHome: false) == "2 turns")
    }

    @Test @MainActor func nonStringModelStillRecordsTheEvent() async {
        let manager = SessionManager()
        let server = HookServer(sessionManager: manager)
        await post(server, body(event: "PreInvocation", hookInput: ",\"model\":42"))
        #expect(manager.sessions[0].state == .working)
        #expect(manager.sessions[0].details.model == nil)
    }
}
