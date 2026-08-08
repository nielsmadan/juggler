import Foundation

enum AppStorageKeys {
    // General
    static let launchAtLogin = "launchAtLogin"
    static let showInDock = "showInDock"
    static let quitOnMonitorClose = "quitOnMonitorClose"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let sessionTitleMode = "sessionTitleMode"
    static let controlBarHintDismissed = "controlBarHintDismissed"

    static let queueOrderMode = "queueOrderMode"
    // Notifications
    static let notifyOnIdle = "notifyOnIdle"
    static let notifyOnPermission = "notifyOnPermission"
    static let playSound = "playSound"

    static let enableStats = "enableStats"
    static let dailyBusyStats = "dailyBusyStats"
    static let statsUseCyclingColors = "statsUseCyclingColors"
    static let statsBarColorRed = "statsBarColorRed"
    static let statsBarColorGreen = "statsBarColorGreen"
    static let statsBarColorBlue = "statsBarColorBlue"

    // Session list highlighting
    static let useCyclingColors = "useCyclingColors"
    static let showShortcutHelper = "showShortcutHelper"

    // Terminal highlighting
    static let useTerminalCyclingColors = "useTerminalCyclingColors"

    // Highlight triggers
    static let highlightOnHotkey = "highlightOnHotkey"
    static let highlightOnGuiSelect = "highlightOnGuiSelect"
    static let highlightOnNotification = "highlightOnNotification"

    static let tabHighlightEnabled = "tabHighlightEnabled"
    static let tabHighlightDuration = "tabHighlightDuration"
    static let tabHighlightColorRed = "tabHighlightColorRed"
    static let tabHighlightColorGreen = "tabHighlightColorGreen"
    static let tabHighlightColorBlue = "tabHighlightColorBlue"

    static let paneHighlightEnabled = "paneHighlightEnabled"
    static let paneHighlightDuration = "paneHighlightDuration"
    static let paneHighlightColorRed = "paneHighlightColorRed"
    static let paneHighlightColorGreen = "paneHighlightColorGreen"
    static let paneHighlightColorBlue = "paneHighlightColorBlue"

    static let goToNextOnBackburner = "goToNextOnBackburner"

    static let autoAdvanceOnBusy = "autoAdvanceOnBusy"
    static let autoRestartOnIdle = "autoRestartOnIdle"
    static let prioritizePermissionSessions = "prioritizePermissionSessions"

    static let iterm2Enabled = "iterm2Enabled"
    static let kittyEnabled = "kittyEnabled"
    static let wezTermEnabled = "wezTermEnabled"

    static let codexEnabled = "codexEnabled"
    static let antigravityEnabled = "antigravityEnabled"

    static let beaconEnabled = "beaconEnabled"
    static let beaconPosition = "beaconPosition"
    static let beaconSize = "beaconSize"
    static let beaconDuration = "beaconDuration"
    static let beaconAnchor = "beaconAnchor"

    static let verboseLogging = "verboseLogging"

    static let mainWindowFrame = "mainWindowFrame"

    static let localShortcutMoveDown = "localShortcutMoveDown"
    static let localShortcutMoveUp = "localShortcutMoveUp"
    static let localShortcutBackburner = "localShortcutBackburner"
    static let localShortcutSendToBack = "localShortcutSendToBack"
    static let localShortcutReactivateSelected = "localShortcutReactivateSelected"
    static let localShortcutReactivateAll = "localShortcutReactivateAll"
    static let localShortcutRename = "localShortcutRename"
    static let localShortcutCycleModeForward = "localShortcutCycleModeForward"
    static let localShortcutCycleModeBackward = "localShortcutCycleModeBackward"
    static let localShortcutToggleBeacon = "localShortcutToggleBeacon"
    static let localShortcutToggleAutoNext = "localShortcutToggleAutoNext"
    static let localShortcutToggleAutoRestart = "localShortcutToggleAutoRestart"
    static let localShortcutTogglePermissionFirst = "localShortcutTogglePermissionFirst"
}
