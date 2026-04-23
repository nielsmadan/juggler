import Foundation
@testable import Juggler

/// Shared helper for constructing a minimal `Session` in tests.
/// The `id` string is used for both `claudeSessionID` and `terminalSessionID`,
/// and `projectPath` is derived as `/test/{id}` so sessions are easy to spot in failures.
func makeSession(_ id: String, state: SessionState = .idle) -> Session {
    Session(
        claudeSessionID: id,
        terminalSessionID: id,
        terminalType: .iterm2,
        agent: "claude-code",
        projectPath: "/test/\(id)",
        terminalTabName: nil,
        terminalWindowName: nil,
        customName: nil,
        state: state,
        startedAt: Date()
    )
}
