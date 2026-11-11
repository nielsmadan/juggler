//
//  SectionAnimationController.swift
//  Juggler
//

import Foundation
import SwiftUI

enum SectionType: Int {
    case idle = 0
    case working = 1
    case backburner = 2

    init(from state: SessionState) {
        switch state {
        case .idle, .permission:
            self = .idle
        case .working, .compacting:
            self = .working
        case .backburner:
            self = .backburner
        }
    }
}

enum AnimationDirection {
    case down
    case up
    case none
}

enum DownPhase {
    case departing
    case inFlight
    case arriving
}

struct DownAnimationState: Equatable {
    let sessionID: String
    let fromState: SessionState
    var phase: DownPhase
}

struct UpAnimationState: Equatable {
    let sessionID: String
}

enum SectionAnimationTiming {
    static let downDepartureDuration: Double = 0.3
    static let downOffscreenDelay: Double = 1.2
    static let downArrivalDuration: Double = 0.3
    static let upMoveDuration: Double = 0.4
}

@Observable
final class SectionAnimationController {
    private(set) var downAnimation: DownAnimationState?
    private(set) var upAnimation: UpAnimationState?
    @ObservationIgnored private var downTask: Task<Void, Never>?
    @ObservationIgnored private var upTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let reducesMotion: () -> Bool

    init(
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        reducesMotion: @escaping () -> Bool = { false }
    ) {
        self.sleep = sleep
        self.reducesMotion = reducesMotion
    }

    func cancel(sessionID: String) {
        if downAnimation?.sessionID == sessionID {
            downTask?.cancel()
            downTask = nil
            downAnimation = nil
        }
        if upAnimation?.sessionID == sessionID {
            upTask?.cancel()
            upTask = nil
            upAnimation = nil
        }
    }

    /// Returns the effective section for a session, or nil if it shouldn't be shown (during DOWN inFlight).
    func effectiveSection(for session: Session) -> SectionType? {
        guard !session.isHidden else { return SectionType(from: session.state) }
        if let down = downAnimation, down.sessionID == session.id {
            switch down.phase {
            case .departing:
                return SectionType(from: down.fromState)
            case .inFlight:
                return nil
            case .arriving:
                return SectionType(from: session.state)
            }
        }

        return SectionType(from: session.state)
    }

    func isDownAnimating(sessionID: String) -> Bool {
        downAnimation?.sessionID == sessionID
    }

    func animateTransition(
        sessionID: String,
        from fromState: SessionState,
        to toState: SessionState
    ) {
        let direction = Self.direction(from: fromState, to: toState)
        if direction != .none { cancel(sessionID: sessionID) }
        guard !reducesMotion() else { return }

        switch direction {
        case .down:
            startDownAnimation(sessionID: sessionID, from: fromState)
        case .up:
            startUpAnimation(sessionID: sessionID)
        case .none:
            break
        }
    }

    private static func direction(from: SessionState, to: SessionState) -> AnimationDirection {
        let fromSection = SectionType(from: from)
        let toSection = SectionType(from: to)

        if toSection.rawValue > fromSection.rawValue {
            return .down
        } else if toSection.rawValue < fromSection.rawValue {
            return .up
        } else {
            return .none
        }
    }

    private func startDownAnimation(sessionID: String, from fromState: SessionState) {
        downTask?.cancel()
        downAnimation = DownAnimationState(
            sessionID: sessionID,
            fromState: fromState,
            phase: .departing
        )

        downTask = Task { @MainActor in
            // Brief delay lets SwiftUI commit the initial state before the phase transition triggers layout changes.
            try? await sleep(.milliseconds(50))
            guard !Task.isCancelled, downAnimation?.sessionID == sessionID else { return }

            withAnimation(.easeInOut(duration: SectionAnimationTiming.downDepartureDuration)) {
                downAnimation = DownAnimationState(
                    sessionID: sessionID,
                    fromState: fromState,
                    phase: .inFlight
                )
            }

            try? await sleep(.seconds(
                SectionAnimationTiming.downDepartureDuration + SectionAnimationTiming.downOffscreenDelay
            ))
            guard !Task.isCancelled, downAnimation?.sessionID == sessionID else { return }

            withAnimation(.easeInOut(duration: SectionAnimationTiming.downArrivalDuration)) {
                downAnimation = DownAnimationState(
                    sessionID: sessionID,
                    fromState: fromState,
                    phase: .arriving
                )
            }

            try? await sleep(.seconds(SectionAnimationTiming.downArrivalDuration))
            if !Task.isCancelled, downAnimation?.sessionID == sessionID {
                downAnimation = nil
                downTask = nil
            }
        }
    }

    private func startUpAnimation(sessionID: String) {
        upTask?.cancel()
        upAnimation = UpAnimationState(
            sessionID: sessionID
        )

        upTask = Task { @MainActor in
            try? await sleep(.seconds(SectionAnimationTiming.upMoveDuration))
            if !Task.isCancelled, upAnimation?.sessionID == sessionID {
                upAnimation = nil
                upTask = nil
            }
        }
    }
}
