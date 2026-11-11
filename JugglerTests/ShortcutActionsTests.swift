import Combine
import Foundation
@testable import Juggler
import ShortcutKit
import ShortcutKitUI
import Testing

@Suite("Shortcut actions")
@MainActor
struct ShortcutActionsTests {
    @Test func monitorVisibilityActionsHaveStableIDsAndNonrepeatingDefaults() {
        #expect(SessionMonitorAction.allCases.map(\.rawValue)
            == ["toggleSelectedHidden", "toggleHiddenVisibility", "toggleSelectedPrioritized"])
        #expect(SessionMonitorAction.toggleSelectedHidden.definition.defaultShortcuts == [Shortcut("e")])
        #expect(SessionMonitorAction.toggleHiddenVisibility.definition.defaultShortcuts == [Shortcut("cmd+e")])
        #expect(SessionMonitorAction.toggleSelectedPrioritized.definition.defaultShortcuts == [Shortcut("y")])
        #expect(SessionMonitorAction.allCases.allSatisfy { !$0.definition.allowsKeyRepeat })
    }

    @Test func monitorContextHasItsOwnSettingsSection() throws {
        let center = ShortcutCenter.shared
        #expect(center.sessionMonitorContext.id == "sessionMonitor")
        let group = try #require(center.registry.keyBindings.groups.first { $0.contextID == "sessionMonitor" })
        #expect(String(localized: group.displayName) == "Session Monitor")
        #expect(group.entries.map(\.actionID) == SessionMonitorAction.allCases.map(\.rawValue))
        let shared = try #require(center.registry.keyBindings.groups.first { $0.contextID == "sessionList" })
        #expect(shared.entries.map(\.actionID) == SessionListAction.allCases.map(\.rawValue))
    }

    @Test func monitorPointerHintsUseTheMonitorContext() {
        let context = ShortcutContext<SessionMonitorAction>("sessionMonitor")
        let registry = ShortcutRegistry(contexts: [context])
        var events: [(String, String)] = []
        let cancellable = registry.actionFired.sink { events.append(($0.contextID, $0.actionID)) }
        context.notify(.toggleSelectedHidden)
        context.notify(.toggleHiddenVisibility)
        #expect(events.map(\.0) == ["sessionMonitor", "sessionMonitor"])
        #expect(events.map(\.1) == ["toggleSelectedHidden", "toggleHiddenVisibility"])
        withExtendedLifetime(cancellable) {}
    }

    @Test func sessionMenuAndNoteActionsUseMatchingDefaultShortcuts() {
        #expect(GlobalAction.sessionMenu.definition.defaultShortcuts == [Shortcut("cmd+shift+m")])
        #expect(SessionListAction.editNote.definition.defaultShortcuts == [Shortcut("m")])
    }

    @Test func savedEditNoteBindingMigratesToTheSessionMenu() {
        let store = MemoryShortcutStore(RawState(overrides: ["global": ["editNote": [Shortcut("cmd+shift+n")]]]))
        let context = ShortcutContext<GlobalAction>("global")
        let registry = ShortcutRegistry(contexts: [context], migrations: ShortcutCenter.migrations, store: store)

        #expect(context.shortcuts(for: .sessionMenu) == [Shortcut("cmd+shift+n")])
        withExtendedLifetime(registry) {}
    }

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
            .editNote,
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
            .editNote,
            .backburner,
            .reactivateSelected
        ])
    }

    @Test func monitorControls_haveDisplayTitles() {
        #expect(MonitorControlAction.allCases.map(\.title) == [
            "Permission First",
            "Auto Next",
            "Auto Restart",
            "Beacon"
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

    @Test func monitorLegendMergesEveryContextIntoOneShortcutsGroup() throws {
        let registry = ShortcutCenter.shared.registry
        let bindings = registry.bindings(for: ["sessionList", "sessionMonitor"])
        let merged = bindings.mergedIntoSingleGroup(displayName: "Shortcuts")

        let group = try #require(merged.groups.first)
        #expect(merged.groups.count == 1)
        #expect(String(localized: group.displayName) == "Shortcuts")
        #expect(group.entries.map(\.actionID)
            == SessionListAction.allCases.map(\.rawValue) + SessionMonitorAction.allCases.map(\.rawValue))
        #expect(KeyBindings().mergedIntoSingleGroup(displayName: "Shortcuts").groups == [])
    }
}

@MainActor
final class MemoryShortcutStore: ShortcutBindingsStore {
    private(set) var state: RawState

    init(_ state: RawState = RawState()) {
        self.state = state
    }

    func load() -> RawState {
        state
    }

    func save(_ state: RawState) {
        self.state = state
    }
}
