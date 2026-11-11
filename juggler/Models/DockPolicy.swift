import Foundation

enum ClosingWindow: Equatable {
    case main(appInitiated: Bool)
    case other
}

enum WindowCloseOutcome: Equatable {
    case quit
    case hideDockIcon
    case keepDockIcon
}

enum DockPolicy {
    static func isAppWindow(isTitled: Bool, isPanel: Bool, isSheet: Bool) -> Bool {
        isTitled && !isPanel && !isSheet
    }

    static func closeOutcome(
        closing: ClosingWindow,
        quitOnMonitorClose: Bool,
        otherWindowOpen: Bool
    ) -> WindowCloseOutcome {
        if closing == .main(appInitiated: false), quitOnMonitorClose { return .quit }
        return otherWindowOpen ? .keepDockIcon : .hideDockIcon
    }

    static func keepsDockIcon(isAppWindow: Bool, isVisible: Bool, isMiniaturized: Bool) -> Bool {
        isAppWindow && (isVisible || isMiniaturized)
    }
}
