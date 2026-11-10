//
//  ShortcutActions.swift
//  Juggler
//
//  Declares the app's keyboard-shortcut actions for ShortcutKit. Each enum's
//  raw value is the stable persistence id (never rename a case — migrate
//  instead). The default shortcut literals reproduce Juggler's historical
//  defaults exactly.
//

import Foundation
import ShortcutKit

/// System-wide hotkeys, registered via `ShortcutKitGlobal`'s
/// `CarbonGlobalActivator`. Fire whether or not Juggler is frontmost.
enum GlobalAction: String, ShortcutAction {
    case cycleForward
    case cycleBackward
    case backburner
    case sendToBack
    case reactivateAll
    case goToLastNotification
    case sessionMenu
    case showMonitor

    var definition: ShortcutActionDefinition {
        switch self {
        case .cycleForward:
            .init("Cycle Forward:", Shortcut("cmd+shift+k"))
        case .cycleBackward:
            .init("Cycle Backward:", Shortcut("cmd+shift+j"))
        case .backburner:
            .init("Backburner Current:", Shortcut("cmd+shift+l"))
        case .sendToBack:
            .init("Send to Back:", Shortcut("cmd+shift+o"))
        case .reactivateAll:
            .init("Reactivate All:", Shortcut("cmd+shift+h"))
        case .goToLastNotification:
            .init(
                "Last Notification:",
                Shortcut("cmd+shift+e"),
                description: "Activates the session from the most recent notification."
            )
        case .sessionMenu:
            .init(
                "Session Menu:",
                Shortcut("cmd+shift+m"),
                description: "Opens a menu to prioritize, hide, rename or note the focused tracked session."
            )
        case .showMonitor:
            .init(
                "Show Monitor:",
                Shortcut("cmd+shift+semicolon"),
                description: "Cycles: popover → monitor window → back to previous app."
            )
        }
    }
}

/// Session-list shortcuts, active while the monitor window, the menu-bar popover
/// or the session menu is the key window (see `ShortcutCenter.keyWindowShortcutContext`).
enum SessionListAction: String, ShortcutAction {
    case activate
    case moveDown
    case moveUp
    case backburner
    case sendToBack
    case reactivateSelected
    case reactivateAll
    case rename
    case editNote
    case cycleModeForward
    case cycleModeBackward
    case toggleBeacon
    case toggleAutoNext
    case toggleAutoRestart
    case togglePermissionFirst

    var definition: ShortcutActionDefinition {
        switch self {
        case .activate: .init("Activate", Shortcut("return"))
        case .moveDown: .init("Move Down", Shortcut("k"))
        case .moveUp: .init("Move Up", Shortcut("j"))
        case .backburner: .init("Backburner", Shortcut("l"))
        case .sendToBack: .init("Send to Back", Shortcut("o"))
        case .reactivateSelected: .init("Reactivate Selected", Shortcut("shift+l"))
        case .reactivateAll: .init("Reactivate All", Shortcut("h"))
        case .rename: .init("Rename", Shortcut("r"))
        case .editNote: .init("Edit Note", Shortcut("m"))
        case .cycleModeForward: .init("Cycle Mode Forward", Shortcut("tab"))
        case .cycleModeBackward: .init("Cycle Mode Backward", Shortcut("shift+tab"))
        case .toggleBeacon: .init("Toggle Beacon", Shortcut("b"))
        case .toggleAutoNext: .init("Auto Next", Shortcut("a"))
        case .toggleAutoRestart: .init("Auto Restart", Shortcut("q"))
        case .togglePermissionFirst: .init("Permission First", Shortcut("p"))
        }
    }

    var legendLabel: String? {
        switch self {
        case .reactivateSelected: "Reactivate"
        case .cycleModeForward: "Mode →"
        case .cycleModeBackward: "Mode ←"
        default: nil
        }
    }

    var showsInMenuLegend: Bool {
        switch self {
        case .activate, .moveDown, .moveUp, .backburner, .sendToBack,
             .reactivateSelected, .reactivateAll, .rename,
             .editNote,
             .cycleModeForward, .cycleModeBackward:
            true
        case .toggleBeacon, .toggleAutoNext, .toggleAutoRestart, .togglePermissionFirst:
            false
        }
    }
}

enum SessionMonitorAction: String, ShortcutAction {
    case toggleSelectedHidden
    case toggleHiddenVisibility
    case toggleSelectedPrioritized

    var definition: ShortcutActionDefinition {
        switch self {
        case .toggleSelectedHidden:
            .init("Hide / Unhide", Shortcut("e"), allowsKeyRepeat: false)
        case .toggleHiddenVisibility:
            .init("Show Hidden", Shortcut("cmd+e"), allowsKeyRepeat: false)
        case .toggleSelectedPrioritized:
            .init("Prio", Shortcut("y"), allowsKeyRepeat: false)
        }
    }
}

enum SessionRowContextAction: CaseIterable {
    case rename
    case editNote
    case backburner
    case reactivate

    var shortcutAction: SessionListAction {
        switch self {
        case .rename: .rename
        case .editNote: .editNote
        case .backburner: .backburner
        case .reactivate: .reactivateSelected
        }
    }
}

enum MonitorControlAction: CaseIterable {
    case permissionFirst
    case autoNext
    case autoRestart
    case beacon

    var shortcutAction: SessionListAction {
        switch self {
        case .permissionFirst: .togglePermissionFirst
        case .autoNext: .toggleAutoNext
        case .autoRestart: .toggleAutoRestart
        case .beacon: .toggleBeacon
        }
    }
}

extension ShortcutContext where Action == SessionListAction {
    func notifyHint(for action: SessionListAction) {
        guard action != .activate else { return }
        notify(action)
    }
}

enum RowActionShortcut: Equatable {
    case list(SessionListAction)
    case monitor(SessionMonitorAction)
}

extension SessionRowAction {
    var shortcut: RowActionShortcut {
        switch self {
        case .rename: .list(.rename)
        case .note: .list(.editNote)
        case .hide: .monitor(.toggleSelectedHidden)
        case .prio: .monitor(.toggleSelectedPrioritized)
        }
    }

    init?(_ shortcut: RowActionShortcut) {
        guard let action = Self.allCases.first(where: { $0.shortcut == shortcut }) else { return nil }
        self = action
    }

    @MainActor
    func shortcutDisplayString(
        list: ShortcutContext<SessionListAction>,
        monitor: ShortcutContext<SessionMonitorAction>
    ) -> String? {
        switch shortcut {
        case let .list(action): list.displayStrings(for: action).first
        case let .monitor(action): monitor.displayStrings(for: action).first
        }
    }
}
