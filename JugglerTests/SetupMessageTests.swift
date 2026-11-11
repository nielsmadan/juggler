@testable import Juggler
import Testing

@Suite("Setup messages")
@MainActor
struct SetupMessageTests {
    @Test func iTerm2AutomationDenialMapsToAutomationDenied() {
        let failure = ITerm2SetupView.CheckFailure(errorNumber: -1743, errorMessage: nil)
        #expect(failure == .automationDenied)
        #expect(failure.message == "Juggler isn't allowed to control iTerm2. Allow it in Automation settings.")
    }

    @Test func iTerm2ScriptErrorShowsItsMessage() {
        let failure = ITerm2SetupView.CheckFailure(errorNumber: -1728, errorMessage: "Can't get application.")
        #expect(failure.message == "Check failed: Can't get application.")
    }

    @Test func iTerm2CheckWithoutErrorExplainsMissingRuntime() {
        let failure = ITerm2SetupView.CheckFailure(errorNumber: nil, errorMessage: nil)
        #expect(failure == .noResponse)
        #expect(failure.message
            == "iTerm2 didn't respond. Check that the Python runtime is installed and the Python API is enabled.")
    }

    @Test func iTerm2ErrorWithoutMessageExplainsMissingRuntime() {
        #expect(ITerm2SetupView.CheckFailure(errorNumber: -1728, errorMessage: nil) == .noResponse)
    }

    @Test func finishStepNamesTheBoundCycleShortcut() {
        #expect(FinishStep.cycleInstruction(keys: "⇧⌘J") == "use ⇧⌘J to cycle through them")
    }

    @Test func finishStepFallsBackWhenCycleShortcutIsUnbound() {
        #expect(FinishStep.cycleInstruction(keys: nil) == "use the Cycle Forward shortcut to cycle through them")
    }
}
