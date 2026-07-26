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
        // PostCompact fires when compaction finishes and the agent resumes its turn.
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
        // Idle sources: session_start (fires at launch and on new/resume/reload/fork),
        // agent_settled (turn finished), session_compact_idle (a manual /compact completed).
        case "session_start", "agent_settled", "session_compact_idle":
            .updateState(.idle)
        // session_compact_working: a threshold/overflow compaction resumes the turn.
        case "agent_start", "session_compact_working":
            .updateState(.working)
        case "session_before_compact":
            .updateState(.compacting)
        // Pi has no native permission event, so .permission is never produced.
        case "session_shutdown":
            .removeSession
        default:
            .ignore
        }
    }

    private nonisolated static func mapAntigravity(event: String) -> MappedAction {
        switch event {
        // Stop fires when the execution loop terminates (turn done → waiting for user).
        case "Stop":
            .updateState(.idle)
        // PreInvocation fires before each model call; the session first appears here as working.
        case "PreInvocation":
            .updateState(.working)
        // Antigravity has no permission, compaction, or session-end event, so those actions
        // are never produced. Sessions are removed via terminal-bridge cleanup.
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
