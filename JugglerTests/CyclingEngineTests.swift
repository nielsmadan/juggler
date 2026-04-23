import Foundation
@testable import Juggler
import Testing

@Suite("CyclingEngine")
struct CyclingEngineTests {
    // MARK: - Basic Cycling

    @Test func cycleForward_fromFirstSession_movesToSecond() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession?.terminalSessionID == "B")
        #expect(result.newState.currentIndex == 1)
        #expect(result.didMove == true)
    }

    @Test func cycleForward_fromMiddle_movesToNext() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 1)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "B", state: state)

        #expect(result.targetSession?.terminalSessionID == "C")
        #expect(result.newState.currentIndex == 2)
    }

    @Test func cycleForward_fromLast_wrapsToFirst() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 2)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "C", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
        #expect(result.newState.currentIndex == 0)
    }

    @Test func cycleBackward_fromMiddle_movesToPrevious() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 1)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "B", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
        #expect(result.newState.currentIndex == 0)
    }

    @Test func cycleBackward_fromFirst_wrapsToLast() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession?.terminalSessionID == "C")
        #expect(result.newState.currentIndex == 2)
    }

    // MARK: - Sync State to Focus

    @Test func syncStateToFocus_updatesCurrentIndex() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let newState = engine.syncStateToFocus(sessions: sessions, focusedSessionID: "C", state: state)

        #expect(newState.currentIndex == 2)
    }

    @Test func syncThenCycleBackward_fromLast_movesToPrevious() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 2)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "C", state: state)

        #expect(result.targetSession?.terminalSessionID == "B")
    }

    @Test func syncThenCycleForward_fromLast_wrapsToFirst() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
        let state = CyclingState(currentIndex: 2)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "C", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
    }

    // MARK: - Backburnered Session Handling

    @Test func cycleForward_skipsBackburneredSession() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession?.terminalSessionID == "C")
    }

    @Test func cycleForward_wrapsAroundSkippingBackburnered() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
        let state = CyclingState(currentIndex: 1)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "C", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
    }

    @Test func cycleBackward_skipsBackburneredSession() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
        let state = CyclingState(currentIndex: 1)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "C", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
    }

    @Test func syncStateToFocus_backburneredSession_keepsCurrentIndex() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let newState = engine.syncStateToFocus(sessions: sessions, focusedSessionID: "B", state: state)

        #expect(newState.currentIndex == 0)
    }

    // MARK: - Single Session

    @Test func cycleForward_singleSession_staysOnSame() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
        #expect(result.didMove == false)
    }

    @Test func cycleBackward_singleSession_staysOnSame() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
        #expect(result.didMove == false)
    }

    // MARK: - All Backburnered

    @Test func cycleForward_allBackburnered_returnsNil() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A", state: .backburner), makeSession("B", state: .backburner)]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession == nil)
        #expect(result.didMove == false)
    }

    @Test func cycleBackward_allBackburnered_returnsNil() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A", state: .backburner), makeSession("B", state: .backburner)]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.targetSession == nil)
        #expect(result.didMove == false)
    }

    // MARK: - Cycling From Backburnered Session

    @Test func cycleForward_fromBackburnered_goesToNextCyclable() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "B", state: state)

        #expect(result.targetSession?.terminalSessionID == "C")
    }

    @Test func cycleBackward_fromBackburnered_goesToPreviousCyclable() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "B", state: state)

        #expect(result.targetSession?.terminalSessionID == "A")
    }

    // MARK: - didMove Flag

    @Test func didMove_singleSession_notMoved() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.didMove == false)
    }

    @Test func didMove_multipleSessions_moved() {
        let engine = DefaultCyclingEngine()
        let sessions = [makeSession("A"), makeSession("B")]
        let state = CyclingState(currentIndex: 0)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

        #expect(result.didMove == true)
    }
}
