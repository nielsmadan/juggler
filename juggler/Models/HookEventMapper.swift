import Foundation

/// Maps raw hook event names from coding agents to Juggler session states
enum HookEventMapper {
    /// The action to take based on a hook event
    enum MappedAction: Equatable {
        case updateState(SessionState)
        case removeSession
        case ignore
    }

    /// Maps a Claude Code hook event name to a Juggler action
    /// - Parameter event: The raw event name (e.g., "PreToolUse", "Stop")
    /// - Returns: The action to take
    nonisolated static func map(event: String) -> MappedAction {
        switch event {
        // Session lifecycle - idle states
        case "SessionStart", "Stop":
            .updateState(.idle)

        // Active work - working states
        case "UserPromptSubmit", "PreToolUse", "PostToolUse",
             "PostToolUseFailure", "SubagentStart":
            .updateState(.working)

        // SubagentStop is ignored - it fires asynchronously AFTER the main Stop event,
        // which would incorrectly overwrite the idle state. See docs/tech/hooks.md for details.
        case "SubagentStop":
            .ignore

        // Permission required
        case "PermissionRequest":
            .updateState(.permission)

        // Context compaction
        case "PreCompact":
            .updateState(.compacting)

        // Session termination
        case "SessionEnd":
            .removeSession

        // Unknown events - ignore gracefully
        default:
            .ignore
        }
    }
}
