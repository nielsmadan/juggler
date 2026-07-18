//
//  MenuBarView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Carbon.HIToolbox
import ShortcutField
import SwiftUI

struct MenuBarView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var controller = SessionListController()
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.default.rawValue
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Juggler")
                    .font(.headline)
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gear")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                Button {
                    openMainWindow()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            QueueModePicker(selection: $queueOrderMode)
                .padding(.bottom, 8)

            if sessionManager.sessions.isEmpty {
                Text("No sessions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(sessionManager.sessions) { session in
                    SessionRowView(
                        session: session,
                        isKeyboardSelected: controller.selectedSessionID == session.id,
                        onActivate: { dismiss() }
                    )
                    .id(session.id)
                }
            }

            if showShortcutHelper {
                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        if let up = controller.shortcutMoveUp, let down = controller.shortcutMoveDown {
                            Text("\(up.displayString)/\(down.displayString) navigate")
                        }
                        if let backburner = controller.shortcutBackburner {
                            Text("\(backburner.displayString) backburner")
                        }
                        if let sendToBack = controller.shortcutSendToBack {
                            Text("\(sendToBack.displayString) send to back")
                        }
                        if let reactivate = controller.shortcutReactivateSelected {
                            Text("\(reactivate.displayString) reactivate")
                        }
                    }
                    HStack(spacing: 12) {
                        if let reactivateAll = controller.shortcutReactivateAll {
                            Text("\(reactivateAll.displayString) reactivate all")
                        }
                        if let rename = controller.shortcutRename {
                            Text("\(rename.displayString) rename")
                        }
                        if let forward = controller.shortcutCycleModeForward,
                           let backward = controller.shortcutCycleModeBackward {
                            Text("\(forward.displayString)/\(backward.displayString) mode")
                        }
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 280)
        .background(WindowAccessor { controller.ownWindow = $0 })
        .suppressShortcutBeep()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            controller.moveSelection(by: 1, in: sessionManager.sessions)
            return .handled
        }
        .onKeyPress(.upArrow) {
            controller.moveSelection(by: -1, in: sessionManager.sessions)
            return .handled
        }
        .onKeyPress(.return) { activateSelected(); return .handled }
        .onKeyPress { press in
            controller.handleKeyPress(press, sessionManager: sessionManager, queueOrderMode: &queueOrderMode)
        }
        .sheet(item: $controller.sessionToRename) { session in
            RenameSessionView(session: session)
                .environment(sessionManager)
        }
        .onChange(of: sessionManager.sessions) { _, newSessions in
            controller.syncSelection(sessions: newSessions)
        }
        .onAppear {
            // Always open on the focused/current session (or the top row), so the
            // popover never shows a stale selection left over from a prior open.
            // `syncColor: false` — opening the popover must not retint the global
            // cycling color (shared with the main monitor / beacon / terminal tabs).
            if let initial = sessionManager.currentReferenceSessionID ?? sessionManager.sessions.first?.id {
                controller.setSelection(toSessionID: initial, syncColor: false)
            } else {
                controller.syncSelection(sessions: sessionManager.sessions)
            }
            controller.reloadShortcuts()
            controller.installKeyMonitor(
                owner: "MenuBar",
                sessionManager: sessionManager,
                queueOrderMode: $queueOrderMode,
                visibleSessions: { sessionManager.sessions }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .localShortcutsDidChange)) { _ in
            controller.reloadShortcuts()
        }
        .onDisappear {
            controller.removeKeyMonitor()
        }
        .onChange(of: queueOrderMode) { _, newMode in
            if let mode = QueueOrderMode(rawValue: newMode) {
                sessionManager.reorderForMode(mode)
            }
        }
    }

    private func activateSelected() {
        guard let id = controller.selectedSessionID,
              let session = sessionManager.sessions.first(where: { $0.id == id }) else { return }
        Task {
            do {
                try await TerminalActivation.activate(session: session, trigger: .guiSelect)
            } catch {
                BeaconManager.shared.show(sessionName: "Activation Failed", force: true)
            }
        }
        dismiss()
    }

    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        StatusBarManager.shared.openSettings()
    }
}

struct QueueModePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(QueueOrderMode.allCases, id: \.rawValue) { mode in
                Button {
                    selection = mode.rawValue
                } label: {
                    Text(mode.displayName)
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selection == mode.rawValue ? Color(
                            red: 144 / 255,
                            green: 104 / 255,
                            blue: 212 / 255
                        ) : Color.clear)
                        .foregroundStyle(selection == mode.rawValue ? .white : .primary)
                        .contentShape(Rectangle())
                        .help(mode.helpText)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.gray.opacity(0.2))
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}
