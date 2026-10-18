import Foundation

/// Rows stay when the ledger reset fails: the next launch would hydrate them back from its records.
enum SessionReset {
    static func run(
        client: HooklinesinkerClient = .shared,
        sessionManager: SessionManager = .shared
    ) async throws {
        do {
            let removed = try await client.resetSessions()
            sessionManager.clearAllSessions()
            logInfo(.hooks, "Reset hooklinesinker sessions: removed \(removed) record(s)")
        } catch {
            logWarning(.hooks, "Session reset failed: \(error.localizedDescription)")
            throw error
        }
    }
}
