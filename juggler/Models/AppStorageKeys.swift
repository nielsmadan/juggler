import Foundation

enum AppStorageKeys {
    // General
    static let launchAtLogin = "launchAtLogin"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let sessionTitleMode = "sessionTitleMode"

    // Queue
    static let queueOrderMode = "queueOrderMode"
    static let groupByWindow = "groupByWindow"

    // Notifications
    static let notifyOnIdle = "notifyOnIdle"
    static let notifyOnPermission = "notifyOnPermission"
    static let playSound = "playSound"

    // Stats
    static let enableStats = "enableStats"
    static let idleSessionColoring = "idleSessionColoring"

    // Session list highlighting
    static let useCyclingColors = "useCyclingColors"
    static let showShortcutHelper = "showShortcutHelper"

    // Terminal highlighting
    static let useTerminalCyclingColors = "useTerminalCyclingColors"

    // Highlight triggers
    static let highlightOnHotkey = "highlightOnHotkey"
    static let highlightOnGuiSelect = "highlightOnGuiSelect"
    static let highlightOnNotification = "highlightOnNotification"

    // Tab bar highlighting
    static let tabHighlightEnabled = "tabHighlightEnabled"
    static let tabHighlightDuration = "tabHighlightDuration"
    static let tabHighlightColorRed = "tabHighlightColorRed"
    static let tabHighlightColorGreen = "tabHighlightColorGreen"
    static let tabHighlightColorBlue = "tabHighlightColorBlue"

    // Pane highlighting
    static let paneHighlightEnabled = "paneHighlightEnabled"
    static let paneHighlightDuration = "paneHighlightDuration"
    static let paneHighlightColorRed = "paneHighlightColorRed"
    static let paneHighlightColorGreen = "paneHighlightColorGreen"
    static let paneHighlightColorBlue = "paneHighlightColorBlue"

    // Backburner behavior
    static let goToNextOnBackburner = "goToNextOnBackburner"

    // Terminal enablement
    static let iterm2Enabled = "iterm2Enabled"
    static let kittyEnabled = "kittyEnabled"

    // Beacon HUD
    static let beaconEnabled = "beaconEnabled"
    static let beaconPosition = "beaconPosition"
    static let beaconSize = "beaconSize"
    static let beaconDuration = "beaconDuration"
    static let beaconAnchor = "beaconAnchor"

    // Logging
    static let verboseLogging = "verboseLogging"

    // Window frame
    static let mainWindowFrame = "mainWindowFrame"

    // Local shortcuts
    static let localShortcutMoveDown = "localShortcutMoveDown"
    static let localShortcutMoveUp = "localShortcutMoveUp"
    static let localShortcutBackburner = "localShortcutBackburner"
    static let localShortcutReactivateSelected = "localShortcutReactivateSelected"
    static let localShortcutReactivateAll = "localShortcutReactivateAll"
    static let localShortcutRename = "localShortcutRename"
    static let localShortcutCycleModeForward = "localShortcutCycleModeForward"
    static let localShortcutCycleModeBackward = "localShortcutCycleModeBackward"
    static let localShortcutTogglePause = "localShortcutTogglePause"
    static let localShortcutResetStats = "localShortcutResetStats"
}
