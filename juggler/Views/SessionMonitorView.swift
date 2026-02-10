//
//  SessionMonitorView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Combine
import SwiftUI

struct SessionMonitorView: View {
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.fair.rawValue
    @AppStorage(AppStorageKeys.groupByWindow) private var groupByWindow: Bool = true
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.enableStats) private var enableStats = true
    @AppStorage(AppStorageKeys.idleSessionColoring) private var idleSessionColoring = true
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true
    @State private var controller = SessionListController()
    @State private var globalStatsResetDate: Date?
    @State private var isPaused = false

    // Namespace for matchedGeometryEffect animations between sections
    @Namespace private var sessionAnimation

    private var isGroupingAvailable: Bool {
        queueOrderMode == QueueOrderMode.static.rawValue
    }

    private var shouldShowGrouped: Bool {
        isGroupingAvailable && groupByWindow
    }

    private var groupedSessions: [(key: String, value: [Session])] {
        let grouped = Dictionary(grouping: sessionManager.sessions) { session in
            session.terminalWindowName ?? "Unknown"
        }
        // Sort groups alphabetically, and sessions within groups by startedAt
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
            (.busy, "Busy"),
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

    private func highlightColor(at index: Int) -> Color {
        if useCyclingColors {
            CyclingColors.palette[index % CyclingColors.palette.count]
        } else {
            Color.accentColor
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            mainContent
        }
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
            }
            .onAppear {
                controller.syncSelection(sessions: sessionManager.sessions)
            }
            .onChange(of: queueOrderMode) { _, newMode in
                if let mode = QueueOrderMode(rawValue: newMode) {
                    sessionManager.reorderForMode(mode)
                }
            }
            .onChange(of: sessionManager.currentSession?.id) { _, _ in
                // Sync selectedIndex when currentSession changes
                if let current = sessionManager.currentSession,
                   let index = sessionManager.sessions.firstIndex(where: { $0.id == current.id }) {
                    controller.selectedIndex = index
                    controller.trackSelectedSession(sessions: sessionManager.sessions)
                }
            }
            .onChange(of: sessionManager.focusedSessionID) { _, newFocusedID in
                // Sync selectedIndex when focus changes (direct observer for reliability)
                guard let focusedID = newFocusedID else { return }
                if let index = sessionManager.sessions.firstIndex(where: {
                    $0.terminalSessionID == focusedID || $0.terminalSessionID.hasSuffix(focusedID)
                }) {
                    controller.selectedIndex = index
                    controller.trackSelectedSession(sessions: sessionManager.sessions)
                }
            }
            .onAppear {
                controller.reloadShortcuts()
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if sessionManager.sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "terminal",
                    description: Text("Start or continue a session and it will show up here")
                )
                .frame(maxHeight: .infinity)
            } else {
                sessionList
            }
            if enableStats, !sessionManager.sessions.isEmpty {
                Divider()
                statsFooter
            }
            if showShortcutHelper, !sessionManager.sessions.isEmpty {
                Divider()
                shortcutsReference
            }
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if queueOrderMode == QueueOrderMode.static.rawValue {
            // Static mode: use List for groupByWindow support
            List {
                if shouldShowGrouped {
                    ForEach(groupedSessions, id: \.key) { windowName, sessions in
                        Section(header: Text(windowName)) {
                            ForEach(sessions) { session in
                                listSessionRow(session)
                            }
                        }
                    }
                } else {
                    ForEach(sessionManager.sessions) { session in
                        listSessionRow(session)
                    }
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
                // Animate layout changes when session ordering changes.
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
        HStack {
            Picker("Order", selection: $queueOrderMode) {
                ForEach(QueueOrderMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Toggle("Group by Window", isOn: Binding(
                get: { isGroupingAvailable && groupByWindow },
                set: { groupByWindow = $0 }
            ))
            .disabled(!isGroupingAvailable)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Row Views

    /// Row view for List (static mode)
    @ViewBuilder
    private func listSessionRow(_ session: Session) -> some View {
        let index = flatIndex(for: session)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "apple.terminal.fill")
                .padding(.top, 2)
            sessionContent(session)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(
            controller.selectedIndex == index
                ? highlightColor(at: index ?? 0).opacity(0.15)
                : Color.clear
        )
        .onTapGesture {
            activateSession(session)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    /// Row view for ScrollView (Fair/Prio mode with animations)
    @ViewBuilder
    private func scrollViewSessionRow(_ session: Session) -> some View {
        let index = flatIndex(for: session)
        let isDownAnimation = animationController.isDownAnimating(sessionID: session.id)

        let row = HStack(alignment: .top, spacing: 8) {
            Image(systemName: "apple.terminal.fill")
                .padding(.top, 2)
            sessionContent(session)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            controller.selectedIndex == index
                ? highlightColor(at: index ?? 0).opacity(0.15)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            activateSession(session)
        }
        // DOWN: slide out right + fade out, delay offscreen, slide in from right + fade in.
        // UP: handled by matchedGeometryEffect (pure vertical move). No insertion/removal transition.
        .transition(isDownAnimation ? .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ) : .identity)

        if isDownAnimation {
            row
        } else {
            // Keep matchedGeometryEffect enabled so UP moves can interpolate from the previous layout.
            row.matchedGeometryEffect(id: session.id, in: sessionAnimation)
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sessionHeader(session)
            sessionMetadata(session)
        }
    }

    @ViewBuilder
    private func sessionHeader(_ session: Session) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(sessionManager.disambiguatedDisplayName(for: session))
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
            .frame(width: 70)
            .padding(.trailing, 4)
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
            idleStatsView(for: session)
        }
    }

    @ViewBuilder
    private func idleStatsView(for session: Session) -> some View {
        if enableStats {
            HStack(spacing: 4) {
                if session.state == .idle || session.state == .permission {
                    Text("idle")
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(formatDuration(session.currentIdleDuration ?? 0))
                        .frame(minWidth: 28, alignment: .trailing)
                    Text("|")
                }
                if session.state == .working || session.state == .compacting {
                    Text("air")
                        .frame(minWidth: 16, alignment: .trailing)
                    Text(formatDuration(session.currentWorkingDuration ?? 0))
                        .frame(minWidth: 28, alignment: .trailing)
                    Text("|")
                }
                Text("total")
                    .frame(minWidth: 24, alignment: .trailing)
                Text(formatDuration(session.totalIdleTime))
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(minHeight: 16)
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Try shared shortcuts first
        let result = controller.handleKeyPress(press, sessionManager: sessionManager, queueOrderMode: &queueOrderMode)
        if result == .handled { return .handled }

        // Monitor-specific keys
        if enableStats, press.characters.lowercased() == "s" {
            isPaused.toggle()
            return .handled
        } else if enableStats, press.characters.lowercased() == "r" {
            globalStatsResetDate = Date()
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
        Task {
            try? await TerminalActivation.activate(session: session, trigger: .guiSelect)
        }
    }

    // MARK: - Duration Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds) / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h\(String(format: "%02d", remainingMinutes))"
    }

    // MARK: - Stats Footer

    private var totalIdleTimeForFooter: TimeInterval {
        guard !isPaused else { return 0 }
        return sessionManager.sessions.reduce(0) { total, session in
            guard let resetDate = globalStatsResetDate else {
                return total + session.totalIdleTime
            }

            // Only count idle time after reset
            if session.startedAt >= resetDate {
                return total + session.totalIdleTime
            }

            // Session existed before reset - only count current idle period if it started after reset
            if let lastBecameIdle = session.lastBecameIdle, lastBecameIdle >= resetDate {
                return total + (session.currentIdleDuration ?? 0)
            }

            return total
        }
    }

    private var totalWorkingTimeForFooter: TimeInterval {
        guard !isPaused else { return 0 }
        return sessionManager.sessions.reduce(0) { total, session in
            guard let resetDate = globalStatsResetDate else {
                return total + session.totalWorkingTime
            }

            // Only count working time after reset
            if session.startedAt >= resetDate {
                return total + session.totalWorkingTime
            }

            // Session existed before reset - only count current working period if it started after reset
            if let lastBecameWorking = session.lastBecameWorking, lastBecameWorking >= resetDate {
                return total + (session.currentWorkingDuration ?? 0)
            }

            return total
        }
    }

    private var idlePercentage: Double {
        guard !sessionManager.sessions.isEmpty else { return 1.0 }
        let idleCount = sessionManager.sessions.filter {
            $0.state == .idle || $0.state == .permission
        }.count
        return Double(idleCount) / Double(sessionManager.sessions.count)
    }

    private var footerGradientColor: Color {
        // Muted green (0% idle = all working) to muted red (100% idle = all waiting)
        Color(
            red: 0.3 + (0.3 * idlePercentage),
            green: 0.5 - (0.2 * idlePercentage),
            blue: 0.3
        )
    }

    @ViewBuilder
    private var statsFooter: some View {
        let idleCount = sessionManager.sessions.filter {
            $0.state == .idle || $0.state == .permission
        }.count
        let totalCount = sessionManager.sessions.count

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(idleCount)/\(totalCount) sessions idle")
                    .font(.subheadline)
                Text("\(formatDuration(totalIdleTimeForFooter)) total idle")
                    .font(.subheadline)
                Text("\(formatDuration(totalWorkingTimeForFooter)) airtime")
                    .font(.subheadline)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    globalStatsResetDate = Date()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    isPaused.toggle()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(idleSessionColoring ? footerGradientColor.opacity(0.3) : Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Shortcuts Reference

    @ViewBuilder
    private var shortcutsReference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shortcuts")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160))], alignment: .leading, spacing: 2) {
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
                shortcutRow("S", "Start/Pause")
                shortcutRow("R", "Reset Stats")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .frame(minWidth: 40, alignment: .trailing)
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
