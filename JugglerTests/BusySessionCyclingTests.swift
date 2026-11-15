import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct BusySessionCyclingTests {
    @Test(arguments: [false, true], [false, true])
    func workingQueueHeadCyclesToFirstWaitingSession(autoAdvance: Bool, prioritized: Bool) {
        let restore = preserveDefaults(
            AppStorageKeys.queueOrderMode, AppStorageKeys.autoAdvanceOnBusy,
            AppStorageKeys.prioritizePermissionSessions
        )
        defer { restore() }
        UserDefaults.standard.set("fair", forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(autoAdvance, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.prioritizePermissionSessions)
        let manager = TestFixtures.isolatedSessionManager()
        var first = makeSession("first")
        var next = makeSession("next")
        first.disposition.isPrioritized = prioritized
        next.disposition.isPrioritized = prioritized
        manager.testSetSessions([first, next, makeSession("shelved", state: .backburner)])
        manager.addOrUpdateSession(
            agentSessionID: "late", terminalSessionID: "late",
            projectPath: "/test/late", state: .idle
        )
        manager.updateFocusedSession(terminalSessionID: "first")

        manager.updateSessionState(terminalSessionID: "first", state: .working)

        #expect(manager.cyclableSessions.map(\.id) == ["next", "late"])
        #expect(manager.cycleForward()?.id == "next")
        #expect(manager.cycleForward()?.id == "late")
    }

    @Test func staticQueueCyclesFromTheWorkingSessionsPosition() {
        let restore = preserveDefaults(AppStorageKeys.queueOrderMode, AppStorageKeys.autoAdvanceOnBusy)
        defer { restore() }
        UserDefaults.standard.set("static", forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("before"), makeSession("current"), makeSession("after")])
        manager.updateFocusedSession(terminalSessionID: "current")

        manager.updateSessionState(terminalSessionID: "current", state: .working)

        #expect(manager.cycleForward()?.id == "after")
    }
}
