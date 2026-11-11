import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject {
    enum SceneID {
        static let main = "main"
        static let onboarding = "onboarding"
        static let about = "about"
    }

    static let shared = WindowManager()

    private let defaults: UserDefaults
    private let mainWindowID: String
    private let terminate: () -> Void
    private var mainWindowOpener: (() -> Void)?
    private var settingsWindow: NSWindow?
    private var mainWindowNeedsRestore = true
    private var hideDockIconWorkItem: DispatchWorkItem?
    private var isClosingMainWithoutQuit = false

    init(
        defaults: UserDefaults = .standard,
        mainWindowID: String = SceneID.main,
        terminate: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.defaults = defaults
        self.mainWindowID = mainWindowID
        self.terminate = terminate
        super.init()
    }

    var isMainWindowVisible: Bool {
        mainWindow?.isVisible ?? false
    }

    func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == mainWindowID
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first(where: isMainWindow)
    }

    private var showInDock: Bool {
        defaults.bool(forKey: AppStorageKeys.showInDock)
    }

    func start() {
        applyShowInDock(showInDock)
        NSApp.activate()
        observeWindows()
        restoreMainWindowFrameAtLaunch()
    }

    func observeWindows() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    /// Only `Commands` can reach `openWindow` before the suppressed main scene has created a window.
    func registerMainWindowOpener(_ opener: @escaping () -> Void) {
        guard mainWindowOpener == nil else { return }
        mainWindowOpener = opener
    }

    @objc func openMainWindow() {
        if let window = mainWindow {
            activateApp()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else if let mainWindowOpener {
            activateApp()
            mainWindowOpener()
        } else {
            logWarning(.navigation, "Session Monitor opener is not registered; cannot open the main window")
        }
    }

    /// An app-initiated close, which must not trigger quit-on-close.
    func closeMainWindow() {
        guard let window = mainWindow else { return }
        isClosingMainWithoutQuit = true
        defer { isClosingMainWithoutQuit = false }
        window.close()
    }

    @objc func openSettings() {
        activateApp()

        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView()
                    .environment(SessionManager.shared)
            )
            let fittingSize = hostingController.view.fittingSize
            hostingController.sizingOptions = .minSize

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(
                width: fittingSize.width,
                height: SettingsLayout.initialContentHeight(
                    fitting: fittingSize.height,
                    screenVisibleHeight: NSScreen.main?.visibleFrame.height
                )
            ))
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applyShowInDock(_ show: Bool) {
        cancelPendingDockHide()
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    /// The Dock policy must change before activation, or the previous app keeps the menu bar.
    private func activateApp() {
        showDockIconIfEnabled()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showDockIconIfEnabled() {
        cancelPendingDockHide()
        if showInDock {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func cancelPendingDockHide() {
        hideDockIconWorkItem?.cancel()
        hideDockIconWorkItem = nil
    }

    private func scheduleDockIconHide() {
        cancelPendingDockHide()
        // Cancellable so a window reopened within the delay keeps its Dock icon.
        let workItem = DispatchWorkItem {
            NSApp.setActivationPolicy(.accessory)
        }
        hideDockIconWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func restoreMainWindowFrameAtLaunch() {
        guard defaults.string(forKey: AppStorageKeys.mainWindowFrame) != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = mainWindow else { return }
            window.alphaValue = 0
            restoreSavedFrame(for: window)
            window.alphaValue = 1
        }
    }

    private func restoreSavedFrame(for window: NSWindow) {
        mainWindowNeedsRestore = false
        guard let frameString = defaults.string(forKey: AppStorageKeys.mainWindowFrame) else { return }
        let savedFrame = NSRectFromString(frameString)
        let onScreen = NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) })
        if savedFrame.width > 100, savedFrame.height > 100, onScreen {
            window.setFrame(savedFrame, display: false)
        }
    }

    private static func isAppWindow(_ window: NSWindow) -> Bool {
        DockPolicy.isAppWindow(
            isTitled: window.styleMask.contains(.titled),
            isPanel: window is NSPanel,
            isSheet: window.sheetParent != nil
        )
    }

    private static func keepsDockIcon(_ window: NSWindow) -> Bool {
        DockPolicy.keepsDockIcon(
            isAppWindow: isAppWindow(window),
            isVisible: window.isVisible,
            isMiniaturized: window.isMiniaturized
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isAppWindow(window) else { return }
        let isMain = isMainWindow(window)

        if isMain {
            // Must save before window deallocs
            defaults.set(NSStringFromRect(window.frame), forKey: AppStorageKeys.mainWindowFrame)
            mainWindowNeedsRestore = true
        }

        let outcome = DockPolicy.closeOutcome(
            closing: isMain ? .main(appInitiated: isClosingMainWithoutQuit) : .other,
            quitOnMonitorClose: defaults.bool(forKey: AppStorageKeys.quitOnMonitorClose),
            otherWindowOpen: NSApp.windows.contains { $0 !== window && Self.keepsDockIcon($0) }
        )
        switch outcome {
        case .quit:
            terminate()
        case .keepDockIcon:
            break
        case .hideDockIcon:
            scheduleDockIconHide()
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isAppWindow(window) else { return }

        guard isMainWindow(window) else {
            showDockIconIfEnabled()
            return
        }

        let wasInAccessoryMode = NSApp.activationPolicy() == .accessory

        cancelPendingDockHide()

        // When a notification click activated us, yield focus to the terminal
        // after the system's activation lifecycle has settled (see comment in
        // NotificationManager.didReceive for details).
        if let bundleID = notificationTerminalBundleID() {
            scheduleTerminalActivation(bundleID: bundleID)
            return
        }

        showDockIconIfEnabled()

        if mainWindowNeedsRestore {
            restoreSavedFrame(for: window)
        }

        // Window was auto-created from accessory mode. Hide it immediately to
        // prevent a flash, then decide on the next run loop (didReceive fires
        // after windowDidBecomeKey, so the notification flag isn't set yet).
        if wasInAccessoryMode {
            window.alphaValue = 0
            DispatchQueue.main.async {
                if let bundleID = self.notificationTerminalBundleID() {
                    self.scheduleTerminalActivation(bundleID: bundleID)
                    self.closeMainWindow()
                }
                window.alphaValue = 1
            }
        }
    }

    private func notificationTerminalBundleID() -> String? {
        guard NotificationManager.shared.isHandlingNotificationClick else { return nil }
        return NotificationManager.shared.pendingTerminalBundleID
    }

    private func scheduleTerminalActivation(bundleID: String) {
        guard let handoff = NotificationManager.shared.pendingClickHandoff else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard NotificationManager.shared.terminalBundleID(for: handoff) == bundleID else { return }
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
            }
        }
    }
}
