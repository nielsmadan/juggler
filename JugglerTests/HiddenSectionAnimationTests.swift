import Foundation
@testable import Juggler
import Testing

@MainActor
private final class AnimationSleepGate {
    var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_: Duration) async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func resumeNext() {
        continuations.removeFirst().resume()
    }

    func waitForSleepers(_ count: Int) async {
        for _ in 0 ..< 1000 {
            if continuations.count == count { return }
            await Task.yield()
        }
        Issue.record("Animation did not reach its delay")
    }
}

@Suite(.serialized)
@MainActor
struct HiddenSectionAnimationTests {
    @Test func hideUnhideCancelsBothAnimationDirections() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("down"), makeSession("up", state: .working)])
        manager.updateSessionState(terminalSessionID: "down", state: .working)
        manager.updateSessionState(terminalSessionID: "up", state: .idle)
        #expect(manager.animationController.downAnimation?.sessionID == "down")
        #expect(manager.animationController.upAnimation?.sessionID == "up")
        manager.setSessionHidden(sessionID: "down", isHidden: true)
        manager.setSessionHidden(sessionID: "up", isHidden: true)
        manager.setSessionHidden(sessionID: "down", isHidden: false)
        manager.setSessionHidden(sessionID: "up", isHidden: false)
        #expect(manager.animationController.downAnimation == nil)
        #expect(manager.animationController.upAnimation == nil)
        #expect(manager.animationController
            .effectiveSection(for: manager.sessions.first { $0.id == "down" }!) == .working)
        #expect(manager.animationController.effectiveSection(for: manager.sessions.first { $0.id == "up" }!) == .idle)
    }

    @Test func replacementCancelsOldTransitionWithoutAnimatingTheNewConversation() {
        let manager = TestFixtures.isolatedSessionManager()
        manager.testSetSessions([makeSession("row")])
        manager.updateSessionState(terminalSessionID: "row", state: .working)
        #expect(manager.animationController.downAnimation?.sessionID == "row")
        manager.addOrUpdateSession(
            agentSessionID: "replacement", terminalSessionID: "row", projectPath: "/test",
            state: .idle, event: "SessionStart"
        )
        #expect(manager.animationController.downAnimation == nil)
        #expect(manager.animationController.upAnimation == nil)
        #expect(manager.animationController.effectiveSection(for: manager.sessions[0]) == .idle)
    }

    @Test(arguments: [true, false])
    func cancelledTaskCannotMutateAnotherTransitionForTheSameRow(down: Bool) async {
        let gate = AnimationSleepGate()
        let controller = SectionAnimationController(sleep: gate.sleep)
        let from: SessionState = down ? .idle : .working
        let to: SessionState = down ? .working : .idle
        controller.animateTransition(sessionID: "row", from: from, to: to)
        await gate.waitForSleepers(1)
        controller.cancel(sessionID: "row")
        controller.animateTransition(sessionID: "row", from: from, to: to)
        await gate.waitForSleepers(2)
        gate.resumeNext()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        if down {
            #expect(controller.downAnimation == DownAnimationState(
                sessionID: "row",
                fromState: .idle,
                phase: .departing
            ))
        } else {
            #expect(controller.upAnimation == UpAnimationState(sessionID: "row"))
        }
        controller.cancel(sessionID: "row")
        gate.resumeNext()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(controller.downAnimation == nil)
        #expect(controller.upAnimation == nil)
    }

    @Test func cancellingOneRowPreservesTheOtherDirection() {
        let controller = SectionAnimationController()
        controller.animateTransition(sessionID: "down", from: .idle, to: .working)
        controller.animateTransition(sessionID: "up", from: .working, to: .idle)
        controller.cancel(sessionID: "down")
        #expect(controller.downAnimation == nil)
        #expect(controller.upAnimation?.sessionID == "up")
        controller.cancel(sessionID: "up")
    }
}
