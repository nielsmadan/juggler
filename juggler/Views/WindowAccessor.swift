//
//  WindowAccessor.swift
//  Juggler
//

import SwiftUI

/// Reports the `NSWindow` hosting this SwiftUI view back to the caller. Used to
/// scope a view's local key-event monitor to its own window so the menu-bar
/// popover and the main window don't steal each other's keystrokes. Mirrors the
/// hosting-window access ShortcutField's `BeepSuppressor` relies on.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // `view.window` is nil until the view is in the hierarchy — resolve next runloop.
        DispatchQueue.main.async { report(view.window, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { report(nsView.window, context: context) }
    }

    private func report(_ window: NSWindow?, context: Context) {
        guard context.coordinator.lastWindow !== window else { return }
        context.coordinator.lastWindow = window
        onResolve(window)
    }

    final class Coordinator {
        weak var lastWindow: NSWindow?
    }
}
