//
//  MenuBarView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var controller = SessionListController()
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.fair.rawValue
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
                ForEach(Array(sessionManager.sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRowView(
                        session: session,
                        isKeyboardSelected: controller.selectedIndex == index,
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
                           let backward = controller.shortcutCycleModeBackward
                        {
                            Text("\(forward.displayString)/\(backward.displayString) mode")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 280)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            controller.moveSelection(by: 1, sessionCount: sessionManager.sessions.count)
            controller.trackSelectedSession(sessions: sessionManager.sessions)
            return .handled
        }
        .onKeyPress(.upArrow) {
            controller.moveSelection(by: -1, sessionCount: sessionManager.sessions.count)
            controller.trackSelectedSession(sessions: sessionManager.sessions)
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
            controller.syncSelection(sessions: sessionManager.sessions)
        }
        .onChange(of: queueOrderMode) { _, newMode in
            if let mode = QueueOrderMode(rawValue: newMode) {
                sessionManager.reorderForMode(mode)
            }
        }
        .onAppear {
            controller.reloadShortcuts()
        }
    }

    private func activateSelected() {
        guard let index = controller.selectedIndex,
              index < sessionManager.sessions.count else { return }
        let session = sessionManager.sessions[index]
        Task {
            try? await TerminalActivation.activate(session: session, trigger: .guiSelect)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selection == mode.rawValue ? Color.accentColor : Color.clear)
                        .foregroundStyle(selection == mode.rawValue ? .white : .primary)
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
