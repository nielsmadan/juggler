//
//  ShortcutCenter.swift
//  Juggler
//
//  Owns the single shared ShortcutKit registry: the global hotkey context and
//  the local session-list context, plus the Carbon activator that registers the
//  global bindings system-wide. The registry is the one object the settings UI,
//  legends, and hint HUD observe.
//

import ShortcutKit
import ShortcutKitGlobal
import SwiftUI

@MainActor
final class ShortcutCenter {
    static let shared = ShortcutCenter()

    /// Global hotkeys. The handler runs system-wide (via Carbon) and routes to
    /// `HotkeyManager`, which captures terminal-frontmost state synchronously
    /// before any async hop.
    let globalContext = ShortcutContext<GlobalAction>(
        global: "global",
        displayName: "Global Shortcuts"
    ) { action, _ in
        HotkeyManager.shared.dispatch(action)
    }

    /// Session-list shortcuts. Local: the dispatch handler is bound per-window
    /// at activation by `keyWindowShortcutContext`.
    let sessionListContext = ShortcutContext<SessionListAction>(
        "sessionList",
        displayName: "Shortcuts"
    )

    let registry: ShortcutRegistry

    private let globalActivator = CarbonGlobalActivator()
    private var didStart = false

    private init() {
        registry = ShortcutRegistry(contexts: [globalContext, sessionListContext])
    }

    /// Start system-wide hotkey registration. Idempotent.
    func start() {
        guard !didStart else { return }
        didStart = true
        do {
            try globalActivator.start(registry)
        } catch {
            logError(.hotkey, "Global hotkey activator failed to start: \(error)")
        }
    }
}

extension View {
    /// Activate `context` only while `isActive` is true (i.e. the hosting window
    /// is key). ShortcutKit stores a single handler per context, so two windows
    /// sharing one context must never both be active — gating on key-window
    /// state guarantees exactly one is. Toggling `isActive` mounts/unmounts a
    /// zero-size companion view carrying `.activeShortcutContext`, whose
    /// onAppear/onDisappear push/pop the context and set/clear the handler.
    func keyWindowShortcutContext<A: ShortcutAction>(
        _ context: ShortcutContext<A>,
        isActive: Bool,
        dispatch handler: @escaping @MainActor (A, ShortcutDispatch) -> Void
    ) -> some View {
        background(
            Group {
                if isActive {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .activeShortcutContext(context, dispatch: handler)
                }
            }
        )
    }
}
