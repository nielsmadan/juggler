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
        case .showMonitor:
            .init(
                "Show Monitor:",
                Shortcut("cmd+shift+semicolon"),
                description: "Cycles: popover → monitor window → back to previous app."
            )
        }
    }
}

/// Session-list shortcuts, active only while the monitor window or the menu-bar
/// popover is the key window (see `ShortcutCenter.keyWindowShortcutContext`).
enum SessionListAction: String, ShortcutAction {
    case activate
    case moveDown
    case moveUp
    case backburner
    case sendToBack
    case reactivateSelected
    case reactivateAll
    case rename
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
             .cycleModeForward, .cycleModeBackward:
            true
        case .toggleBeacon, .toggleAutoNext, .toggleAutoRestart, .togglePermissionFirst:
            false
        }
    }
}
