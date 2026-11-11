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
    let presentation: PopoverPresentation
    @Environment(SessionManager.self) private var sessionManager
    @State private var controller = SessionListController()
    @State private var isPopoverKey = false
    @State private var listContentHeight: CGFloat = 0
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.default.rawValue
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true
    @AppStorage(AppStorageKeys.beaconEnabled) private var beaconEnabled = true
    @AppStorage(AppStorageKeys.autoAdvanceOnBusy) private var autoAdvanceOnBusy = false
    @AppStorage(AppStorageKeys.autoRestartOnIdle) private var autoRestartOnIdle = false
    @AppStorage(AppStorageKeys.prioritizePermissionSessions) private var prioritizePermissionSessions = false
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleModeRaw = SessionTitleMode.default.rawValue

    private var titleMode: SessionTitleMode {
        SessionTitleMode(rawValue: sessionTitleModeRaw) ?? .default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Juggler")
                    .font(.headline)
                Spacer()
                Button {
                    WindowManager.shared.openSettings()
                } label: {
                    Image(systemName: "gear")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Settings")
                .accessibilityLabel("Settings")
                Button {
                    WindowManager.shared.openMainWindow()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Open Session Monitor")
                .accessibilityLabel("Open Session Monitor")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            QueueModePicker(selection: $queueOrderMode)
                .padding(.bottom, 8)

            if let emptyState = sessionManager.listEmptyState {
                VStack(spacing: 6) {
                    Text(emptyState.title)
                    if emptyState == .allHidden {
                        Text(emptyState.description)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sessionManager.listedSessions) { session in
                                SessionRowView(
                                    session: session,
                                    controller: controller,
                                    isKeyboardSelected: controller.selectedSessionID == session.id,
                                    onActivate: { StatusBarManager.shared.hidePopover() }
                                )
                                .id(session.id)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listContentHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(listContentHeight, MenuBarLayout.sessionListMaxHeight))
                    .onAppear { scrollToSelection(proxy) }
                    .onChange(of: presentation.showCount) { scrollToSelection(proxy) }
                    .onChange(of: listContentHeight == 0) { scrollToSelection(proxy) }
                    .onChange(of: controller.selectedSessionID) { scrollToSelection(proxy) }
                    .onChange(of: sessionManager.listedSessions.map(\.id)) { scrollToSelection(proxy) }
                }
            }

            if showShortcutHelper {
                Divider()

                KeyBindingsLegendView(
                    registry: ShortcutCenter.shared.registry,
                    style: .embedded,
                    contextIDs: ["sessionList"],
                    options: LegendOptions(
                        columns: .fixed(2),
                        size: .small,
                        showsHeaderDivider: false,
                        labelWidth: .fixed(74)
                    ),
                    isIncluded: { entry in
                        SessionListAction(rawValue: entry.actionID)?.showsInMenuLegend ?? true
                    },
                    label: { entry in
                        SessionListAction(rawValue: entry.actionID)?.legendLabel
                    }
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
        .shortcutHintHUD(
            presenter: ShortcutCenter.shared.hintPresenter,
            options: ShortcutCenter.shared.hintOptions
        )
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            controller.moveSelection(by: 1, in: sessionManager.listedSessions)
            return .handled
        }
        .onKeyPress(.upArrow) {
            controller.moveSelection(by: -1, in: sessionManager.listedSessions)
            return .handled
        }
        .sheet(item: $controller.sessionToRename) { session in
            RenameSessionView(session: session)
                .environment(sessionManager)
        }
        .sheet(item: $controller.sessionToEditNote) { session in
            SessionNoteEditorView(
                sessionName: sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode),
                note: session.note,
                onSave: { note in
                    let saved = sessionManager.updateNote(for: session, note: note)
                    controller.sessionToEditNote = nil
                    if !saved {
                        BeaconManager.shared.show(sessionName: "Session No Longer Available", force: true)
                    }
                },
                onCancel: { controller.sessionToEditNote = nil }
            )
        }
        .onChange(of: sessionManager.listedSessions) { _, newSessions in
            controller.syncSelection(sessions: newSessions)
        }
        .onAppear {
            controller.ownerLabel = "MenuBar"
            controller.syncPopoverSelection(sessionManager: sessionManager)
            isPopoverKey = controller.ownWindow?.isKeyWindow ?? true
        }
        .onChange(of: presentation.showCount) {
            controller.syncPopoverSelection(sessionManager: sessionManager)
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

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        if let id = controller.selectedSessionID { proxy.scrollTo(id) }
    }

    private var permissionFirstAvailable: Bool {
        QueueOrderMode(rawValue: queueOrderMode)?.supportsPermissionPriority == true
    }

    /// Dispatch a session-list shortcut while the popover is key. The popover has no control-bar
    /// buttons to reflect toggled settings, so each toggle confirms via `showToggleBeacon`.
    private func handleSessionListAction(_ action: SessionListAction) {
        switch action {
        case .activate: activateSelected()
        case .moveDown: controller.moveSelection(by: 1, in: sessionManager.listedSessions)
        case .moveUp: controller.moveSelection(by: -1, in: sessionManager.listedSessions)
        case .backburner: controller.backburnerSelected(sessionManager: sessionManager)
        case .sendToBack: controller.sendToBackSelected(sessionManager: sessionManager)
        case .reactivateSelected: controller.reactivateSelected(sessionManager: sessionManager)
        case .reactivateAll: controller.reactivateAll(sessionManager: sessionManager)
        case .rename, .editNote: handleEditorAction(action)
        case .cycleModeForward: queueOrderMode = controller.cycleMode(forward: true, currentMode: queueOrderMode)
        case .cycleModeBackward: queueOrderMode = controller.cycleMode(forward: false, currentMode: queueOrderMode)
        case .toggleBeacon:
            beaconEnabled.toggle()
            showToggleBeacon(MonitorControlAction.beacon.title, enabled: beaconEnabled)
        case .toggleAutoNext:
            autoAdvanceOnBusy.toggle()
            showToggleBeacon(MonitorControlAction.autoNext.title, enabled: autoAdvanceOnBusy)
        case .toggleAutoRestart:
            autoRestartOnIdle.toggle()
            showToggleBeacon(MonitorControlAction.autoRestart.title, enabled: autoRestartOnIdle)
        case .togglePermissionFirst:
            if permissionFirstAvailable {
                prioritizePermissionSessions.toggle()
                showToggleBeacon(MonitorControlAction.permissionFirst.title, enabled: prioritizePermissionSessions)
            } else {
                BeaconManager.shared.show(sessionName: "\(MonitorControlAction.permissionFirst.title) N/A", force: true)
            }
        }
    }

    private func handleEditorAction(_ action: SessionListAction) {
        switch action {
        case .rename: controller.renameSelected(sessions: sessionManager.listedSessions)
        case .editNote: controller.editNoteSelected(sessions: sessionManager.listedSessions)
        default: assertionFailure("Unexpected editor action")
        }
    }

    /// Flash a beacon confirming a toggle's new state. Forced so it appears even
    /// when the beacon overlay is itself disabled.
    private func showToggleBeacon(_ name: String, enabled: Bool) {
        let message = "\(name) \(enabled ? "Enabled" : "Disabled")"
        BeaconManager.shared.show(sessionName: message, force: true)
        AccessibilityNotification.Announcement(message).post()
    }

    private func activateSelected() {
        guard let session = controller.selectedSession(in: sessionManager.listedSessions) else { return }
        Task {
            _ = await SessionActivator.shared.activate(session: session, trigger: .guiSelect, policy: .explicit)
        }
        StatusBarManager.shared.hidePopover()
    }
}

struct QueueModePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(QueueOrderMode.allCases, id: \.rawValue) { mode in
                Button {
                    let previous = QueueOrderMode(rawValue: selection)
                    guard previous != mode else { return }
                    selection = mode.rawValue
                    if let previous, let action = Self.shortcutAction(from: previous, to: mode) {
                        ShortcutCenter.shared.sessionListContext.notifyHint(for: action)
                    }
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
                .accessibilityAddTraits(selection == mode.rawValue ? .isSelected : [])
            }
        }
        .background(Color.gray.opacity(0.2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queue Order")
    }

    static func shortcutAction(from current: QueueOrderMode, to target: QueueOrderMode) -> SessionListAction? {
        guard current != target,
              let currentIndex = QueueOrderMode.allCases.firstIndex(of: current),
              let targetIndex = QueueOrderMode.allCases.firstIndex(of: target)
        else { return nil }

        let count = QueueOrderMode.allCases.count
        let forwardDistance = (targetIndex - currentIndex + count) % count
        let backwardDistance = (currentIndex - targetIndex + count) % count
        return forwardDistance <= backwardDistance ? .cycleModeForward : .cycleModeBackward
    }
}
