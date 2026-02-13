//
//  SectionAnimationController.swift
//  Juggler
//
//  Manages animations for sessions moving between sections.
//  DOWN: slide out right, delay, slide in from right (using transitions)
//  UP: smooth vertical movement (using matchedGeometryEffect)
//

import Foundation
import SwiftUI

// MARK: - Section Type

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

// MARK: - Animation Direction

enum AnimationDirection {
    case down // Idle→Busy, Busy→Backburner (slide out/in)
    case up // Busy→Idle, Backburner→Busy (vertical movement)
    case none // Same section
}

// MARK: - DOWN Animation Phases

enum DownPhase {
    case departing // Still in source section
    case inFlight // Not visible (between sections)
    case arriving // Appearing in target section
}

// MARK: - Animation State

struct DownAnimationState: Equatable {
    let sessionID: String
    let fromState: SessionState
    let toState: SessionState
    var phase: DownPhase
}

struct UpAnimationState: Equatable {
    let sessionID: String
    let fromState: SessionState
    let toState: SessionState
}

// MARK: - Animation Timing

enum SectionAnimationTiming {
    static let downDepartureDuration: Double = 0.3
    static let downOffscreenDelay: Double = 1.2
    static let downArrivalDuration: Double = 0.3
    static let upMoveDuration: Double = 0.4
}

// MARK: - Section Animation Controller

@Observable
final class SectionAnimationController {
    private(set) var downAnimation: DownAnimationState?
    private(set) var upAnimation: UpAnimationState?

    // MARK: - Public API

    /// Returns the effective section for a session, or nil if it shouldn't be shown (during DOWN inFlight).
    func effectiveSection(for session: Session) -> SectionType? {
        // Check DOWN animation
        if let down = downAnimation, down.sessionID == session.id {
            switch down.phase {
            case .departing:
                return SectionType(from: down.fromState)
            case .inFlight:
                return nil // Not visible during transition
            case .arriving:
                return SectionType(from: session.state)
            }
        }

        // UP animation: session is always in its actual section (matchedGeometryEffect handles movement)
        // No special handling needed - just return actual section

        return SectionType(from: session.state)
    }

    /// Returns whether this session is doing a DOWN animation.
    func isDownAnimating(sessionID: String) -> Bool {
        downAnimation?.sessionID == sessionID
    }

    /// Triggers animation for a session moving between states.
    func animateTransition(
        sessionID: String,
        from fromState: SessionState,
        to toState: SessionState
    ) {
        let direction = Self.direction(from: fromState, to: toState)

        switch direction {
        case .down:
            startDownAnimation(sessionID: sessionID, from: fromState, to: toState)
        case .up:
            startUpAnimation(sessionID: sessionID, from: fromState, to: toState)
        case .none:
            break
        }
    }

    // MARK: - Direction Helper

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

    // MARK: - DOWN Animation

    private func startDownAnimation(sessionID: String, from fromState: SessionState, to toState: SessionState) {
        // Phase 1: departing (still visible in source section).
        downAnimation = DownAnimationState(
            sessionID: sessionID,
            fromState: fromState,
            toState: toState,
            phase: .departing
        )

        Task { @MainActor in
            // Small delay then trigger removal
            try? await Task.sleep(for: .milliseconds(50))
            guard downAnimation?.sessionID == sessionID else { return }

            // Phase 2: inFlight (row removed, offscreen delay starts).
            withAnimation(.easeInOut(duration: SectionAnimationTiming.downDepartureDuration)) {
                downAnimation = DownAnimationState(
                    sessionID: sessionID,
                    fromState: fromState,
                    toState: toState,
                    phase: .inFlight
                )
            }

            // Wait for removal + offscreen delay.
            try? await Task
                .sleep(for: .seconds(SectionAnimationTiming.downDepartureDuration + SectionAnimationTiming
                        .downOffscreenDelay))
            guard downAnimation?.sessionID == sessionID else { return }

            // Phase 3: arriving (row inserted in target section).
            withAnimation(.easeInOut(duration: SectionAnimationTiming.downArrivalDuration)) {
                downAnimation = DownAnimationState(
                    sessionID: sessionID,
                    fromState: fromState,
                    toState: toState,
                    phase: .arriving
                )
            }

            // Wait for insertion, then clear
            try? await Task.sleep(for: .seconds(SectionAnimationTiming.downArrivalDuration))
            if downAnimation?.sessionID == sessionID {
                downAnimation = nil
            }
        }
    }

    // MARK: - UP Animation

    private func startUpAnimation(sessionID: String, from fromState: SessionState, to toState: SessionState) {
        // For UP, we just track that an animation is happening
        // The actual animation is handled by matchedGeometryEffect in the view
        upAnimation = UpAnimationState(
            sessionID: sessionID,
            fromState: fromState,
            toState: toState
        )

        Task { @MainActor in
            // Clear after animation duration
            try? await Task.sleep(for: .seconds(SectionAnimationTiming.upMoveDuration))
            if upAnimation?.sessionID == sessionID {
                upAnimation = nil
            }
        }
    }
}
