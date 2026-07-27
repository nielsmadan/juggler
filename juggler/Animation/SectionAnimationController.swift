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

    /// Returns the effective section for a session, or nil if it shouldn't be shown (during DOWN inFlight).
    func effectiveSection(for session: Session) -> SectionType? {
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
        downAnimation = DownAnimationState(
            sessionID: sessionID,
            fromState: fromState,
            phase: .departing
        )

        Task { @MainActor in
            // Brief delay lets SwiftUI commit the initial state before the phase transition triggers layout changes.
            try? await Task.sleep(for: .milliseconds(50))
            guard downAnimation?.sessionID == sessionID else { return }

            withAnimation(.easeInOut(duration: SectionAnimationTiming.downDepartureDuration)) {
                downAnimation = DownAnimationState(
                    sessionID: sessionID,
                    fromState: fromState,
                    phase: .inFlight
                )
            }

            try? await Task
                .sleep(for: .seconds(SectionAnimationTiming.downDepartureDuration + SectionAnimationTiming
                        .downOffscreenDelay))
            guard downAnimation?.sessionID == sessionID else { return }

            withAnimation(.easeInOut(duration: SectionAnimationTiming.downArrivalDuration)) {
                downAnimation = DownAnimationState(
                    sessionID: sessionID,
                    fromState: fromState,
                    phase: .arriving
                )
            }

            try? await Task.sleep(for: .seconds(SectionAnimationTiming.downArrivalDuration))
            if downAnimation?.sessionID == sessionID {
                downAnimation = nil
            }
        }
    }

    private func startUpAnimation(sessionID: String) {
        upAnimation = UpAnimationState(
            sessionID: sessionID
        )

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(SectionAnimationTiming.upMoveDuration))
            if upAnimation?.sessionID == sessionID {
                upAnimation = nil
            }
        }
    }
}
