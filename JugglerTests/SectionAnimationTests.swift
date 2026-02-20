import Foundation
@testable import Juggler
import Testing

// MARK: - SectionType Tests

@Test func sectionType_idle_mapsFromIdleAndPermission() {
    #expect(SectionType(from: .idle) == .idle)
    #expect(SectionType(from: .permission) == .idle)
}

@Test func sectionType_working_mapsFromWorkingAndCompacting() {
    #expect(SectionType(from: .working) == .working)
    #expect(SectionType(from: .compacting) == .working)
}

@Test func sectionType_backburner_mapsFromBackburner() {
    #expect(SectionType(from: .backburner) == .backburner)
}

@Test func sectionType_rawValues_orderedCorrectly() {
    #expect(SectionType.idle.rawValue < SectionType.working.rawValue)
    #expect(SectionType.working.rawValue < SectionType.backburner.rawValue)
}

// MARK: - SectionAnimationController Tests

@Test func effectiveSection_noAnimation_returnsActualSection() {
    let controller = SectionAnimationController()
    let session = makeSession("s1", state: .idle)

    let section = controller.effectiveSection(for: session)

    #expect(section == .idle)
}

@Test func effectiveSection_noAnimation_workingSession() {
    let controller = SectionAnimationController()
    let session = makeSession("s1", state: .working)

    let section = controller.effectiveSection(for: session)

    #expect(section == .working)
}

@Test func effectiveSection_noAnimation_backburnerSession() {
    let controller = SectionAnimationController()
    let session = makeSession("s1", state: .backburner)

    let section = controller.effectiveSection(for: session)

    #expect(section == .backburner)
}

@Test func isDownAnimating_noAnimation_returnsFalse() {
    let controller = SectionAnimationController()

    #expect(controller.isDownAnimating(sessionID: "s1") == false)
}

// MARK: - AnimationDirection Tests

@Test func animationDirection_sameSection_isNone() {
    let controller = SectionAnimationController()
    // idle → permission stays in same section
    controller.animateTransition(sessionID: "s1", from: .idle, to: .permission)
    // No animation should be triggered for same-section transitions
    #expect(controller.isDownAnimating(sessionID: "s1") == false)
}

// animateTransition sets the initial departing phase synchronously before spawning
// an async Task for subsequent phase transitions, so we can safely check state here.
@Test func animateTransition_downDirection_idleToWorking() {
    let controller = SectionAnimationController()

    controller.animateTransition(sessionID: "s1", from: .idle, to: .working)

    #expect(controller.isDownAnimating(sessionID: "s1") == true)
    #expect(controller.isDownAnimating(sessionID: "s2") == false)
}

@Test func animateTransition_downDirection_workingToBackburner() {
    let controller = SectionAnimationController()

    controller.animateTransition(sessionID: "s1", from: .working, to: .backburner)

    #expect(controller.isDownAnimating(sessionID: "s1") == true)
}

@Test func animateTransition_upDirection_workingToIdle() {
    let controller = SectionAnimationController()

    controller.animateTransition(sessionID: "s1", from: .working, to: .idle)

    // Up animations don't use downAnimation
    #expect(controller.isDownAnimating(sessionID: "s1") == false)
}

@Test func animateTransition_upDirection_backburnerToWorking() {
    let controller = SectionAnimationController()

    controller.animateTransition(sessionID: "s1", from: .backburner, to: .working)

    #expect(controller.isDownAnimating(sessionID: "s1") == false)
}

@Test func animateTransition_sameSectionTransitions_noAnimation() {
    let controller = SectionAnimationController()

    // working → compacting: same section (working)
    controller.animateTransition(sessionID: "s1", from: .working, to: .compacting)
    #expect(controller.isDownAnimating(sessionID: "s1") == false)

    // permission → idle: same section (idle)
    controller.animateTransition(sessionID: "s2", from: .permission, to: .idle)
    #expect(controller.isDownAnimating(sessionID: "s2") == false)
}

@Test func effectiveSection_duringDownAnimation_returnsSourceSection() {
    let controller = SectionAnimationController()

    // Trigger down animation from idle to working
    controller.animateTransition(sessionID: "s1", from: .idle, to: .working)

    // The session's actual state would be .working now, but during departing phase
    // effectiveSection should return the source section (.idle)
    var session = makeSession("s1", state: .working)
    let section = controller.effectiveSection(for: session)

    #expect(section == .idle)
}

// MARK: - SectionAnimationTiming Tests

@Test func sectionAnimationTiming_valuesArePositive() {
    #expect(SectionAnimationTiming.downDepartureDuration > 0)
    #expect(SectionAnimationTiming.downOffscreenDelay > 0)
    #expect(SectionAnimationTiming.downArrivalDuration > 0)
    #expect(SectionAnimationTiming.upMoveDuration > 0)
}

// MARK: - DownAnimationState Tests

@Test func downAnimationState_equatable() {
    let state1 = DownAnimationState(sessionID: "s1", fromState: .idle, phase: .departing)
    let state2 = DownAnimationState(sessionID: "s1", fromState: .idle, phase: .departing)
    let state3 = DownAnimationState(sessionID: "s2", fromState: .idle, phase: .departing)

    #expect(state1 == state2)
    #expect(state1 != state3)
}

@Test func upAnimationState_equatable() {
    let state1 = UpAnimationState(sessionID: "s1")
    let state2 = UpAnimationState(sessionID: "s1")
    let state3 = UpAnimationState(sessionID: "s2")

    #expect(state1 == state2)
    #expect(state1 != state3)
}
