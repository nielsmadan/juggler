//
//  CyclingEngineTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

// MARK: - Test Helpers

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
        lastUpdated: Date(),
        startedAt: Date()
    )
}

// MARK: - Basic Cycling Tests

@Test func cycleForward_fromFirstSession_movesToSecond() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession?.terminalSessionID == "B")
    #expect(result.newState.currentIndex == 1)
    #expect(result.colorChanged == true)
}

@Test func cycleForward_fromMiddle_movesToNext() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 1, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "B", state: state)

    #expect(result.targetSession?.terminalSessionID == "C")
    #expect(result.newState.currentIndex == 2)
}

@Test func cycleForward_fromLast_wrapsToFirst() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 2, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "C", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
    #expect(result.newState.currentIndex == 0)
}

@Test func cycleBackward_fromMiddle_movesToPrevious() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 1, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "B", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
    #expect(result.newState.currentIndex == 0)
}

@Test func cycleBackward_fromFirst_wrapsToLast() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession?.terminalSessionID == "C")
    #expect(result.newState.currentIndex == 2)
}

// MARK: - Sync State to Focus Tests

@Test func syncStateToFocus_updatesCurrentIndex() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let newState = engine.syncStateToFocus(sessions: sessions, focusedSessionID: "C", state: state)

    #expect(newState.currentIndex == 2)
}

@Test func syncThenCycleBackward_fromLast_movesToPrevious() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 2, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "C", state: state)

    #expect(result.targetSession?.terminalSessionID == "B")
}

@Test func syncThenCycleForward_fromLast_wrapsToFirst() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B"), makeSession("C")]
    let state = CyclingState(currentIndex: 2, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "C", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
}

// MARK: - Backburnered Session Tests

@Test func cycleForward_skipsBackburneredSession() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession?.terminalSessionID == "C")
}

@Test func cycleForward_wrapsAroundSkippingBackburnered() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
    let state = CyclingState(currentIndex: 1, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "C", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
}

@Test func cycleBackward_skipsBackburneredSession() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
    let state = CyclingState(currentIndex: 1, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "C", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
}

@Test func syncStateToFocus_backburneredSession_keepsCurrentIndex() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let newState = engine.syncStateToFocus(sessions: sessions, focusedSessionID: "B", state: state)

    #expect(newState.currentIndex == 0)
}

// MARK: - Single Session Tests

@Test func cycleForward_singleSession_staysOnSame() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
    #expect(result.colorChanged == false)
}

@Test func cycleBackward_singleSession_staysOnSame() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
    #expect(result.colorChanged == false)
}

// MARK: - All Backburnered Tests

@Test func cycleForward_allBackburnered_returnsNil() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A", state: .backburner), makeSession("B", state: .backburner)]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession == nil)
    #expect(result.colorChanged == false)
}

@Test func cycleBackward_allBackburnered_returnsNil() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A", state: .backburner), makeSession("B", state: .backburner)]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.targetSession == nil)
    #expect(result.colorChanged == false)
}

// MARK: - Cycling From Backburnered Session

@Test func cycleForward_fromBackburnered_goesToNextCyclable() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "B", state: state)

    #expect(result.targetSession?.terminalSessionID == "C")
}

@Test func cycleBackward_fromBackburnered_goesToPreviousCyclable() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B", state: .backburner), makeSession("C")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "B", state: state)

    #expect(result.targetSession?.terminalSessionID == "A")
}

// MARK: - Color Index Tests

@Test func colorIndex_singleSession_unchanged() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 2)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.newState.highlightColorIndex == 2)
    #expect(result.colorChanged == false)
}

@Test func colorIndex_multipleSessions_advancesOnCycle() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.newState.highlightColorIndex == 1)
    #expect(result.colorChanged == true)
}

@Test func colorIndex_cycleBackward_decrements() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B")]

    var state = CyclingState(currentIndex: 0, highlightColorIndex: 0)

    var result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)
    #expect(result.newState.highlightColorIndex == 1)
    state = result.newState

    result = engine.cycleBackward(sessions: sessions, focusedSessionID: "B", state: state)
    #expect(result.newState.highlightColorIndex == 0)
}

@Test func colorWrapsAt5() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B")]
    let state = CyclingState(currentIndex: 0, highlightColorIndex: 4)

    let result = engine.cycleForward(sessions: sessions, focusedSessionID: "A", state: state)

    #expect(result.newState.highlightColorIndex == 0)
}

@Test func colorWrapsBackwardAt0() {
    let engine = DefaultCyclingEngine()
    let sessions = [makeSession("A"), makeSession("B")]
    let state = CyclingState(currentIndex: 1, highlightColorIndex: 0)

    let result = engine.cycleBackward(sessions: sessions, focusedSessionID: "B", state: state)

    #expect(result.newState.highlightColorIndex == 4)
}
