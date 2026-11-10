import Foundation
@testable import Juggler
import Synchronization
import Testing

@Suite("Session disposition lifecycle", .serialized)
struct SessionDispositionLifecycleTests {
    private let key = AgentSessionIdentity(agent: "codex", agentSessionID: "conversation")
    private let shelvedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private var storedBackburner: BackburnerDisposition {
        BackburnerDisposition(wasAwaitingUser: true, backburneredAt: shelvedAt, turnsByBinding: ["binding": 4])
    }

    @discardableResult
    private func receive(
        _ manager: SessionManager,
        pane: String = "pane",
        conversation: String = "conversation",
        agent: String = "codex",
        state: SessionState = .idle,
        event: String? = "Stop",
        source: StatusSource = .live,
        observedAt: Date? = nil,
        turns: Int? = nil,
        bindingID: String = "binding"
    ) -> Bool {
        manager.addOrUpdateSession(
            agentSessionID: conversation, terminalSessionID: pane, agent: agent,
            projectPath: "/test", state: state, event: event, bindingID: bindingID, source: source,
            detailsChange: .replace(SessionDetails(turns: turns, reportedTurns: turns, observedAt: observedAt))
        )
    }

    @Test func identityTransitionsDistinguishMissingReplacementAndStaleEvents() {
        let transient = AgentSessionIdentity(agent: "codex", agentSessionID: "")
        let replacement = AgentSessionIdentity(agent: "codex", agentSessionID: "replacement")
        let differentAgent = AgentSessionIdentity(agent: "pi", agentSessionID: "conversation")
        #expect(SessionIdentityTransition.resolve(current: key, incoming: key, event: "Stop") == .unchanged)
        #expect(SessionIdentityTransition.resolve(current: key, incoming: transient, event: "Stop") == .unchanged)
        #expect(SessionIdentityTransition.resolve(current: transient, incoming: key, event: "Stop")
            == .filledMissing(previous: transient, current: key))
        #expect(SessionIdentityTransition.resolve(current: key, incoming: replacement, event: "SessionStart")
            == .replaced(previous: key, current: replacement))
        #expect(SessionIdentityTransition.resolve(current: key, incoming: differentAgent, event: "session_start")
            == .replaced(previous: key, current: differentAgent))
        #expect(SessionIdentityTransition.resolve(current: key, incoming: replacement, event: "Stop") == .rejected)
    }

    @Test func stableReplacementDropsOldDispositionAndProcessesTheIncomingState() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager, turns: 4)
        if let notification = manager.makeNotificationTarget(sessionID: "pane") {
            manager.recordLastNotification(notification)
        }
        manager.setSessionHidden(sessionID: "pane", isHidden: true)
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        manager.testSetLastActiveSessionID("pane")
        manager.beginActivation(targetSessionID: "pane")

        #expect(receive(manager, conversation: "new", state: .working, event: "UserPromptSubmit"))
        let row = manager.sessions[0]
        #expect(row.agentSessionID == "new")
        #expect(row.disposition == .empty)
        #expect(row.state == .working)
        #expect(row.turnCount == 1)
        #expect(row.details.turns == nil)
        #expect(manager.lastActiveSessionID == nil)
        #expect(manager.lastNotifiedSessionID == nil)
        #expect(manager.activationTarget == nil)
        #expect(manager.dispositionStore.disposition(for: key)
            == SessionDisposition(isHidden: true, backburner: storedBackburner))
    }

    @Test func replacementHydratesOnlyItsOwnDispositionAndRejectsOldLifecycleEvents() {
        let manager = TestFixtures.isolatedSessionManager()
        let replacement = AgentSessionIdentity(agent: "pi", agentSessionID: "conversation")
        manager.dispositionStore.setDisposition(.init(isHidden: true, backburner: storedBackburner), for: replacement)
        receive(manager)
        #expect(receive(manager, agent: "pi", state: .working, event: "session_start"))
        #expect(manager.sessions[0].agentSessionIdentity == replacement)
        #expect(manager.sessions[0].isHidden)
        #expect(manager.sessions[0].state == .backburner)
        #expect(receive(manager, state: .working, event: "PreToolUse") == false)
        #expect(manager.sessions[0].agentSessionIdentity == replacement)
        #expect(manager.sessions[0].disposition == .init(isHidden: true, backburner: storedBackburner))
    }

    @Test func untouchedTransientFieldsHydrateButExplicitFalseAndNilWin() {
        let store = SessionDispositionStore()
        store.setDisposition(.init(isHidden: true, backburner: storedBackburner), for: key)
        let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
        receive(manager, conversation: "")
        receive(manager)
        #expect(manager.sessions[0].disposition == .init(isHidden: true, backburner: storedBackburner))

        receive(manager, pane: "transient", conversation: "")
        manager.setSessionHidden(sessionID: "transient", isHidden: false)
        manager.reactivateSession(terminalSessionID: "transient")
        receive(manager, pane: "transient")
        #expect(manager.sessions.allSatisfy { $0.disposition == .empty && $0.state == .idle })
        #expect(store.dispositions.isEmpty)
    }

    @Test func transientOverridesReconcilePerField() {
        let store = SessionDispositionStore()
        store.setDisposition(.init(isHidden: true, backburner: storedBackburner), for: key)
        let manager = TestFixtures.isolatedSessionManager(dispositionStore: store)
        receive(manager, conversation: "")
        manager.setSessionHidden(sessionID: "pane", isHidden: false)
        receive(manager)
        #expect(manager.sessions[0].disposition == .init(isHidden: false, backburner: storedBackburner))

        receive(manager, pane: "other", conversation: "")
        manager.setSessionHidden(sessionID: "other", isHidden: true)
        manager.backburnerSession(terminalSessionID: "other", now: shelvedAt)
        #expect(store.dispositions.count == 1)
        receive(manager, pane: "other", conversation: "other")
        #expect(manager.sessions.first { $0.id == "other" }?.disposition == .init(
            isHidden: true,
            backburner: .init(wasAwaitingUser: true, backburneredAt: shelvedAt)
        ))
    }

    @Test func transientIntentDoesNotMigrateAcrossAnAgentChange() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager, conversation: "")
        manager.setSessionHidden(sessionID: "pane", isHidden: true)
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        receive(manager, agent: "pi", event: "session_start")
        #expect(manager.sessions[0].disposition == .empty)
        #expect(manager.sessions[0].state == .idle)
        #expect(manager.dispositionStore.dispositions.isEmpty)
    }

    @Test func duplicatesSynchronizeAndWriteOncePerDispositionChange() throws {
        let suite = "JugglerTests.DispositionCounting.\(UUID().uuidString)"
        let defaults = try #require(DispositionCountingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = TestFixtures.isolatedSessionManager(dispositionStore: SessionDispositionStore(defaults: defaults))
        receive(manager, turns: 4)
        receive(manager, pane: "duplicate", turns: 4)
        manager.setSessionHidden(sessionID: "pane", isHidden: true)
        #expect(defaults.dispositionWrites == 1)
        let allHidden = manager.sessions.allSatisfy(\.isHidden)
        #expect(allHidden)
        manager.setSessionHidden(sessionID: "duplicate", isHidden: true)
        #expect(defaults.dispositionWrites == 1)
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        #expect(defaults.dispositionWrites == 2)
        #expect(manager.sessions.allSatisfy {
            $0.disposition.backburner == storedBackburner && $0.state == .backburner
        })
        manager.reactivateSession(terminalSessionID: "duplicate")
        #expect(defaults.dispositionWrites == 3)
        #expect(manager.sessions.allSatisfy { $0.isHidden && $0.disposition.backburner == nil && $0.state == .idle })
    }

    @Test func duplicateReactivationTriggersAutomationOnce() {
        let previous = UserDefaults.standard.object(forKey: AppStorageKeys.autoRestartOnIdle)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.autoRestartOnIdle)
        defer { UserDefaults.standard.set(previous, forKey: AppStorageKeys.autoRestartOnIdle) }
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager)
        receive(manager, pane: "duplicate")
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        let notifications = Mutex<[String]>([])
        let observer = NotificationCenter.default.addObserver(forName: .shouldAutoRestart, object: nil, queue: nil) {
            if let sessionID = $0.userInfo?["sessionID"] as? String {
                notifications.withLock { $0.append(sessionID) }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        manager.reactivateSession(terminalSessionID: "pane")
        #expect(notifications.withLock { $0 } == ["pane"])
        #expect(manager.sessions.map(\.state) == [.idle, .idle])
    }

    @Test func removalAndGenericRowClearPreserveDurableDisposition() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager)
        manager.setSessionHidden(sessionID: "pane", isHidden: true)
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        manager.removeSession(sessionID: "pane")
        receive(manager, pane: "new-pane", source: .hydration)
        #expect(manager.sessions[0].isHidden)
        #expect(manager.sessions[0].state == .backburner)
        manager.clearAllSessions()
        #expect(manager.dispositionStore.disposition(for: key).isHidden)
        #expect(manager.dispositionStore.disposition(for: key).backburner?.backburneredAt == shelvedAt)
    }

    @Test func hydrationRestoresMetadataAndDoesNotCountTurns() {
        let defaults = TestDefaults.fresh()
        let store = SessionDispositionStore(defaults: defaults)
        store.setDisposition(.init(isHidden: true, backburner: storedBackburner), for: key)
        let manager = TestFixtures.isolatedSessionManager(dispositionStore: SessionDispositionStore(defaults: defaults))
        receive(manager, state: .working, event: "UserPromptSubmit", source: .hydration,
                observedAt: shelvedAt, turns: 4)
        #expect(manager.sessions[0].disposition == .init(isHidden: true, backburner: storedBackburner))
        #expect(manager.sessions[0].state == .backburner)
        #expect(manager.sessions[0].wasAwaitingUserBeforeBackburner)
        #expect(manager.sessions[0].turnCount == 0)
    }

    @Test(arguments: ["UserPromptSubmit", "PreToolUse", "Stop"])
    func ambiguousHydrationDoesNotWake(event: String) {
        let manager = TestFixtures.isolatedSessionManager()
        manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: storedBackburner), for: key)
        receive(manager, state: .working, event: event, source: .hydration)
        #expect(manager.sessions[0].state == .backburner)
        receive(manager, state: .working, event: event, source: .hydration,
                observedAt: shelvedAt.addingTimeInterval(-1), turns: 4)
        #expect(manager.sessions[0].state == .backburner)
    }

    @Test func newerHydratedPromptWakesAndPersistsTheClearForEveryDuplicate() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.dispositionStore.setDisposition(.init(isHidden: true, backburner: storedBackburner), for: key)
        receive(manager, source: .hydration)
        receive(manager, pane: "duplicate", source: .hydration)
        receive(manager, state: .working, event: "UserPromptSubmit", source: .hydration,
                observedAt: shelvedAt.addingTimeInterval(1), turns: 4)
        #expect(manager.sessions.allSatisfy { $0.isHidden && $0.state == .working && $0.disposition.backburner == nil })
        #expect(manager.dispositionStore.disposition(for: key) == .init(isHidden: true))
    }

    @Test func newerHydratedCursorPromptWakesWithoutATurnBaseline() {
        let manager = TestFixtures.isolatedSessionManager()
        let identity = AgentSessionIdentity(agent: "cursor", agentSessionID: "conversation")
        let backburner = BackburnerDisposition(wasAwaitingUser: false, backburneredAt: shelvedAt)
        manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: backburner), for: identity)
        receive(manager, agent: "cursor", state: .working, event: "beforeSubmitPrompt", source: .hydration,
                observedAt: shelvedAt.addingTimeInterval(1))
        #expect(manager.sessions[0].state == .working)
        #expect(manager.dispositionStore.dispositions.isEmpty)
    }

    @Test func increasedExternalTurnsProveOfflineWakeEvenAfterThePromptHasCompleted() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: storedBackburner), for: key)
        receive(manager, event: "Stop", source: .hydration, observedAt: shelvedAt.addingTimeInterval(1), turns: 5)
        #expect(manager.sessions[0].state == .idle)
        #expect(manager.dispositionStore.dispositions.isEmpty)
    }

    @Test func backburnerPreservesEachDuplicateBindingTurnCount() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager, turns: 4)
        receive(manager, pane: "duplicate", turns: 8, bindingID: "other-binding")
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        #expect(manager.dispositionStore.disposition(for: key).backburner?.turnsByBinding
            == ["binding": 4, "other-binding": 8])
        receive(manager, pane: "duplicate", source: .hydration, observedAt: shelvedAt.addingTimeInterval(1),
                turns: 8, bindingID: "other-binding")
        #expect(manager.sessions.allSatisfy { $0.state == .backburner })
    }

    @Test func missingTurnBaselineCannotProveWakeFromAnExternalCountAlone() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager)
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        receive(manager, event: "PreToolUse", source: .hydration,
                observedAt: shelvedAt.addingTimeInterval(1), turns: 100)
        #expect(manager.sessions[0].state == .backburner)
        #expect(manager.dispositionStore.disposition(for: key).backburner?.turnsByBinding == [:])
    }

    @Test func newerWorkingSnapshotAloneDoesNotWakeClaudeOrBusyOriginAntigravity() {
        for agent in ["claude-code", "antigravity"] {
            let manager = TestFixtures.isolatedSessionManager()
            let identity = AgentSessionIdentity(agent: agent, agentSessionID: "conversation")
            let backburner = BackburnerDisposition(
                wasAwaitingUser: agent != "antigravity", backburneredAt: shelvedAt
            )
            manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: backburner), for: identity)
            receive(manager, agent: agent, state: .working, event: "PreInvocation", source: .hydration,
                    observedAt: shelvedAt.addingTimeInterval(1))
            #expect(manager.sessions[0].state == .backburner)
        }
    }

    @Test func antigravityHydrationRequiresNewerWorkingEvidenceAndAwaitingUserOrigin() {
        let manager = TestFixtures.isolatedSessionManager()
        let identity = AgentSessionIdentity(agent: "antigravity", agentSessionID: "conversation")
        manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: storedBackburner), for: identity)
        receive(manager, agent: "antigravity", state: .working, event: "PreInvocation", source: .hydration,
                observedAt: shelvedAt)
        #expect(manager.sessions[0].state == .backburner)
        receive(manager, agent: "antigravity", state: .working, event: "PreInvocation", source: .hydration,
                observedAt: shelvedAt.addingTimeInterval(1))
        #expect(manager.sessions[0].state == .working)
        #expect(manager.dispositionStore.dispositions.isEmpty)
    }

    @Test func olderSnapshotCannotBorrowANewerDetailsTimestampAsWakeEvidence() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: storedBackburner), for: key)
        receive(manager, source: .hydration, observedAt: shelvedAt.addingTimeInterval(10))
        receive(manager, state: .working, event: "UserPromptSubmit", source: .hydration,
                observedAt: shelvedAt.addingTimeInterval(-10))
        #expect(manager.sessions[0].details.observedAt == shelvedAt.addingTimeInterval(10))
        #expect(manager.sessions[0].state == .backburner)
    }

    @Test func livePromptWakesTransientAndStableDuplicatesWithoutTimestamps() {
        let manager = TestFixtures.isolatedSessionManager()
        receive(manager, conversation: "")
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        receive(manager, conversation: "", state: .working, event: "UserPromptSubmit")
        #expect(manager.sessions[0].state == .working)
        manager.dispositionStore.setDisposition(.init(isHidden: false, backburner: storedBackburner), for: key)
        receive(manager)
        #expect(manager.sessions[0].disposition == .empty)
        receive(manager, pane: "duplicate")
        manager.backburnerSession(terminalSessionID: "pane", now: shelvedAt)
        receive(manager, state: .working, event: "UserPromptSubmit")
        #expect(manager.sessions.allSatisfy { $0.state == .working && $0.disposition.backburner == nil })
        #expect(manager.dispositionStore.dispositions.isEmpty)
    }
}
