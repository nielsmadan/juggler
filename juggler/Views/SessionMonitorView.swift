//
//  SessionMonitorView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Carbon.HIToolbox
import ShortcutField
import SwiftUI

struct SessionMonitorView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.default.rawValue
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.enableStats) private var enableStats = true
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true
    @AppStorage(AppStorageKeys.beaconEnabled) private var beaconEnabled = true
    @AppStorage(AppStorageKeys.autoAdvanceOnBusy) private var autoAdvanceOnBusy = false
    @AppStorage(AppStorageKeys.autoRestartOnIdle) private var autoRestartOnIdle = false
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleModeRaw: String = SessionTitleMode
        .default.rawValue
    @AppStorage(AppStorageKeys.controlBarHintDismissed) private var controlBarHintDismissed = false

    private var titleMode: SessionTitleMode {
        SessionTitleMode(rawValue: sessionTitleModeRaw) ?? .default
    }

    private var controlBarDividerColor: Color {
        colorScheme == .dark
            ? Color(red: 205 / 255, green: 205 / 255, blue: 205 / 255)
            : Color(red: 50 / 255, green: 50 / 255, blue: 50 / 255)
    }

    @State private var controller = SessionListController()
    @State private var isMonitorWindowKey = false
    /// Per-session Today-tab rendered width, captured via PreferenceKey so the
    /// state badge can align its horizontal center with the tab's diagonal apex.
    @State private var todayTabWidths: [String: CGFloat] = [:]

    @Namespace private var sessionAnimation

    private var groupedSessions: [(key: String, value: [Session])] {
        let grouped = Dictionary(grouping: sessionManager.sessions) { session in
            session.terminalWindowName ?? "Unknown"
        }
        return grouped.map { (key: $0.key, value: $0.value.sorted { $0.startedAt < $1.startedAt }) }
            .sorted { $0.key < $1.key }
    }

    private func flatIndex(for session: Session) -> Int? {
        sessionManager.sessions.firstIndex(where: { $0.id == session.id })
    }

    private var animationController: SectionAnimationController {
        sessionManager.animationController
    }

    private enum SectionRow: Identifiable {
        case header(SectionType, String)
        case session(Session)
        case placeholder(SectionType)
        case divider(SectionType, String)

        var id: String {
            switch self {
            case let .header(section, _):
                "header-\(section.rawValue)"
            case let .session(session):
                "session-\(session.id)"
            case let .placeholder(section):
                "empty-\(section.rawValue)"
            case let .divider(section, sessionID):
                "divider-\(section.rawValue)-\(sessionID)"
            }
        }
    }

    private func sessionsForSection(_ section: SectionType) -> [Session] {
        sessionManager.sessions.filter { session in
            animationController.effectiveSection(for: session) == section
        }
    }

    private var sectionedRows: [SectionRow] {
        var rows: [SectionRow] = []
        let sections: [(SectionType, String)] = [
            (.idle, "Idle"),
            (.working, "Working"),
            (.backburner, "Backburner")
        ]

        for (section, title) in sections {
            rows.append(.header(section, title))
            let sessions = sessionsForSection(section)
            if sessions.isEmpty {
                rows.append(.placeholder(section))
            } else {
                for (index, session) in sessions.enumerated() {
                    rows.append(.session(session))
                    if index < sessions.count - 1 {
                        rows.append(.divider(section, session.id))
                    }
                }
            }
        }

        return rows
    }

    private var highlightColor: Color {
        useCyclingColors ? sessionManager.activeColor : Color.accentColor
    }

    var body: some View {
        mainContent
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
            .onKeyPress { handleKeyPress($0) }
            .sheet(item: $controller.sessionToRename) { session in
                RenameSessionView(session: session)
                    .environment(sessionManager)
            }
            .onChange(of: sessionManager.sessions) { _, newSessions in
                controller.syncSelection(sessions: newSessions)
                let alive = Set(newSessions.map(\.id))
                todayTabWidths = todayTabWidths.filter { alive.contains($0.key) }
            }
            .onAppear {
                controller.syncSelection(sessions: sessionManager.sessions)
                controller.reloadShortcuts()
                controller.installTabMonitor(
                    sessionManager: sessionManager,
                    queueOrderMode: $queueOrderMode,
                    extraHandler: { event in
                        if let shortcut = controller.shortcutToggleAutoNext, shortcut.matches(event) {
                            autoAdvanceOnBusy.toggle()
                            return true
                        }
                        if let shortcut = controller.shortcutToggleAutoRestart, shortcut.matches(event) {
                            autoRestartOnIdle.toggle()
                            return true
                        }
                        return false
                    }
                )
            }
            .onDisappear {
                controller.removeTabMonitor()
            }
            .onChange(of: queueOrderMode) { _, newMode in
                if let mode = QueueOrderMode(rawValue: newMode) {
                    sessionManager.reorderForMode(mode)
                }
            }
            .onChange(of: sessionManager.currentSession?.id) { _, _ in
                if let current = sessionManager.currentSession,
                   let index = sessionManager.sessions.firstIndex(where: { $0.id == current.id }) {
                    controller.setSelection(to: index, sessions: sessionManager.sessions)
                }
            }
            .onChange(of: sessionManager.focusedSessionID) { _, newFocusedID in
                guard let focusedID = newFocusedID else { return }
                if let index = sessionManager.sessions.firstIndex(where: {
                    $0.terminalSessionID == focusedID || $0.id == focusedID
                }) {
                    controller.setSelection(to: index, sessions: sessionManager.sessions)
                }
            }
            .onChange(of: sessionManager.isSessionFocused) { _, isFocused in
                // Resync selectedIndex when a terminal becomes active, so arrow-key
                // drift in the monitor doesn't persist when returning to the terminal.
                // Skip if an activation is in flight — the focus event for the target
                // session hasn't arrived yet, so resyncing would flash the old session.
                if isFocused, sessionManager.activationTarget == nil,
                   let focusedID = sessionManager.focusedSessionID,
                   let index = sessionManager.sessions.firstIndex(where: {
                       $0.terminalSessionID == focusedID || $0.id == focusedID
                   }) {
                    controller.setSelection(to: index, sessions: sessionManager.sessions)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .localShortcutsDidChange)) { _ in
                controller.reloadShortcuts()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, window.identifier?.rawValue == "main" {
                    isMonitorWindowKey = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, window.identifier?.rawValue == "main" {
                    isMonitorWindowKey = false
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            controlBar
            if !controlBarHintDismissed {
                HStack {
                    Text("Hover over buttons to show help.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Dismiss") {
                        controlBarHintDismissed = true
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            if sessionManager.sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "terminal",
                    description: Text(
                        "Start or continue a session and it will show up here.\n\nCodex sessions appear after your first message."
                    )
                )
                .frame(maxHeight: .infinity)
            } else {
                sessionList
            }
            if enableStats, !sessionManager.sessions.isEmpty {
                Divider()
                StatsChartView()
            }
            if showShortcutHelper, !sessionManager.sessions.isEmpty {
                Divider()
                shortcutsReference
            }
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if queueOrderMode == QueueOrderMode.grouped.rawValue {
            List {
                ForEach(groupedSessions, id: \.key) { windowName, sessions in
                    Section(header: Text(windowName)) {
                        ForEach(sessions) { session in
                            listSessionRow(session)
                        }
                    }
                }
            }
        } else if queueOrderMode == QueueOrderMode.static.rawValue {
            List {
                ForEach(sessionManager.sessions) { session in
                    listSessionRow(session)
                }
            }
        } else {
            // Fair/Prio mode: use a single stack so UP moves can animate smoothly.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sectionedRows) { row in
                        switch row {
                        case let .header(_, title):
                            sectionHeader(title)
                        case let .session(session):
                            scrollViewSessionRow(session)
                        case .placeholder:
                            emptyPlaceholder
                                .padding(.horizontal, 16)
                        case .divider:
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .animation(
                    .easeInOut(duration: SectionAnimationTiming.upMoveDuration),
                    value: sessionManager.sessions.map(\.id)
                )
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyPlaceholder: some View {
        HStack {
            Spacer()
            Text("No sessions")
                .foregroundStyle(.tertiary)
                .font(.subheadline)
            Spacer()
        }
        .frame(minHeight: 66)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            QueueModePicker(selection: $queueOrderMode)

            Rectangle()
                .fill(controlBarDividerColor)
                .frame(width: 2)

            toggleButton(isOn: $autoAdvanceOnBusy, icon: "forward.fill",
                         activeColor: CyclingColors.palette[0],
                         help: "Auto-advance: go to next session when current goes busy")
            toggleButton(isOn: $autoRestartOnIdle, icon: "autostartstop",
                         activeColor: CyclingColors.palette[3],
                         help: "Auto-restart: when all sessions are busy and one becomes idle, jump to it")
            toggleButton(isOn: $beaconEnabled, icon: "light.panel",
                         activeColor: CyclingColors.palette[4],
                         help: "Beacon: show session name when cycling")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
    }

    private func toggleButton(isOn: Binding<Bool>, icon: String, activeColor: Color, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
                .font(.callout)
                .frame(width: 16, height: 16)
                .frame(width: 32)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? activeColor : Color.clear)
                .foregroundStyle(isOn.wrappedValue ? .white : .primary)
                .contentShape(Rectangle())
                .help(help)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row Views

    /// Terminal-type icon, agent initials, and an SSH tag for remote sessions.
    @ViewBuilder
    private func agentColumn(_ session: Session) -> some View {
        VStack(spacing: 2) {
            Image(systemName: session.terminalType.iconName)
            Text(session.agentShortName)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            if let remoteHost = session.remoteHost {
                Text("SSH")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .help(remoteHost)
            }
        }
        .padding(.top, 2)
    }

    /// Row view for List (static mode)
    @ViewBuilder
    private func listSessionRow(_ session: Session) -> some View {
        let index = flatIndex(for: session)
        HStack(alignment: .top, spacing: 8) {
            agentColumn(session)
            // List rows have no outer horizontal padding — the List itself manages insets.
            sessionContent(session, rowHorizontalPadding: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            if enableStats {
                BusyStatsCorner(
                    session: session,
                    highlightColor: highlightColor,
                    isActive: isActiveRow(index: index)
                )
            }
        }
        .onPreferenceChange(TodayTabWidthKey.self) { width in
            if width > 0 { todayTabWidths[session.id] = width }
        }
        .contentShape(Rectangle())
        .listRowBackground(
            isActiveRow(index: index)
                ? highlightColor.opacity(0.15)
                : Color.clear
        )
        .onTapGesture {
            activateSession(session)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func isActiveRow(index: Int?) -> Bool {
        (sessionManager.isSessionFocused || isMonitorWindowKey) && controller.selectedIndex == index
    }

    /// Row view for ScrollView (Fair/Prio mode with animations)
    @ViewBuilder
    private func scrollViewSessionRow(_ session: Session) -> some View {
        let index = flatIndex(for: session)
        let isDownAnimation = animationController.isDownAnimating(sessionID: session.id)

        let row = HStack(alignment: .top, spacing: 8) {
            agentColumn(session)
            // ScrollView rows apply 16pt horizontal padding (see below).
            sessionContent(session, rowHorizontalPadding: 16)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActiveRow(index: index)
                ? highlightColor.opacity(0.15)
                : Color.clear
        )
        .overlay(alignment: .bottomTrailing) {
            if enableStats {
                BusyStatsCorner(
                    session: session,
                    highlightColor: highlightColor,
                    isActive: isActiveRow(index: index)
                )
            }
        }
        .onPreferenceChange(TodayTabWidthKey.self) { width in
            if width > 0 { todayTabWidths[session.id] = width }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activateSession(session)
        }
        .transition(.asymmetric(
            insertion: isDownAnimation ? .curvedEnterFromAbove : .fadeInFromAbove,
            removal: isDownAnimation ? .curvedExitDown : .identity
        ))

        if isDownAnimation {
            row
        } else {
            row.matchedGeometryEffect(id: session.id, in: sessionAnimation)
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: Session, rowHorizontalPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sessionHeader(session, rowHorizontalPadding: rowHorizontalPadding)
            sessionMetadata(session)
        }
    }

    /// State-badge x offset that keeps the badge's vertical center aligned
    /// with the Today tab's diagonal apex. Falls back to a reasonable default
    /// (matches a short-value tab with the calendar icon) until the
    /// PreferenceKey populates the actual rendered width.
    ///
    /// `rowHorizontalPadding` must match the row's outer `.padding(.horizontal, X)`
    /// — differs between row variants (List = 0, ScrollView = 16).
    private func stateBadgeOffset(for session: Session, rowHorizontalPadding: CGFloat) -> CGFloat {
        // Natural badge center-x (no offset) sits at:
        //   row_right - rowHorizontalPadding - StateBadgeLayout.centerXFromRight.
        // Today apex_x = row_right - todayWidth + tabDiagonalOffset.
        // Required offset = apex_x - natural center.
        let todayWidth = todayTabWidths[session.id] ?? 65
        return (BusyStatsCornerLayout.tabDiagonalOffset + rowHorizontalPadding + StateBadgeLayout.centerXFromRight)
            - todayWidth
    }

    @ViewBuilder
    private func sessionHeader(_ session: Session, rowHorizontalPadding: CGFloat) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode))
                        .font(.headline)
                    Button {
                        controller.sessionToRename = session
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Label(session.projectPath, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: session.state.iconName)
                    .font(.system(size: 16))
                Text(session.state.displayText)
                    .font(.caption)
            }
            .frame(width: StateBadgeLayout.frameWidth)
            .padding(.trailing, StateBadgeLayout.trailingPadding)
            // Shift the badge horizontally so its vertical center sits at the
            // same x as the Today tab's diagonal apex. Offset is recomputed
            // whenever the Today tab's width changes (via PreferenceKey).
            .offset(x: stateBadgeOffset(for: session, rowHorizontalPadding: rowHorizontalPadding))
        }
    }

    @ViewBuilder
    private func sessionMetadata(_ session: Session) -> some View {
        HStack {
            if let branch = session.gitBranch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let result = controller.handleKeyPress(press, sessionManager: sessionManager, queueOrderMode: &queueOrderMode)
        if result == .handled { return .handled }

        if let shortcut = controller.shortcutToggleBeacon, shortcut.matches(press) {
            beaconEnabled.toggle()
            return .handled
        }
        if let shortcut = controller.shortcutToggleAutoNext, shortcut.matches(press) {
            autoAdvanceOnBusy.toggle()
            return .handled
        }
        if let shortcut = controller.shortcutToggleAutoRestart, shortcut.matches(press) {
            autoRestartOnIdle.toggle()
            return .handled
        }
        return .ignored
    }

    private func activateSelected() {
        guard let index = controller.selectedIndex,
              index < sessionManager.sessions.count else { return }
        activateSession(sessionManager.sessions[index])
    }

    private func activateSession(_ session: Session) {
        // Only update color when clicking a different session (not Enter on already-selected)
        if let index = sessionManager.sessions.firstIndex(where: { $0.id == session.id }),
           controller.selectedIndex != index {
            sessionManager.setColorIndex(to: index)
        }
        sessionManager.beginActivation(targetSessionID: session.id)
        Task {
            try? await TerminalActivation.activate(session: session, trigger: .guiSelect)
            sessionManager.endActivation()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        SessionStatsCalculator.formatDuration(seconds)
    }

    // MARK: - Shortcuts Reference

    @ViewBuilder
    private var shortcutsReference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shortcuts")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180))], alignment: .leading, spacing: 2) {
                shortcutRow("↑/↓", "Navigate")
                shortcutRow("↵", "Activate")
                shortcutRow(controller.shortcutMoveUp?.displayString ?? "–", "Move Up")
                shortcutRow(controller.shortcutMoveDown?.displayString ?? "–", "Move Down")
                shortcutRow(controller.shortcutBackburner?.displayString ?? "–", "Backburner")
                shortcutRow(controller.shortcutReactivateSelected?.displayString ?? "–", "Reactivate")
                shortcutRow(controller.shortcutReactivateAll?.displayString ?? "–", "Reactivate All")
                shortcutRow(controller.shortcutRename?.displayString ?? "–", "Rename")
                shortcutRow(controller.shortcutCycleModeForward?.displayString ?? "–", "Mode →")
                shortcutRow(controller.shortcutCycleModeBackward?.displayString ?? "–", "Mode ←")
                shortcutRow(controller.shortcutToggleBeacon?.displayString ?? "–", "Toggle Beacon")
                shortcutRow(controller.shortcutToggleAutoNext?.displayString ?? "–", "Auto Next")
                shortcutRow(controller.shortcutToggleAutoRestart?.displayString ?? "–", "Auto Restart")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 48, alignment: .trailing)
            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Parabolic Arc Transition for DOWN Animations

private struct FadeFromAboveModifier: ViewModifier {
    let yOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(y: yOffset).opacity(opacity)
    }
}

private struct ParabolicArcEffect: GeometryEffect {
    var progress: CGFloat
    let endX: CGFloat
    let endY: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        let x = endX * progress
        let y = endY * progress * progress
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

extension AnyTransition {
    static var curvedExitDown: AnyTransition {
        .modifier(
            active: ParabolicArcEffect(progress: 1, endX: 300, endY: 40),
            identity: ParabolicArcEffect(progress: 0, endX: 300, endY: 40)
        ).combined(with: .opacity)
    }

    static var fadeInFromAbove: AnyTransition {
        .modifier(
            active: FadeFromAboveModifier(yOffset: -20, opacity: 0),
            identity: FadeFromAboveModifier(yOffset: 0, opacity: 1)
        )
    }

    static var curvedEnterFromAbove: AnyTransition {
        .modifier(
            active: ParabolicArcEffect(progress: 1, endX: 300, endY: -40),
            identity: ParabolicArcEffect(progress: 0, endX: 300, endY: -40)
        ).combined(with: .opacity)
    }
}
