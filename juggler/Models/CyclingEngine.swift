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

    /// Finds a session by composite id or terminalSessionID (focusedSessionID is normalized on entry).
    private func findSessionIndex(in sessions: [Session], matching focusedID: String) -> Int? {
        sessions.firstIndex(where: { $0.id == focusedID || $0.terminalSessionID == focusedID })
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

        if let idx = findSessionIndex(in: cyclable, matching: focusedID) {
            return (idx + 1) % cyclable.count
        }

        guard let allIdx = findSessionIndex(in: allSessions, matching: focusedID) else {
            return (fallbackIndex + 1) % cyclable.count
        }

        for (i, session) in cyclable.enumerated() {
            if let sessionAllIdx = allSessions.firstIndex(where: { $0.id == session.id }),
               sessionAllIdx > allIdx {
                return i
            }
        }
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

        if let idx = findSessionIndex(in: cyclable, matching: focusedID) {
            return (idx - 1 + cyclable.count) % cyclable.count
        }

        guard let allIdx = findSessionIndex(in: allSessions, matching: focusedID) else {
            return (fallbackIndex - 1 + cyclable.count) % cyclable.count
        }

        for (i, session) in cyclable.enumerated().reversed() {
            if let sessionAllIdx = allSessions.firstIndex(where: { $0.id == session.id }),
               sessionAllIdx < allIdx {
                return i
            }
        }
        return cyclable.count - 1
    }
}
