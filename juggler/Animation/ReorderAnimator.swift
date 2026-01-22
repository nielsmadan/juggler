import Foundation
import SwiftUI

// MARK: - Animation State (Discriminated Union)

enum ReorderAnimationState: Equatable {
    case idle
    case animatingUp(UpState)
    case animatingDown(DownState)

    struct UpState: Equatable {
        let sessionID: String
        let fromState: SessionState
        var offset: CGFloat
        var phase: Phase

        enum Phase: Equatable {
            case traveling // Sliding up, semi-transparent
            case settling // Moved in array, fading to full opacity
        }
    }

    struct DownState: Equatable {
        let sessionID: String
        let fromState: SessionState
        var phase: Phase

        enum Phase: Equatable {
            case departing // Fading out, sliding right
            case shifting // Invisible, sections resize
            case arriving // Fading in, sliding from right
        }
    }

    // MARK: - Convenience Accessors

    var animatingSessionID: String? {
        switch self {
        case .idle: nil
        case let .animatingUp(s): s.sessionID
        case let .animatingDown(s): s.sessionID
        }
    }

    var isAnimating: Bool {
        self != .idle
    }

    var fromState: SessionState? {
        switch self {
        case .idle: nil
        case let .animatingUp(s): s.fromState
        case let .animatingDown(s): s.fromState
        }
    }

    var offset: CGFloat {
        switch self {
        case let .animatingUp(s): s.offset
        case .idle, .animatingDown: 0
        }
    }

    /// Returns row opacity for the animating session
    var rowOpacity: Double {
        switch self {
        case .idle:
            1.0
        case let .animatingUp(s):
            switch s.phase {
            case .traveling: 0.6
            case .settling: 1.0
            }
        case let .animatingDown(s):
            switch s.phase {
            case .departing: 0.0
            case .shifting: 0.0
            case .arriving: 1.0
            }
        }
    }

    /// Returns horizontal offset for DOWN animations
    var horizontalOffset: CGFloat {
        switch self {
        case .idle, .animatingUp:
            0
        case let .animatingDown(s):
            switch s.phase {
            case .departing, .shifting: 400
            case .arriving: 0
            }
        }
    }

    /// Returns true if the animation is in UP direction
    var isUp: Bool {
        if case .animatingUp = self { return true }
        return false
    }

    /// Returns true if the animation is in DOWN direction
    var isDown: Bool {
        if case .animatingDown = self { return true }
        return false
    }
}

// MARK: - Queue Position

enum QueuePosition: Equatable {
    case topOfIdle
    case bottomOfIdle
    case bottomOfBusy
    case bottomOfBackburner
}

// MARK: - Reorder Animator

@Observable
final class ReorderAnimator {
    private(set) var state: ReorderAnimationState = .idle

    private var queue: [ReorderRequest] = []

    struct ReorderRequest: Equatable {
        let sessionID: String
        let position: QueuePosition
        let fromState: SessionState
    }

    // MARK: - Public API

    /// Enqueue a reorder animation. If no animation is in progress, starts immediately.
    func enqueueReorder(
        sessionID: String,
        to position: QueuePosition,
        fromState: SessionState,
        sessions: [Session],
        moveSession: @escaping (Int, Int) -> Void
    ) {
        if state.isAnimating {
            queue.append(ReorderRequest(sessionID: sessionID, position: position, fromState: fromState))
            return
        }

        performAnimatedReorder(
            sessionID: sessionID,
            to: position,
            fromState: fromState,
            sessions: sessions,
            moveSession: moveSession
        )
    }

    /// Cancel all animations and clear the queue
    func cancelAll() {
        state = .idle
        queue.removeAll()
    }

    /// Cancel animation for a specific session
    func cancel(sessionID: String) {
        if state.animatingSessionID == sessionID {
            state = .idle
        }
        queue.removeAll { $0.sessionID == sessionID }
    }

    // MARK: - Private Implementation

    private func performAnimatedReorder(
        sessionID: String,
        to position: QueuePosition,
        fromState: SessionState,
        sessions: [Session],
        moveSession: @escaping (Int, Int) -> Void
    ) {
        guard let currentIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            processNextInQueue(sessions: sessions, moveSession: moveSession)
            return
        }

        let targetIdx = targetIndex(for: position, in: sessions)
        if currentIndex == targetIdx {
            processNextInQueue(sessions: sessions, moveSession: moveSession)
            return
        }

        let direction = animationDirection(from: fromState, to: position)

        if direction == .up {
            performUpAnimation(
                sessionID: sessionID,
                fromState: fromState,
                currentIndex: currentIndex,
                targetIndex: targetIdx,
                position: position,
                sessions: sessions,
                moveSession: moveSession
            )
        } else {
            performDownAnimation(
                sessionID: sessionID,
                fromState: fromState,
                currentIndex: currentIndex,
                position: position,
                sessions: sessions,
                moveSession: moveSession
            )
        }
    }

    private enum Direction { case up, down }

    private func animationDirection(from fromState: SessionState, to position: QueuePosition) -> Direction {
        let fromIsIdle = fromState == .idle || fromState == .permission
        let fromIsBackburner = fromState == .backburner

        switch position {
        case .topOfIdle, .bottomOfIdle:
            return .up
        case .bottomOfBusy:
            if fromIsIdle {
                return .down
            } else if fromIsBackburner {
                return .up
            }
            return .down
        case .bottomOfBackburner:
            return .down
        }
    }

    private func targetIndex(for position: QueuePosition, in sessions: [Session]) -> Int {
        switch position {
        case .topOfIdle:
            return 0

        case .bottomOfIdle:
            if let firstBusy = sessions.firstIndex(where: { $0.state == .working || $0.state == .compacting }) {
                return firstBusy
            }
            if let firstBackburner = sessions.firstIndex(where: { $0.state == .backburner }) {
                return firstBackburner
            }
            return sessions.count

        case .bottomOfBusy:
            if let firstBackburner = sessions.firstIndex(where: { $0.state == .backburner }) {
                return firstBackburner
            }
            return sessions.count

        case .bottomOfBackburner:
            return sessions.count
        }
    }

    // MARK: - UP Animation

    private func performUpAnimation(
        sessionID: String,
        fromState: SessionState,
        currentIndex: Int,
        targetIndex: Int,
        position _: QueuePosition,
        sessions: [Session],
        moveSession: @escaping (Int, Int) -> Void
    ) {
        let rowHeight: CGFloat = 70
        let initialOffset = CGFloat(currentIndex - targetIndex) * rowHeight

        // Step 1: Set initial state with offset BEFORE animation starts
        state = .animatingUp(.init(
            sessionID: sessionID,
            fromState: fromState,
            offset: initialOffset,
            phase: .traveling
        ))

        // Step 2: In ONE animation block: move array AND animate offset to 0
        // This synchronizes section resize with item slide
        withAnimation(.easeInOut(duration: 0.6)) {
            moveSession(currentIndex, targetIndex)

            if case var .animatingUp(upState) = state {
                upState.offset = 0
                state = .animatingUp(upState)
            }
        }

        // Step 3: Wait for animation, then settle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)

            withAnimation(.easeOut(duration: 0.2)) {
                if case var .animatingUp(upState) = state {
                    upState.phase = .settling
                    state = .animatingUp(upState)
                }
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
            resetAndProcessNext(sessions: sessions, moveSession: moveSession)
        }
    }

    // MARK: - DOWN Animation

    private func performDownAnimation(
        sessionID: String,
        fromState: SessionState,
        currentIndex _: Int,
        position: QueuePosition,
        sessions: [Session],
        moveSession: @escaping (Int, Int) -> Void
    ) {
        Task { @MainActor in
            // Phase 1: Depart - set state INSIDE withAnimation so it animates
            withAnimation(.linear(duration: 0.4)) {
                state = .animatingDown(.init(
                    sessionID: sessionID,
                    fromState: fromState,
                    phase: .departing
                ))
            }

            try? await Task.sleep(nanoseconds: 400_000_000)

            // Phase 2: Shift (move array while invisible)
            // Use withAnimation so SwiftUI animates section resizing
            withAnimation(.easeInOut(duration: 0.4)) {
                if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
                    let newTarget = self.targetIndex(for: position, in: sessions)
                    moveSession(idx, min(newTarget, sessions.count))
                }

                if case var .animatingDown(downState) = state {
                    downState.phase = .shifting
                    state = .animatingDown(downState)
                }
            }

            // Wait for section animation to complete
            try? await Task.sleep(nanoseconds: 400_000_000)

            // Phase 3: Arrive
            withAnimation(.linear(duration: 0.4)) {
                if case var .animatingDown(downState) = state {
                    downState.phase = .arriving
                    state = .animatingDown(downState)
                }
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
            resetAndProcessNext(sessions: sessions, moveSession: moveSession)
        }
    }

    // MARK: - Queue Processing

    private func resetAndProcessNext(sessions: [Session], moveSession: @escaping (Int, Int) -> Void) {
        state = .idle
        processNextInQueue(sessions: sessions, moveSession: moveSession)
    }

    private func processNextInQueue(sessions: [Session], moveSession: @escaping (Int, Int) -> Void) {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        performAnimatedReorder(
            sessionID: next.sessionID,
            to: next.position,
            fromState: next.fromState,
            sessions: sessions,
            moveSession: moveSession
        )
    }
}
