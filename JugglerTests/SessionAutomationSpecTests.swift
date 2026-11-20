@testable import Juggler
import Testing

extension SessionInteractionSpecifications {
    @MainActor
    struct SessionAutomationSpecTests {
        @Test(arguments: [false, true], [false, true])
        func startingFocusedWorkUsesOnlyAutoAdvance(autoAdvance: Bool, autoReactivate: Bool) async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: autoAdvance, autoReactivate: autoReactivate)
            defer { f.close() }
            f.focus("A")
            try f.startWork("A")
            await f.deliverPendingAutomation()
            #expect(f.activations == (autoAdvance ? ["B"] : []))
            #expect(f.focusedSession == (autoAdvance ? "B" : "A"))
            #expect(f.queue == ["B"])
        }

        @Test(arguments: [false, true])
        func backgroundWorkDoesNotAdvanceFocus(outside: Bool) async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            if outside { f.leave(.otherApp) }
            try f.startWork("B")
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.queue == ["A"])
        }

        @Test(arguments: [false, true], [false, true])
        func firstAgentCompletionUsesOnlyAutoReactivate(autoAdvance: Bool, autoReactivate: Bool) async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: autoAdvance, autoReactivate: autoReactivate)
            defer { f.close() }
            f.setBusy("A")
            f.setBusy("B")
            f.focus("A")
            try f.finishWork("B")
            await f.deliverPendingAutomation()
            #expect(f.activations == (autoReactivate ? ["B"] : []))
        }

        @Test(arguments: InteractionOutside.allCases)
        func completionOutsideTrackedSessionsDoesNotActivate(outside: InteractionOutside) async throws {
            let f = try InteractionFixture(["A", "B"], autoReactivate: true)
            defer { f.close() }
            f.setBusy("A")
            f.setBusy("B")
            f.focus("A")
            f.leave(outside)
            try f.finishWork("B")
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.queue == ["B"])
        }

        @Test func existingWaitingSessionSuppressesAutoReactivate() async throws {
            let f = try InteractionFixture(["A", "B", "C"], autoReactivate: true)
            defer { f.close() }
            f.setBusy("A")
            f.setBusy("B")
            f.focus("A")
            try f.finishWork("B")
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.queue == ["C", "B"])
        }

        @Test(arguments: InteractionRemoval.allCases, [false, true])
        func monitorRestorationNeverAutoReactivates(removal: InteractionRemoval, enabled: Bool) async throws {
            let f = try InteractionFixture(["A", "B"], autoReactivate: enabled)
            defer { f.close() }
            f.setBusy("A")
            f.focus("A")
            f.leave(.monitor)
            try await f.remove("B", using: removal, from: .monitor)
            try #require(f.queue == [])
            if removal == .hide { try f.unhide("B") } else { try f.restore("B") }
            #expect(f.pendingAutomationCount == 0)
            await f.deliverPendingAutomation()
            #expect(f.queue == ["B"])
            #expect(f.activations == [])
        }

        @Test(arguments: InteractionRemoval.allCases)
        func automaticAdvanceSkipsHiddenAndBackburneredSessions(removal: InteractionRemoval) async throws {
            let f = try InteractionFixture(["A", "B", "C"], autoAdvance: true)
            defer { f.close() }
            f.leave(.monitor)
            try await f.remove("B", using: removal, from: .monitor)
            f.focus("A")
            try f.startWork("A")
            await f.deliverPendingAutomation()
            #expect(f.activations == ["C"])
        }

        @Test func automaticAdvanceWithNoTargetShowsAllAtWork() async throws {
            let f = try InteractionFixture(["A"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            try f.startWork("A")
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.beacons == ["All At Work"])
        }

        @Test(arguments: InteractionOutside.allCases)
        func leavingBeforeAutomaticActivationIsHandledCancelsIt(outside: InteractionOutside) async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            try f.startWork("A")
            try #require(f.pendingAutomationCount == 1)
            f.leave(outside)
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
        }

        @Test func clickingAnotherSessionBeforeAutomaticActivationCancelsIt() async throws {
            let f = try InteractionFixture(["A", "B", "C"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            try f.startWork("A")
            try #require(f.pendingAutomationCount == 1)
            f.focus("C")
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.focusedSession == "C")
        }

        @Test(arguments: InteractionOutside.allCases, [false, true])
        func leavingDuringTerminalLookupCancelsActivation(outside: InteractionOutside, restarting: Bool) async throws {
            let f = try InteractionFixture(
                ["A", "B"], autoAdvance: !restarting, autoReactivate: restarting, pauseActivation: true
            )
            defer { f.close() }
            if restarting {
                f.setBusy("A")
                f.setBusy("B")
            }
            f.focus("A")
            if restarting { try f.finishWork("B") } else { try f.startWork("A") }
            try #require(f.pendingAutomationCount == 1)
            let activation = Task {
                defer { f.finishActivationLookup() }
                await f.deliverPendingAutomation()
            }
            let enteredLookup = await withTaskCancellationHandler {
                await f.waitForActivationLookup()
            } onCancel: {
                activation.cancel()
            }
            if enteredLookup, !Task.isCancelled { f.leave(outside) }
            f.releaseActivationLookup()
            await activation.value
            try Task.checkCancellation()
            try #require(enteredLookup, "Automatic activation finished before bridge lookup")
            #expect(f.activations == [])
        }

        @Test func backgroundCompactionDoesNotAutoAdvance() async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            try f.startCompaction("A")
            await f.deliverPendingAutomation()
            #expect(f.state("A") == .compacting)
            #expect(f.queue == ["B"])
            #expect(f.activations == [])
            #expect(f.focusedSession == "A")
        }

        @Test func backgroundToolActivityDoesNotAutoAdvance() async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            try f.startBackgroundTool("A")
            await f.deliverPendingAutomation()
            #expect(f.state("A") == .working)
            #expect(f.queue == ["B"])
            #expect(f.activations == [])
            #expect(f.focusedSession == "A")
        }

        @Test(arguments: InteractionRemoval.allCases)
        func controllerRestorationSuppressesAutomationEvenWithTrackedFocus(removal: InteractionRemoval) async throws {
            let f = try InteractionFixture(["A", "B"], autoReactivate: true)
            defer { f.close() }
            f.setBusy("A")
            f.leave(.monitor)
            try await f.remove("B", using: removal, from: .monitor)
            try #require(f.queue == [])
            f.focus("A")
            try #require(f.focusedSession == "A")

            if removal == .hide { try f.unhide("B") } else { try f.restore("B") }

            #expect(f.queue == ["B"])
            #expect(f.pendingAutomationCount == 0)
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.focusedSession == "A")
        }

        @Test func completionOfAHiddenSessionDoesNotAutoReactivate() async throws {
            let f = try InteractionFixture(["A", "B"], autoReactivate: true)
            defer { f.close() }
            f.setBusy("A")
            f.setBusy("B")
            f.leave(.monitor)
            try await f.remove("B", using: .hide, from: .monitor)
            f.focus("A")
            try f.finishWork("B")
            await f.deliverPendingAutomation()
            #expect(f.queue == [])
            #expect(f.activations == [])
        }

        @Test(arguments: InteractionOutside.allCases)
        func lateWorkEventForTheLastFocusedSessionDoesNotActivate(outside: InteractionOutside) async throws {
            let f = try InteractionFixture(["A", "B"], autoAdvance: true)
            defer { f.close() }
            f.focus("A")
            f.leave(outside)
            try f.startWork("A")
            await f.deliverPendingAutomation()
            #expect(f.activations == [])
            #expect(f.queue == ["B"])
        }
    }
}
