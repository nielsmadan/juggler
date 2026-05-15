@testable import Juggler
import Testing

@Suite("HookEventMapper")
struct HookEventMapperTests {
    // MARK: - Idle State Mappings

    @Test func sessionStart_mapsToIdle() {
        let action = HookEventMapper.map(event: "SessionStart")
        #expect(action == .updateState(.idle))
    }

    @Test func stop_mapsToIdle() {
        let action = HookEventMapper.map(event: "Stop")
        #expect(action == .updateState(.idle))
    }

    // MARK: - Working State Mappings

    @Test func userPromptSubmit_mapsToWorking() {
        let action = HookEventMapper.map(event: "UserPromptSubmit")
        #expect(action == .updateState(.working))
    }

    @Test func preToolUse_mapsToWorking() {
        let action = HookEventMapper.map(event: "PreToolUse")
        #expect(action == .updateState(.working))
    }

    @Test func postToolUse_mapsToWorking() {
        let action = HookEventMapper.map(event: "PostToolUse")
        #expect(action == .updateState(.working))
    }

    @Test func postToolUseFailure_mapsToWorking() {
        let action = HookEventMapper.map(event: "PostToolUseFailure")
        #expect(action == .updateState(.working))
    }

    @Test func subagentStart_mapsToWorking() {
        let action = HookEventMapper.map(event: "SubagentStart")
        #expect(action == .updateState(.working))
    }

    // SubagentStop is ignored because it fires asynchronously AFTER Stop,
    // which would incorrectly overwrite the idle state. See docs/tech/hooks.md for details.
    @Test func subagentStop_mapsToIgnore() {
        let action = HookEventMapper.map(event: "SubagentStop")
        #expect(action == .ignore)
    }

    // MARK: - Permission State Mapping

    @Test func permissionRequest_mapsToPermission() {
        let action = HookEventMapper.map(event: "PermissionRequest")
        #expect(action == .updateState(.permission))
    }

    // MARK: - Compacting State Mapping

    @Test func preCompact_mapsToCompacting() {
        let action = HookEventMapper.map(event: "PreCompact")
        #expect(action == .updateState(.compacting))
    }

    // MARK: - Session Removal

    @Test func sessionEnd_mapsToRemoveSession() {
        let action = HookEventMapper.map(event: "SessionEnd")
        #expect(action == .removeSession)
    }

    // MARK: - Unknown Events

    @Test func unknownEvent_mapsToIgnore() {
        let action = HookEventMapper.map(event: "SomeFutureEvent")
        #expect(action == .ignore)
    }

    @Test func emptyEvent_mapsToIgnore() {
        let action = HookEventMapper.map(event: "")
        #expect(action == .ignore)
    }

    @Test func lowercaseEvent_mapsToIgnore() {
        // Events are case-sensitive
        let action = HookEventMapper.map(event: "sessionstart")
        #expect(action == .ignore)
    }

    // MARK: - Codex Mappings

    @Test func codex_sessionStart_mapsToIdle() {
        let action = HookEventMapper.map(event: "SessionStart", agent: "codex")
        #expect(action == .updateState(.idle))
    }

    @Test func codex_stop_mapsToIdle() {
        let action = HookEventMapper.map(event: "Stop", agent: "codex")
        #expect(action == .updateState(.idle))
    }

    @Test func codex_userPromptSubmit_mapsToWorking() {
        let action = HookEventMapper.map(event: "UserPromptSubmit", agent: "codex")
        #expect(action == .updateState(.working))
    }

    @Test func codex_preToolUse_mapsToWorking() {
        let action = HookEventMapper.map(event: "PreToolUse", agent: "codex")
        #expect(action == .updateState(.working))
    }

    @Test func codex_postToolUse_mapsToWorking() {
        let action = HookEventMapper.map(event: "PostToolUse", agent: "codex")
        #expect(action == .updateState(.working))
    }

    @Test func codex_permissionRequest_mapsToPermission() {
        let action = HookEventMapper.map(event: "PermissionRequest", agent: "codex")
        #expect(action == .updateState(.permission))
    }

    // Codex does not emit a session-end event. Pin this so a future SessionEnd handler
    // isn't added by accident.
    @Test func codex_sessionEnd_mapsToIgnore() {
        let action = HookEventMapper.map(event: "SessionEnd", agent: "codex")
        #expect(action == .ignore)
    }

    @Test func codex_preCompact_mapsToCompacting() {
        let action = HookEventMapper.map(event: "PreCompact", agent: "codex")
        #expect(action == .updateState(.compacting))
    }

    // PostCompact fires when compaction finishes and the agent resumes its turn.
    @Test func codex_postCompact_mapsToWorking() {
        let action = HookEventMapper.map(event: "PostCompact", agent: "codex")
        #expect(action == .updateState(.working))
    }

    @Test func codex_unknownEvent_mapsToIgnore() {
        let action = HookEventMapper.map(event: "SomeFutureEvent", agent: "codex")
        #expect(action == .ignore)
    }

    // mapCodex is case-sensitive (exact-string switch). Pin that a lowercase event is ignored.
    @Test func codex_lowercaseEvent_mapsToIgnore() {
        let action = HookEventMapper.map(event: "sessionstart", agent: "codex")
        #expect(action == .ignore)
    }
}
