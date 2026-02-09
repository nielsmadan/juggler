//
//  CyclingEngine.swift
//  Juggler
//

import Foundation

struct CyclingState: Equatable {
    var currentIndex: Int
    var highlightColorIndex: Int

    static let initial = CyclingState(currentIndex: 0, highlightColorIndex: 0)
}

struct CyclingResult: Equatable {
    let targetSession: Session?
    let newState: CyclingState
    let colorChanged: Bool
}

protocol CyclingEngine {
    func cycleForward(
        sessions: [Session],
        focusedSessionID: String?,
        state: CyclingState
    ) -> CyclingResult

    func cycleBackward(
        sessions: [Session],
        focusedSessionID: String?,
        state: CyclingState
    ) -> CyclingResult

    func syncStateToFocus(
        sessions: [Session],
        focusedSessionID: String?,
        state: CyclingState
    ) -> CyclingState
}

struct DefaultCyclingEngine: CyclingEngine {
    func cycleForward(
        sessions: [Session],
        focusedSessionID: String?,
        state: CyclingState
    ) -> CyclingResult {
        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        guard !cyclable.isEmpty else {
            return CyclingResult(targetSession: nil, newState: state, colorChanged: false)
        }

        let targetIdx = findTargetIndexForward(
            cyclable: cyclable,
            allSessions: sessions,
            focusedSessionID: focusedSessionID,
            fallbackIndex: state.currentIndex
        )

        let target = cyclable[targetIdx]
        let moved = (cyclable.count > 1)
        let newColorIdx = moved ? (state.highlightColorIndex + 1) % 5 : state.highlightColorIndex

        return CyclingResult(
            targetSession: target,
            newState: CyclingState(currentIndex: targetIdx, highlightColorIndex: newColorIdx),
            colorChanged: moved
        )
    }

    func cycleBackward(
        sessions: [Session],
        focusedSessionID: String?,
        state: CyclingState
    ) -> CyclingResult {
        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        guard !cyclable.isEmpty else {
            return CyclingResult(targetSession: nil, newState: state, colorChanged: false)
        }

        let targetIdx = findTargetIndexBackward(
            cyclable: cyclable,
            allSessions: sessions,
            focusedSessionID: focusedSessionID,
            fallbackIndex: state.currentIndex
        )

        let target = cyclable[targetIdx]
        let moved = (cyclable.count > 1)
        let newColorIdx = moved ? (state.highlightColorIndex - 1 + 5) % 5 : state.highlightColorIndex

        return CyclingResult(
            targetSession: target,
            newState: CyclingState(currentIndex: targetIdx, highlightColorIndex: newColorIdx),
            colorChanged: moved
        )
    }

    func syncStateToFocus(
        sessions: [Session],
        focusedSessionID: String?,
        state: CyclingState
    ) -> CyclingState {
        let cyclable = sessions.filter(\.state.isIncludedInCycle)
        guard !cyclable.isEmpty, let focusedID = focusedSessionID else {
            return state
        }

        if let idx = findSessionIndex(in: cyclable, matching: focusedID) {
            return CyclingState(currentIndex: idx, highlightColorIndex: state.highlightColorIndex)
        }

        return state
    }

    /// Finds a session by trying composite id first, then terminalSessionID with hasSuffix for bare UUID focus events.
    private func findSessionIndex(in sessions: [Session], matching focusedID: String) -> Int? {
        // Try composite id first (set from hook events with tmux pane info)
        if let idx = sessions.firstIndex(where: { $0.id == focusedID }) {
            return idx
        }
        // Fall back to terminalSessionID matching (for bare UUID from iTerm2 focus events)
        if let idx = sessions.firstIndex(where: {
            $0.terminalSessionID == focusedID || $0.terminalSessionID.hasSuffix(focusedID)
        }) {
            return idx
        }
        return nil
    }

    private func findTargetIndexForward(
        cyclable: [Session],
        allSessions: [Session],
        focusedSessionID: String?,
        fallbackIndex: Int
    ) -> Int {
        guard let focusedID = focusedSessionID else {
            return (fallbackIndex + 1) % cyclable.count
        }

        // Check if focused session is cyclable
        if let idx = findSessionIndex(in: cyclable, matching: focusedID) {
            return (idx + 1) % cyclable.count
        }

        // Focused session is non-cyclable - find the next cyclable after its position
        guard let allIdx = findSessionIndex(in: allSessions, matching: focusedID) else {
            return (fallbackIndex + 1) % cyclable.count
        }

        // Find first cyclable session AFTER the focused position
        for (i, session) in cyclable.enumerated() {
            if let sessionAllIdx = allSessions.firstIndex(where: { $0.id == session.id }),
               sessionAllIdx > allIdx {
                return i
            }
        }
        // Wrap around to first cyclable
        return 0
    }

    private func findTargetIndexBackward(
        cyclable: [Session],
        allSessions: [Session],
        focusedSessionID: String?,
        fallbackIndex: Int
    ) -> Int {
        guard let focusedID = focusedSessionID else {
            return (fallbackIndex - 1 + cyclable.count) % cyclable.count
        }

        // Check if focused session is cyclable
        if let idx = findSessionIndex(in: cyclable, matching: focusedID) {
            return (idx - 1 + cyclable.count) % cyclable.count
        }

        // Focused session is non-cyclable - find the previous cyclable before its position
        guard let allIdx = findSessionIndex(in: allSessions, matching: focusedID) else {
            return (fallbackIndex - 1 + cyclable.count) % cyclable.count
        }

        // Find last cyclable session BEFORE the focused position
        for (i, session) in cyclable.enumerated().reversed() {
            if let sessionAllIdx = allSessions.firstIndex(where: { $0.id == session.id }),
               sessionAllIdx < allIdx {
                return i
            }
        }
        // Wrap around to last cyclable
        return cyclable.count - 1
    }
}
