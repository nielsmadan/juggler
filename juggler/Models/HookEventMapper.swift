import Foundation

/// Maps raw hook event names from coding agents to Juggler session states
enum HookEventMapper {
    /// The action to take based on a hook event
    enum MappedAction: Equatable {
        case updateState(SessionState)
        case removeSession
        case ignore
    }

    /// Maps a hook event name to a Juggler action, dispatching by agent
    nonisolated static func map(event: String, agent: String = "claude-code") -> MappedAction {
        switch agent {
        case "opencode":
            mapOpenCode(event: event)
        default:
            mapClaudeCode(event: event)
        }
    }

    private nonisolated static func mapClaudeCode(event: String) -> MappedAction {
        switch event {
        case "SessionStart", "Stop":
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

    private nonisolated static func mapOpenCode(event: String) -> MappedAction {
        switch event {
        case "session.created", "session.status.idle":
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
