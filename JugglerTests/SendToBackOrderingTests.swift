import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct SendToBackOrderingTests {
    @Test(arguments: [(QueueOrderMode.fair, false), (.fair, true), (.prio, false), (.prio, true)],
          [SessionState.working, .compacting, .backburner])
    func sendToBackPassesEveryWaitingSession(
        configuration: (mode: QueueOrderMode, prioritized: Bool), interveningState: SessionState
    ) throws {
        let restore = try preservePersistentDefaults(
            AppStorageKeys.queueOrderMode,
            AppStorageKeys.prioritizePermissionSessions
        )
        defer { restore() }
        UserDefaults.standard.set(configuration.mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.prioritizePermissionSessions)
        let manager = TestFixtures.isolatedSessionManager()
        var target = makeSession("target")
        target.disposition.isPrioritized = configuration.prioritized
        manager.testSetSessions([
            target,
            makeSession("intervening", state: interveningState),
            makeSession("plain", state: .permission)
        ])

        #expect(manager.sendToBackOfQueue(sessionID: "target")?.id == "plain")

        #expect(manager.cyclableSessions.map(\.id) == ["plain", "target"])
        #expect(manager.sessions.first { $0.id == "target" }?.isPrioritized == configuration.prioritized)
        #expect(manager.sendToBackOfQueue(sessionID: "target")?.id == "plain")
        #expect(manager.cyclableSessions.map(\.id) == ["plain", "target"])
    }

    @Test(arguments: [SessionState.idle, .permission])
    func permissionFirstKeepsSendToBackWithinItsWaitingGroup(state: SessionState) throws {
        let restore = try preservePersistentDefaults(
            AppStorageKeys.queueOrderMode,
            AppStorageKeys.prioritizePermissionSessions
        )
        defer { restore() }
        UserDefaults.standard.set("fair", forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.prioritizePermissionSessions)
        let manager = TestFixtures.isolatedSessionManager()
        let permission = makeSession("permission", state: .permission)
        let idle = makeSession("idle")
        let target = makeSession("target", state: state)
        let busy = makeSession("busy", state: .working)
        manager.testSetSessions(
            state == .permission ? [target, busy, permission, idle] : [permission, target, busy, idle]
        )

        #expect(manager.moveSessionToBackOfQueue(sessionID: "target"))

        let expected = state == .permission ? ["permission", "target", "idle"] : ["permission", "idle", "target"]
        #expect(manager.cyclableSessions.map(\.id) == expected)
    }

    @Test(arguments: [QueueOrderMode.fair, .prio])
    func permissionSessionPassesIdleWaiterWhenPermissionFirstIsOff(mode: QueueOrderMode) throws {
        let restore = try preservePersistentDefaults(
            AppStorageKeys.queueOrderMode, AppStorageKeys.prioritizePermissionSessions
        )
        defer { restore() }
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.prioritizePermissionSessions)
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([
            makeSession("A", state: .permission), makeSession("busy", state: .working), makeSession("B")
        ])

        #expect(manager.moveSessionToBackOfQueue(sessionID: "A"))

        #expect(manager.cyclableSessions.map(\.id) == ["B", "A"])
    }

    @Test func hiddenTailDoesNotMoveTheOnlyWaiterBehindALaterCompletion() throws {
        let restore = try preservePersistentDefaults(
            AppStorageKeys.queueOrderMode, AppStorageKeys.prioritizePermissionSessions,
            AppStorageKeys.autoAdvanceOnBusy, AppStorageKeys.autoRestartOnIdle
        )
        defer { restore() }
        UserDefaults.standard.set("fair", forKey: AppStorageKeys.queueOrderMode)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.prioritizePermissionSessions)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoAdvanceOnBusy)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.autoRestartOnIdle)
        let manager = TestFixtures.isolatedSessionManager()
        for (name, state, event) in [
            ("A", SessionState.idle, "SessionStart"), ("X", .working, "UserPromptSubmit"),
            ("Y", .working, "UserPromptSubmit"), ("H", .idle, "SessionStart")
        ] {
            try #require(manager.addOrUpdateSession(
                agentSessionID: name, terminalSessionID: name, projectPath: "/test/\(name)",
                state: state, event: event, source: .live
            ))
        }
        manager.toggleSessionHidden(sessionID: "H")
        try #require(manager.cyclableSessions.map(\.id) == ["A"])
        try #require(manager.moveSessionToBackOfQueue(sessionID: "A"))

        try #require(manager.addOrUpdateSession(
            agentSessionID: "Y", terminalSessionID: "Y", projectPath: "/test/Y",
            state: .idle, event: "Stop", source: .live
        ))

        #expect(manager.cyclableSessions.map(\.id) == ["A", "Y"])
    }
}
