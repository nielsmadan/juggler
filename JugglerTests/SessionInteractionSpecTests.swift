@testable import Juggler
import Testing

extension SessionInteractionSpecifications {
    @MainActor
    struct SessionInteractionSpecTests {
        @Test func mouseFocusEstablishesTheCyclePosition() async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.focus("B")
            try await f.cycle(.forward)
            #expect(f.activations == ["C"])
            try await f.cycle(.forward)
            #expect(f.activations == ["C", "A"])
            try await f.cycle(.backward)
            #expect(f.activations == ["C", "A", "C"])
        }

        @Test(arguments: InteractionDirection.allCases, InteractionOutside.allCases)
        func leavingTrackedSessionsResetsEitherCycleDirection(
            direction: InteractionDirection, outside: InteractionOutside
        ) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.focus("B")
            f.leave(outside)
            try await f.cycle(direction)
            #expect(f.activations == ["A"])
        }

        @Test(arguments: [false, true], [false, true])
        func busyPrioritizedHeadCyclesToTheNewHead(autoAdvance: Bool, compacting: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"], autoAdvance: autoAdvance)
            defer { f.close() }
            f.priority("A", true)
            f.priority("B", true)
            f.focus("A")
            if compacting { try f.startCompaction("A") } else { try f.startWork("A") }
            try await f.cycle(.forward)
            await f.deliverPendingAutomation()
            #expect(f.activations == ["B"])
        }

        @Test(arguments: InteractionRemoval.allCases, [false, true])
        func monitorRemovalDoesNotActivateTerminal(removal: InteractionRemoval, autoReactivate: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"], autoReactivate: autoReactivate)
            defer { f.close() }
            f.focus("B")
            f.leave(.monitor)
            try await f.remove("C", using: removal, from: .monitor)
            #expect(f.queue == ["A", "B"])
            #expect(f.activations == [])
            #expect(f.beacons == [])
            try await f.cycle(.forward)
            #expect(f.activations == ["A"])
        }

        @Test(arguments: [false, true])
        func hudHideAlwaysActivatesTheHead(backburnerAdvances: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"], backburnerAdvances: backburnerAdvances)
            defer { f.close() }
            f.focus("B")
            try await f.remove("B", using: .hide, from: .hud)
            #expect(f.queue == ["A", "C"])
            #expect(f.activations == ["A"])
        }

        @Test(arguments: [InteractionSource.hud, .global], [false, true])
        func backburnerUsesItsOwnAdvanceSetting(source: InteractionSource, advances: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"], backburnerAdvances: advances)
            defer { f.close() }
            f.focus("B")
            try await f.remove("B", using: .backburner, from: source)
            #expect(f.queue == ["A", "C"])
            #expect(f.activations == (advances ? ["A"] : []))
            #expect(f.focusedSession == (advances ? "A" : "B"))
        }

        @Test(arguments: InteractionEmptyAction.allCases)
        func intendedActivationWithoutATargetShowsAllAtWork(action: InteractionEmptyAction) async throws {
            let f = try InteractionFixture(["A"], backburnerAdvances: true)
            defer { f.close() }
            f.focus("A")
            try await f.performEmptyAction(action)
            #expect(f.activations == [])
            #expect(f.beacons == ["All At Work"])
        }

        @Test(arguments: [InteractionSource.hud, .monitor])
        func priorityChangesPlacementWithoutActivation(source: InteractionSource) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.priority("A", true)
            f.focus("C")
            if source == .monitor { f.leave(.monitor) }
            try #require(f.focusedSession == (source == .monitor ? nil : "C"))
            try await f.setPriority("C", true, from: source)
            #expect(f.queue == ["A", "C", "B"])
            #expect(f.focusedSession == (source == .monitor ? nil : "C"))
            f.focus("A")
            if source == .monitor { f.leave(.monitor) }
            try #require(f.focusedSession == (source == .monitor ? nil : "A"))
            try await f.setPriority("A", false, from: source)
            #expect(f.queue == ["C", "A", "B"])
            #expect(f.isPrioritized("C"))
            #expect(f.isPrioritized("A") == false)
            #expect(f.focusedSession == (source == .monitor ? nil : "A"))
            #expect(f.activations == [])
        }

        @Test(arguments: [false, true])
        func hideThenUnhidePreservesPriorityAndCurrentPosition(prioritized: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.priority("B", prioritized)
            let original = prioritized ? ["B", "A", "C"] : ["A", "B", "C"]
            #expect(f.queue == original)
            f.leave(.monitor)
            try await f.remove("B", using: .hide, from: .monitor)
            #expect(f.isHidden("B"))
            try f.unhide("B")
            #expect(f.isHidden("B") == false)
            #expect(f.queue == original)
            #expect(f.isPrioritized("B") == prioritized)
            #expect(f.activations == [])
            try await f.cycle(.forward)
            #expect(f.activations == [original[0]])
        }

        @Test func unhidingDoesNotRestoreAnOldIdleState() async throws {
            let f = try InteractionFixture(["A", "B"])
            defer { f.close() }
            f.leave(.monitor)
            try await f.remove("A", using: .hide, from: .monitor)
            #expect(f.isHidden("A"))
            f.setBusy("A")
            try f.unhide("A")
            #expect(f.isHidden("A") == false)
            #expect(f.queue == ["B"])
            #expect(f.state("A") == .working)
            try await f.cycle(.forward)
            #expect(f.activations == ["B"])
        }

        @Test(arguments: [false, true])
        func restoreBackburnerUsesQueueMode(prioMode: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"], prioMode: prioMode)
            defer { f.close() }
            f.leave(.monitor)
            try await f.remove("B", using: .backburner, from: .monitor)
            try f.restore("B")
            #expect(f.queue == (prioMode ? ["B", "A", "C"] : ["A", "C", "B"]))
            #expect(f.activations == [])
            try await f.cycle(.forward)
            #expect(f.activations == [prioMode ? "B" : "A"])
        }

        @Test(arguments: [false, true])
        func sendToBackThenCycleUsesTheVisibleQueue(prioritized: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.priority("A", true)
            f.priority("B", prioritized)
            f.focus("B")
            try await f.sendToBack("B")
            #expect(f.queue == ["A", "C", "B"])
            #expect(f.isPrioritized("B") == prioritized)
            #expect(f.activations == ["A"])
            try await f.cycle(.forward)
            #expect(f.activations == ["A", "C"])
        }

        @Test(arguments: InteractionHistory.allCases)
        func equivalentQueueAndFocusIgnoreThePreviousCommand(history: InteractionHistory) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.focus("B")
            try await f.establishEquivalentState(history)
            #expect(f.queue == ["A", "B", "C"])
            #expect(f.focusedSession == nil)
            try await f.cycle(.forward)
            #expect(f.activations == ["A"])
        }

        @Test(arguments: InteractionRemoval.allCases, InteractionDirection.allCases)
        func cyclingSkipsExcludedSessions(removal: InteractionRemoval, direction: InteractionDirection) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.leave(.monitor)
            try await f.remove("B", using: removal, from: .monitor)
            f.focus(direction == .forward ? "A" : "C")
            try await f.cycle(direction)
            #expect(f.activations == [direction == .forward ? "C" : "A"])
        }

        @Test func priorityResumesAfterSentBackSessionFinishesWork() async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.priority("A", true)
            f.priority("B", true)
            f.focus("B")
            try await f.sendToBack("B")
            #expect(f.queue == ["A", "C", "B"])
            f.setBusy("B")
            try f.finishWork("B")
            #expect(f.queue == ["A", "B", "C"])
            #expect(f.isPrioritized("B"))
        }

        @Test(arguments: [false, true])
        func priorityOnNonWaitingSessionAppliesWhenItReturns(backburnered: Bool) async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.priority("A", true)
            f.leave(.monitor)
            if backburnered {
                try await f.remove("C", using: .backburner, from: .monitor)
            } else {
                f.setBusy("C")
            }
            try await f.setPriority("C", true, from: .monitor)
            #expect(f.queue == ["A", "B"])
            if backburnered { try f.restore("C") } else { try f.finishWork("C") }
            #expect(f.queue == ["A", "C", "B"])
            #expect(f.activations == [])
        }

        @Test func selectingAMonitorRowDoesNotEstablishTerminalFocus() async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.focus("A")
            f.leave(.monitor)
            f.selectMonitorRow("B")
            #expect(f.selectedMonitorSession == "B")
            #expect(f.focusedSession == nil)
            #expect(f.activations == [])
            try await f.cycle(.forward)
            #expect(f.activations == ["A"])
        }

        @Test(arguments: [false, true], [false, true])
        func busyNonHeadSessionCyclesToTheHead(prioMode: Bool, compacting: Bool) async throws {
            let f = try InteractionFixture(["A", "B"], prioMode: prioMode)
            defer { f.close() }
            f.focus("B")
            if compacting { try f.startCompaction("B") } else { try f.startWork("B") }
            try f.addWaitingSession("C")
            try #require(f.queue == ["A", "C"])
            try #require(f.focusedSession == "B")
            try await f.cycle(.forward)
            #expect(f.activations == ["A"])
        }

        @Test(arguments: InteractionRemoval.allCases)
        func monitorRemovalOfTheLastEligibleSessionDoesNotAttemptActivation(removal: InteractionRemoval) async throws {
            let f = try InteractionFixture(["A"], autoAdvance: true, autoReactivate: true)
            defer { f.close() }
            f.focus("A")
            f.leave(.monitor)
            try await f.remove("A", using: removal, from: .monitor)
            #expect(f.queue == [])
            #expect(f.activations == [])
            #expect(f.beacons == [])
        }

        @Test(arguments: [InteractionSource.hud, .global])
        func disabledBackburnerAdvanceDoesNotReportAllAtWork(source: InteractionSource) async throws {
            let f = try InteractionFixture(["A"], backburnerAdvances: false)
            defer { f.close() }
            f.focus("A")
            try await f.remove("A", using: .backburner, from: source)
            #expect(f.queue == [])
            #expect(f.activations == [])
            #expect(f.beacons.contains("All At Work") == false)
            #expect(f.focusedSession == "A")
        }

        @Test func backburnerAndRestoreRetainAnExistingPriorityFlag() async throws {
            let f = try InteractionFixture(["A", "B"])
            defer { f.close() }
            f.priority("B", true)
            f.leave(.monitor)
            try await f.remove("B", using: .backburner, from: .monitor)
            #expect(f.isPrioritized("B"))
            #expect(f.queue == ["A"])
            try f.restore("B")
            #expect(f.isPrioritized("B"))
            #expect(f.queue == ["B", "A"])
            #expect(f.activations == [])
        }

        @Test func removingPriorityAfterSendToBackUsesCurrentPriorityPlacement() async throws {
            let f = try InteractionFixture(["A", "B", "C"])
            defer { f.close() }
            f.priority("A", true)
            f.priority("B", true)
            f.focus("B")
            try await f.sendToBack("B")
            try #require(f.queue == ["A", "C", "B"])
            try #require(f.isPrioritized("B"))
            f.leave(.monitor)
            try await f.setPriority("B", false, from: .monitor)
            #expect(f.queue == ["A", "B", "C"])
            #expect(f.isPrioritized("B") == false)
            #expect(f.activations == ["A"])
        }
    }
}
