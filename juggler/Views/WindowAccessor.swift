//
//  WindowAccessor.swift
//  Juggler
//

import SwiftUI

/// Reports the `NSWindow` hosting this SwiftUI view, so a view can gate its shortcut context
/// on its own window being key.
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
