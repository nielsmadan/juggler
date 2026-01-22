@testable import Juggler
import Testing

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
}
