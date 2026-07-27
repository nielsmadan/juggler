import Foundation

enum HookEventMapper {
    enum MappedAction: Equatable {
        case updateState(SessionState)
        case removeSession
        case ignore
    }

    nonisolated static func map(event: String, agent: String = "claude-code") -> MappedAction {
        switch agent {
        case "opencode":
            mapOpenCode(event: event)
        case "codex":
            mapCodex(event: event)
        case "pi":
            mapPi(event: event)
        case "antigravity":
            mapAntigravity(event: event)
        default:
            mapClaudeCode(event: event)
        }
    }

    private nonisolated static func mapClaudeCode(event: String) -> MappedAction {
        switch event {
        case "SessionStart", "Stop", "StopFailure":
            .updateState(.idle)
        case "UserPromptSubmit", "PreToolUse", "PostToolUse",
             "PostToolUseFailure", "SubagentStart":
            .updateState(.working)
        // SubagentStop fires asynchronously after the main Stop event,
        // which would incorrectly overwrite the idle state back to working.
        case "SubagentStop":
            .ignore
        case "PermissionRequest":
            .updateState(.permission)
        case "PreCompact":
            .updateState(.compacting)
        case "SessionEnd":
            .removeSession
        default:
            .ignore
        }
    }

    private nonisolated static func mapCodex(event: String) -> MappedAction {
        switch event {
        case "SessionStart", "Stop":
            .updateState(.idle)
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostCompact":
            .updateState(.working)
        case "PermissionRequest":
            .updateState(.permission)
        case "PreCompact":
            .updateState(.compacting)
        default:
            .ignore
        }
    }

    private nonisolated static func mapPi(event: String) -> MappedAction {
        switch event {
        case "session_start", "agent_settled", "session_compact_idle":
            .updateState(.idle)
        case "agent_start", "session_compact_working":
            .updateState(.working)
        case "session_before_compact":
            .updateState(.compacting)
        case "session_shutdown":
            .removeSession
        default:
            .ignore
        }
    }

    private nonisolated static func mapAntigravity(event: String) -> MappedAction {
        switch event {
        case "Stop":
            .updateState(.idle)
        case "PreInvocation":
            .updateState(.working)
        default:
            .ignore
        }
    }

    private nonisolated static func mapOpenCode(event: String) -> MappedAction {
        switch event {
        case "session.created", "session.status.idle", "session.idle", "session.error":
            .updateState(.idle)
        case "session.status.busy", "session.status.retry":
            .updateState(.working)
        case "permission.asked":
            .updateState(.permission)
        case "session.compacted":
            .updateState(.compacting)
        case "session.deleted", "server.instance.disposed":
            .removeSession
        default:
            .ignore
        }
    }
}
