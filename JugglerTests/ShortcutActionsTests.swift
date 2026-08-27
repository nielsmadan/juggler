import Combine
import Foundation
@testable import Juggler
import ShortcutKit
import ShortcutKitUI
import Testing

@Suite("Shortcut actions")
@MainActor
struct ShortcutActionsTests {
    @Test func sessionListContext_usesShortcutsTitle() {
        #expect(String(localized: ShortcutCenter.shared.sessionListContext.displayName) == "Shortcuts")
    }

    @Test func sessionListActions_useCompactLegendLabels() {
        #expect(SessionListAction.reactivateSelected.legendLabel == "Reactivate")
        #expect(SessionListAction.cycleModeForward.legendLabel == "Mode →")
        #expect(SessionListAction.cycleModeBackward.legendLabel == "Mode ←")
    }

    @Test func sessionListActions_exposeMenuLegendEntries() {
        #expect(SessionListAction.allCases.filter(\.showsInMenuLegend) == [
            .activate,
            .moveDown,
            .moveUp,
            .backburner,
            .sendToBack,
            .reactivateSelected,
            .reactivateAll,
            .rename,
            .cycleModeForward,
            .cycleModeBackward
        ])
    }

    @Test func queueModePicker_usesShortestCycleShortcut() {
        #expect(QueueModePicker.shortcutAction(from: .fair, to: .prio) == .cycleModeForward)
        #expect(QueueModePicker.shortcutAction(from: .fair, to: .grouped) == .cycleModeBackward)
        #expect(QueueModePicker.shortcutAction(from: .grouped, to: .fair) == .cycleModeForward)
        #expect(QueueModePicker.shortcutAction(from: .fair, to: .static) == .cycleModeForward)
        #expect(QueueModePicker.shortcutAction(from: .fair, to: .fair) == nil)
    }

    @Test func shortcutHints_useTopWindowPresentation() {
        #expect(ShortcutCenter.shared.hintOptions.placement == .top)
        #expect(ShortcutCenter.shared.hintOptions.presentation == .window)
    }

    @Test func pointerHints_suppressActivationAndEmitVisibleActions() {
        let context = ShortcutContext<SessionListAction>("testSessionList")
        let registry = ShortcutRegistry(contexts: [context])
        var actionIDs: [String] = []
        let cancellable = registry.actionFired.sink { actionIDs.append($0.actionID) }

        context.notifyHint(for: .activate)
        context.notifyHint(for: .rename)
        context.notifyHint(for: .toggleBeacon)

        #expect(actionIDs == ["rename", "toggleBeacon"])
        withExtendedLifetime(cancellable) {}
    }

    @Test func rowContextActions_mapToMatchingShortcuts() {
        #expect(SessionRowContextAction.allCases.map(\.shortcutAction) == [
            .rename,
            .backburner,
            .reactivateSelected
        ])
    }

    @Test func monitorControls_mapToMatchingShortcuts() {
        #expect(MonitorControlAction.allCases.map(\.shortcutAction) == [
            .togglePermissionFirst,
            .toggleAutoNext,
            .toggleAutoRestart,
            .toggleBeacon
        ])
    }
}
