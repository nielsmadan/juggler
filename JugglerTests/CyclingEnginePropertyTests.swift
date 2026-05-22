import Foundation
@testable import Juggler
import Testing

/// Seed range each property is run over.
private let propertySeeds = 0 ..< 500

/// Deterministic SplitMix64 generator so a failing property case is reproducible
/// from the seed Swift Testing reports.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let allStates: [SessionState] = [.idle, .working, .permission, .backburner, .compacting]

/// Builds a random session list (each id "S0", "S1", … with a random state).
private func randomSessions(using rng: inout SeededGenerator) -> [Session] {
    let count = Int.random(in: 0 ... 8, using: &rng)
    return (0 ..< count).map { i in
        makeSession("S\(i)", state: allStates.randomElement(using: &rng)!)
    }
}

/// Random focus: a session id, an unknown id, or nil.
private func randomFocus(in sessions: [Session], using rng: inout SeededGenerator) -> String? {
    switch Int.random(in: 0 ... 2, using: &rng) {
    case 0: sessions.randomElement(using: &rng)?.terminalSessionID
    case 1: "unknown-\(Int.random(in: 0 ... 99, using: &rng))"
    default: nil
    }
}

@Suite("CyclingEngine Properties")
struct CyclingEnginePropertyTests {
    private let engine = DefaultCyclingEngine()

    // MARK: - Property 1: target is always a cyclable session

    @Test(arguments: propertySeeds)
    func cycleForward_targetIsAlwaysCyclable(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let sessions = randomSessions(using: &rng)
        let focus = randomFocus(in: sessions, using: &rng)

        let result = engine.cycleForward(sessions: sessions, focusedSessionID: focus, state: .initial)

        if let target = result.targetSession {
            #expect(target.state.isIncludedInCycle)
        } else {
            #expect(!sessions.contains { $0.state.isIncludedInCycle })
        }
    }

    @Test(arguments: propertySeeds)
    func cycleBackward_targetIsAlwaysCyclable(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let sessions = randomSessions(using: &rng)
        let focus = randomFocus(in: sessions, using: &rng)

        let result = engine.cycleBackward(sessions: sessions, focusedSessionID: focus, state: .initial)

        if let target = result.targetSession {
            #expect(target.state.isIncludedInCycle)
        } else {
            #expect(!sessions.contains { $0.state.isIncludedInCycle })
        }
    }

    // MARK: - Property 2: forward then backward returns to the original session

    @Test(arguments: propertySeeds)
    func roundTrip_forwardThenBackward_returnsToOrigin(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let sessions = randomSessions(using: &rng)
        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        guard cyclable.count >= 2, let origin = cyclable.randomElement(using: &rng) else { return }

        let forward = engine.cycleForward(
            sessions: sessions,
            focusedSessionID: origin.terminalSessionID,
            state: .initial
        )
        guard let landed = forward.targetSession else {
            Issue.record("cycleForward returned nil with \(cyclable.count) cyclable sessions")
            return
        }

        let back = engine.cycleBackward(
            sessions: sessions,
            focusedSessionID: landed.terminalSessionID,
            state: forward.newState
        )
        #expect(back.targetSession?.terminalSessionID == origin.terminalSessionID)
    }

    // MARK: - Property 3: N forward cycles visit every cyclable session exactly once

    @Test(arguments: propertySeeds)
    func fullTraversal_visitsEveryCyclableSessionOnce(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let sessions = randomSessions(using: &rng)
        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        guard let start = cyclable.first else { return }

        var focus = start.terminalSessionID
        var state = CyclingState.initial
        var visited: [String] = []

        for _ in 0 ..< cyclable.count {
            let result = engine.cycleForward(sessions: sessions, focusedSessionID: focus, state: state)
            guard let target = result.targetSession else {
                Issue.record("cycleForward returned nil mid-traversal")
                return
            }
            visited.append(target.terminalSessionID)
            focus = target.terminalSessionID
            state = result.newState
        }

        let expected = Set(cyclable.map(\.terminalSessionID))
        #expect(Set(visited) == expected)
        #expect(visited.count == cyclable.count)
        #expect(visited.last == start.terminalSessionID)
    }

    // MARK: - Property 4: didMove reflects whether more than one session is cyclable

    @Test(arguments: propertySeeds)
    func didMove_matchesCyclableCount(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let sessions = randomSessions(using: &rng)
        let focus = randomFocus(in: sessions, using: &rng)
        let cyclableCount = sessions.filter(\.state.isIncludedInCycle).count

        let forward = engine.cycleForward(sessions: sessions, focusedSessionID: focus, state: .initial)
        if forward.targetSession != nil {
            #expect(forward.didMove == (cyclableCount > 1))
        }

        let backward = engine.cycleBackward(sessions: sessions, focusedSessionID: focus, state: .initial)
        if backward.targetSession != nil {
            #expect(backward.didMove == (cyclableCount > 1))
        }
    }

    // MARK: - Property 5: a stale (out-of-range) currentIndex never crashes

    /// After sessions are removed, a `CyclingState` can carry an index larger than
    /// the current list. With no focus the engine falls back to that index — it must
    /// still land on a valid cyclable session rather than trip a bounds assert.
    @Test(arguments: propertySeeds)
    func staleCurrentIndex_withNilFocus_yieldsValidTarget(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let sessions = randomSessions(using: &rng)
        let staleState = CyclingState(currentIndex: Int.random(in: 0 ... 50, using: &rng))

        let forward = engine.cycleForward(sessions: sessions, focusedSessionID: nil, state: staleState)
        if let target = forward.targetSession {
            #expect(target.state.isIncludedInCycle)
        }

        let backward = engine.cycleBackward(sessions: sessions, focusedSessionID: nil, state: staleState)
        if let target = backward.targetSession {
            #expect(target.state.isIncludedInCycle)
        }
    }
}
