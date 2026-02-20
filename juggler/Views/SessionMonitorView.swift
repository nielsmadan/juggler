//
//  SessionMonitorView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import Carbon.HIToolbox
import Combine
import SwiftUI

struct SessionMonitorView: View {
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.fair.rawValue
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.enableStats) private var enableStats = true
    @AppStorage(AppStorageKeys.idleSessionColoring) private var idleSessionColoring = true
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true
    @AppStorage(AppStorageKeys.beaconEnabled) private var beaconEnabled = true
    @AppStorage(AppStorageKeys.autoAdvanceOnBusy) private var autoAdvanceOnBusy = false
    @AppStorage(AppStorageKeys.autoRestartOnIdle) private var autoRestartOnIdle = false
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleModeRaw: String = SessionTitleMode.tabTitle
        .rawValue

    private var titleMode: SessionTitleMode {
        SessionTitleMode(rawValue: sessionTitleModeRaw) ?? .tabTitle
    }

    @State private var controller = SessionListController()
    @State private var globalStatsResetDate: Date?
    @State private var isPaused = false
    @State private var showModesInfo = false

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
            (.backburner, "Backburner"),
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
            controller.reloadShortcuts()
            controller.installTabMonitor(
                sessionManager: sessionManager,
                queueOrderMode: $queueOrderMode,
                extraHandler: { event in
                    if enableStats, let shortcut = controller.shortcutTogglePause, shortcut.matches(event) {
                        isPaused.toggle()
                        return true
                    }
                    if enableStats, let shortcut = controller.shortcutResetStats, shortcut.matches(event) {
                        globalStatsResetDate = Date()
                        return true
                    }
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
               let index = sessionManager.sessions.firstIndex(where: { $0.id == current.id })
            {
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
        .onReceive(NotificationCenter.default.publisher(for: .localShortcutsDidChange)) { _ in
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
        HStack(spacing: 8) {
            QueueModePicker(selection: $queueOrderMode)
                .frame(maxWidth: 260)

            Button {
                showModesInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModesInfo) {
                VStack(alignment: .leading, spacing: 2) {
                    modeRow("Fair", "Idle sessions go to end of queue")
                    modeRow("Prio", "Idle sessions go to top of queue")
                    modeRow("Static", "No automatic reordering")
                    modeRow("Grouped", "Static + grouped by window")
                }
                .padding()
            }

            Spacer()

            Toggle(isOn: $autoAdvanceOnBusy) {
                Image(systemName: "forward.fill")
            }
            .toggleStyle(.button)
            .help("Auto-advance: go to next session when current goes busy")

            Toggle(isOn: $autoRestartOnIdle) {
                Image(systemName: "autostartstop")
            }
            .toggleStyle(.button)
            .help("Auto-restart: jump to session when it becomes idle and all others are busy")

            Toggle(isOn: $beaconEnabled) {
                Image(systemName: "light.panel")
            }
            .toggleStyle(.button)
            .help("Beacon: show session name when cycling")
        }
        .padding(.trailing)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Row Views

    /// Row view for List (static mode)
    @ViewBuilder
    private func listSessionRow(_ session: Session) -> some View {
        let index = flatIndex(for: session)
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Image(systemName: session.terminalType.iconName)
                Text(session.agentShortName)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            sessionContent(session)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(
            sessionManager.isSessionFocused && controller.selectedIndex == index
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
            VStack(spacing: 2) {
                Image(systemName: session.terminalType.iconName)
                Text(session.agentShortName)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            sessionContent(session)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            sessionManager.isSessionFocused && controller.selectedIndex == index
                ? highlightColor(at: index ?? 0).opacity(0.15)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            activateSession(session)
        }
        // New sessions: fade in from above. DOWN arrivals: parabolic arc from right.
        // DOWN removal: parabolic arc out (right + down). UP: matchedGeometryEffect handles vertical move.
        .transition(.asymmetric(
            insertion: isDownAnimation ? .curvedEnterFromAbove : .fadeInFromAbove,
            removal: isDownAnimation ? .curvedExitDown : .identity
        ))

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
                    Text("working")
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
        let result = controller.handleKeyPress(press, sessionManager: sessionManager, queueOrderMode: &queueOrderMode)
        if result == .handled { return .handled }

        if enableStats, let shortcut = controller.shortcutTogglePause, shortcut.matches(press) {
            isPaused.toggle()
            return .handled
        } else if enableStats, let shortcut = controller.shortcutResetStats, shortcut.matches(press) {
            globalStatsResetDate = Date()
            return .handled
        }
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
        Task {
            try? await TerminalActivation.activate(session: session, trigger: .guiSelect)
        }
    }

    // MARK: - Duration Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        SessionStatsCalculator.formatDuration(seconds)
    }

    // MARK: - Stats Footer

    private var totalIdleTimeForFooter: TimeInterval {
        SessionStatsCalculator.totalIdleTime(
            sessions: sessionManager.sessions, resetDate: globalStatsResetDate, isPaused: isPaused
        )
    }

    private var totalWorkingTimeForFooter: TimeInterval {
        SessionStatsCalculator.totalWorkingTime(
            sessions: sessionManager.sessions, resetDate: globalStatsResetDate, isPaused: isPaused
        )
    }

    private var idlePercentage: Double {
        SessionStatsCalculator.idlePercentage(sessions: sessionManager.sessions)
    }

    private var footerGradientColor: Color {
        let c = SessionStatsCalculator.footerGradientComponents(idlePercentage: idlePercentage)
        return Color(red: c.red, green: c.green, blue: c.blue)
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
                Text("\(formatDuration(totalWorkingTimeForFooter)) working time")
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
                shortcutRow(controller.shortcutTogglePause?.displayString ?? "–", "Start/Pause")
                shortcutRow(controller.shortcutResetStats?.displayString ?? "–", "Reset Stats")
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

    private func modeRow(_ name: String, _ description: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .frame(minWidth: 40, alignment: .trailing)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
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
