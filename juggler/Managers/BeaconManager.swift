import AppKit
import SwiftUI

@MainActor
final class BeaconManager {
    static let shared = BeaconManager()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var hostingController: NSHostingController<BeaconContentView>?
    private var showGeneration = 0

    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.beaconEnabled)
    }

    private var position: BeaconPosition {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.beaconPosition)
            ?? BeaconPosition.center.rawValue
        return BeaconPosition(rawValue: raw) ?? .center
    }

    private var size: BeaconSize {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.beaconSize)
            ?? BeaconSize.m.rawValue
        return BeaconSize(rawValue: raw) ?? .m
    }

    private var duration: Double {
        let value = UserDefaults.standard.double(forKey: AppStorageKeys.beaconDuration)
        return value > 0 ? value : 1.5
    }

    private var anchor: BeaconAnchor {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.beaconAnchor)
            ?? BeaconAnchor.screen.rawValue
        return BeaconAnchor(rawValue: raw) ?? .screen
    }

    func show(sessionName: String) {
        guard isEnabled else { return }

        showGeneration += 1
        dismissTask?.cancel()

        if panel == nil {
            createPanel()
        }

        hostingController?.rootView = BeaconContentView(sessionName: sessionName, size: size)

        let panelSize: NSSize
        if let hosting = hostingController {
            let fittingSize = hosting.view.fittingSize
            panel?.setContentSize(fittingSize)
            panelSize = fittingSize
        } else {
            panelSize = panel?.frame.size ?? .zero
        }

        positionPanel(panelSize: panelSize)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.panel?.animator().alphaValue = 1.0
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.duration))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    private func dismiss() {
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.panel?.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.showGeneration == generation else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    private func createPanel() {
        let contentView = BeaconContentView(sessionName: "")
        let hosting = NSHostingController(rootView: contentView)
        hostingController = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting

        self.panel = panel
    }

    private func frontmostWindowFrame() -> NSRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }

            guard let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            // CG coordinates use top-left of PRIMARY display as origin; convert to NS bottom-left origin.
            // Must use primary screen (screens[0]) — not NSScreen.main which is the screen with keyboard focus.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return NSRect(
                x: cgRect.origin.x,
                y: primaryHeight - cgRect.origin.y - cgRect.height,
                width: cgRect.width,
                height: cgRect.height
            )
        }
        return nil
    }

    private func positionPanel(panelSize: NSSize) {
        guard panel != nil, let screen = NSScreen.main else { return }

        let referenceFrame: NSRect = if anchor == .activeWindow, let windowFrame = frontmostWindowFrame() {
            windowFrame
        } else {
            screen.visibleFrame
        }

        let origin = BeaconPositionCalculator.calculateOrigin(
            position: position,
            referenceFrame: referenceFrame,
            panelSize: panelSize
        )
        panel?.setFrameOrigin(origin)
    }
}
