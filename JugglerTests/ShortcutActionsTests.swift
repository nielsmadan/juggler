import Foundation
@testable import Juggler
import ShortcutKit
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
}
