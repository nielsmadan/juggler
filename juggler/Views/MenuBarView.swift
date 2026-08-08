//
//  MenuBarView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Carbon.HIToolbox
import ShortcutKit
import ShortcutKitUI
import SwiftUI

struct MenuBarView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var controller = SessionListController()
    @State private var isPopoverKey = false
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.default.rawValue
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true
    @AppStorage(AppStorageKeys.beaconEnabled) private var beaconEnabled = true
    @AppStorage(AppStorageKeys.autoAdvanceOnBusy) private var autoAdvanceOnBusy = false
    @AppStorage(AppStorageKeys.autoRestartOnIdle) private var autoRestartOnIdle = false
    @AppStorage(AppStorageKeys.prioritizePermissionSessions) private var prioritizePermissionSessions = false

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

                KeyBindingsLegendView(
                    registry: ShortcutCenter.shared.registry,
                    style: .panel,
                    contextIDs: ["sessionList"],
                    options: LegendOptions(compact: true)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 280)
        .background(WindowAccessor { controller.ownWindow = $0 })
        .keyWindowShortcutContext(ShortcutCenter.shared.sessionListContext, isActive: isPopoverKey) { action, _ in
            handleSessionListAction(action)
        }
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
        .sheet(item: $controller.sessionToRename) { session in
            RenameSessionView(session: session)
                .environment(sessionManager)
        }
        .onChange(of: sessionManager.sessions) { _, newSessions in
            controller.syncSelection(sessions: newSessions)
        }
        .onAppear {
            // `syncColor: false` — opening the popover must not retint the global cycling color.
            controller.ownerLabel = "MenuBar"
            if let initial = sessionManager.currentReferenceSessionID ?? sessionManager.sessions.first?.id {
                controller.setSelection(toSessionID: initial, syncColor: false)
            } else {
                controller.syncSelection(sessions: sessionManager.sessions)
            }
            isPopoverKey = controller.ownWindow?.isKeyWindow ?? true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window === controller.ownWindow {
                isPopoverKey = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window === controller.ownWindow {
                isPopoverKey = false
            }
        }
        .onChange(of: queueOrderMode) { _, newMode in
            if let mode = QueueOrderMode(rawValue: newMode) {
                sessionManager.reorderForMode(mode)
            }
        }
        .onChange(of: prioritizePermissionSessions) {
            if let mode = QueueOrderMode(rawValue: queueOrderMode) {
                sessionManager.reorderForPermissionPriority(prioritizePermissionSessions, mode: mode)
            }
        }
    }

    private var permissionFirstAvailable: Bool {
        QueueOrderMode(rawValue: queueOrderMode)?.supportsPermissionPriority == true
    }

    /// Dispatch a session-list shortcut while the popover is key. The toggle
    /// actions flip the same app-global settings the monitor's control-bar
    /// buttons do; since the popover has no button to reflect the new state, each
    /// confirms via a forced beacon message (shown regardless of the beacon
    /// setting itself).
    private func handleSessionListAction(_ action: SessionListAction) {
        switch action {
        case .activate: activateSelected()
        case .moveDown: controller.moveSelection(by: 1, in: sessionManager.sessions)
        case .moveUp: controller.moveSelection(by: -1, in: sessionManager.sessions)
        case .backburner: controller.backburnerSelected(sessionManager: sessionManager)
        case .sendToBack: controller.sendToBackSelected(sessionManager: sessionManager)
        case .reactivateSelected: controller.reactivateSelected(sessionManager: sessionManager)
        case .reactivateAll: controller.reactivateAll(sessionManager: sessionManager)
        case .rename: controller.renameSelected(sessions: sessionManager.sessions)
        case .cycleModeForward: queueOrderMode = controller.cycleMode(forward: true, currentMode: queueOrderMode)
        case .cycleModeBackward: queueOrderMode = controller.cycleMode(forward: false, currentMode: queueOrderMode)
        case .toggleBeacon:
            beaconEnabled.toggle()
            showToggleBeacon("Beacon", enabled: beaconEnabled)
        case .toggleAutoNext:
            autoAdvanceOnBusy.toggle()
            showToggleBeacon("Auto Next", enabled: autoAdvanceOnBusy)
        case .toggleAutoRestart:
            autoRestartOnIdle.toggle()
            showToggleBeacon("Auto Restart", enabled: autoRestartOnIdle)
        case .togglePermissionFirst:
            if permissionFirstAvailable {
                prioritizePermissionSessions.toggle()
                showToggleBeacon("Permission First", enabled: prioritizePermissionSessions)
            } else {
                BeaconManager.shared.show(sessionName: "Permission First N/A", force: true)
            }
        }
    }

    /// Flash a beacon confirming a toggle's new state. Forced so it appears even
    /// when the beacon overlay is itself disabled.
    private func showToggleBeacon(_ name: String, enabled: Bool) {
        BeaconManager.shared.show(sessionName: "\(name) \(enabled ? "Enabled" : "Disabled")", force: true)
    }

    private func activateSelected() {
        guard let id = controller.selectedSessionID,
              let session = sessionManager.sessions.first(where: { $0.id == id }) else { return }
        Task {
            _ = await SessionActivator.shared.activate(session: session, trigger: .guiSelect)
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
