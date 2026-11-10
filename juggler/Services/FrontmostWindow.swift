import AppKit

enum FrontmostWindow {
    static func frame() -> NSRect? {
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
}
