//
//  ShortcutCenter.swift
//  Juggler
//
//  Owns the single shared ShortcutKit registry: the global hotkey context and
//  the local session-list and session-monitor contexts, plus the Carbon activator
//  that registers the global bindings system-wide. The registry is the one object the settings UI,
//  legends, and hint HUD observe.
//

import ShortcutKit
import ShortcutKitGlobal
import ShortcutKitUI
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

    let sessionMonitorContext = ShortcutContext<SessionMonitorAction>(
        "sessionMonitor",
        displayName: "Session Monitor"
    )

    static let migrations: [ShortcutMigration] = [
        .renameAction(context: "global", from: "editNote", to: "sessionMenu")
    ]

    let registry: ShortcutRegistry
    let hintPresenter: ShortcutHintPresenter
    let hintOptions = HintHUDOptions(placement: .top, presentation: .window)

    private let globalActivator = CarbonGlobalActivator()
    private var didStart = false

    private init() {
        let registry = ShortcutRegistry(
            contexts: [globalContext, sessionListContext, sessionMonitorContext],
            migrations: Self.migrations
        )
        self.registry = registry
        hintPresenter = ShortcutHintPresenter(registry: registry)
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
    // Key-window gating scopes ShortcutKit's per-activation handler to the receiving window.
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
