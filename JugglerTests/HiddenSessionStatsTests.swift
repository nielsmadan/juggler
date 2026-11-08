import Foundation
@testable import Juggler
import Testing

@Suite(.serialized)
@MainActor
struct HiddenSessionStatsTests {
    @Test func summaryCountsAllTrackedRowsAndBothBusyStates() {
        let states: [SessionState] = [.idle, .permission, .working, .compacting, .backburner]
        let sessions = [false, true].flatMap { hidden in
            states.enumerated().map { index, state in
                var session = makeSession("\(hidden)-\(index)", state: state)
                session.disposition.isHidden = hidden
                return session
            }
        }
        let summary = SessionStatsSummary(sessions: sessions)
        #expect(summary.workingCount == 4)
        #expect(summary.totalCount == 10)
        #expect(summary.hiddenCount == 5)
        #expect(summary.displayText == "4/10 busy, 5 hidden")
        #expect(SessionStatsSummary(sessions: []).displayText == "0/0 busy, 0 hidden")
    }

    @Test func showingHiddenDoesNotChangeStatsOrWorkingIntervals() {
        let manager = TestFixtures.isolatedSessionManager()
        var hidden = makeSession("hidden", state: .working)
        hidden.disposition.isHidden = true
        hidden.busyTimeToday = 20
        hidden.lastBecameWorking = Date(timeIntervalSince1970: 100)
        manager.testSetSessions([hidden, makeSession("visible")])
        let summary = SessionStatsSummary(sessions: manager.sessions)
        #expect(summary.displayText == "1/2 busy, 1 hidden")
        #expect(manager.listedSessions.count == 1)
        manager.showsHiddenSessions = true
        #expect(manager.listedSessions.count == 2)
        #expect(SessionStatsSummary(sessions: manager.sessions) == summary)
        #expect(manager.sessions.first?.busyTimeToday == 20)
        #expect(manager.sessions.first?.lastBecameWorking == Date(timeIntervalSince1970: 100))
    }

    @Test func duplicateConversationRowsEachContributeToSummary() {
        var first = makeSession("first", state: .compacting)
        first.disposition.isHidden = true
        var second = makeSession("second", state: .compacting)
        second.agentSessionID = first.agentSessionID
        second.disposition = first.disposition
        #expect(SessionStatsSummary(sessions: [first, second]).displayText == "2/2 busy, 2 hidden")
    }
}
