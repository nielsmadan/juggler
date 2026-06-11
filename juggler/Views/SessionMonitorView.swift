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
    /// Pending scroll-into-view work. Cancelled and replaced on each request so
    /// rapid navigation collapses to a single `scrollTo` instead of piling up.
    @State private var scrollTask: Task<Void, Never>?
    /// Per-session Today-tab rendered width, captured via PreferenceKey so the
    /// state badge can align its horizontal center with the tab's diagonal apex.
    @State private var todayTabWidths: [String: CGFloat] = [:]

    @Namespace private var sessionAnimation

    private var animationController: SectionAnimationController {
        sessionManager.animationController
    }

    /// Visual title for a section header. Section *order* and membership come from
    /// `SessionManager.sessionsBySection()`; only the labels live in the view.
    private func sectionTitle(_ section: SectionType) -> String {
        switch section {
        case .idle: "Idle"
        case .working: "Working"
        case .backburner: "Backburner"
        }
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
                Self.sessionRowID(session.id)
            case let .placeholder(section):
                "empty-\(section.rawValue)"
            case let .divider(section, sessionID):
                "divider-\(section.rawValue)-\(sessionID)"
            }
        }

        /// Single source for a session row's scroll/identity key. `scrollToSelected`
        /// must use this so the scroll target stays in lockstep with the row's id.
        static func sessionRowID(_ sessionID: String) -> String {
            "session-\(sessionID)"
        }
    }

    private var sectionedRows: [SectionRow] {
        var rows: [SectionRow] = []

        for (section, sessions) in sessionManager.sessionsBySection() {
            rows.append(.header(section, sectionTitle(section)))
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
            .background(WindowAccessor { controller.ownWindow = $0 })
            .suppressShortcutBeep()
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) {
                logDebug(.navigation, "onKeyPress downArrow → moveSelection (SwiftUI focus path)")
                controller.moveSelection(by: 1, in: sessionManager.orderedVisibleSessions())
                return .handled
            }
            .onKeyPress(.upArrow) {
                logDebug(.navigation, "onKeyPress upArrow → moveSelection (SwiftUI focus path)")
                controller.moveSelection(by: -1, in: sessionManager.orderedVisibleSessions())
                return .handled
            }
            .onKeyPress(.return) { activateSelected(); return .handled }
            .onKeyPress { handleKeyPress($0) }
            .sheet(item: $controller.sessionToRename) { session in
                RenameSessionView(session: session)
                    .environment(sessionManager)
            }
            .onChange(of: sessionManager.sessions) { _, newSessions in
                logDebug(.navigation, "sessions changed (count=\(newSessions.count)) → syncSelection")
                controller.syncSelection(sessions: newSessions)
                let alive = Set(newSessions.map(\.id))
                todayTabWidths = todayTabWidths.filter { alive.contains($0.key) }
            }
            .onAppear {
                controller.syncSelection(sessions: sessionManager.sessions)
                controller.reloadShortcuts()
                controller.installKeyMonitor(
                    owner: "Monitor",
                    sessionManager: sessionManager,
                    queueOrderMode: $queueOrderMode,
                    visibleSessions: { sessionManager.orderedVisibleSessions() },
                    extraHandler: { event in
                        var handled = false
                        for (matcher, action) in [
                            (controller.matcherToggleAutoNext, { autoAdvanceOnBusy.toggle() }),
                            (controller.matcherToggleAutoRestart, { autoRestartOnIdle.toggle() })
                        ] {
                            switch matcher?.handle(event) ?? .ignored {
                            case .fired:
                                action()
                                handled = true
                            case let .advanced(consumeEvent):
                                if consumeEvent { handled = true }
                            case .ignored, .continuousFired:
                                break
                            }
                        }
                        return handled
                    }
                )
            }
            .onDisappear {
                controller.removeKeyMonitor()
                scrollTask?.cancel()
            }
            .onChange(of: queueOrderMode) { _, newMode in
                if let mode = QueueOrderMode(rawValue: newMode) {
                    sessionManager.reorderForMode(mode)
                }
            }
            .onChange(of: sessionManager.currentSession?.id) { _, newID in
                if let current = sessionManager.currentSession {
                    logDebug(.navigation, "currentSession changed → \(newID ?? "nil") → setSelection(\(current.id))")
                    controller.setSelection(toSessionID: current.id)
                }
            }
            .onChange(of: sessionManager.focusedSessionID) { _, newFocusedID in
                guard let focusedID = newFocusedID else { return }
                if let session = sessionManager.sessions.first(where: {
                    $0.terminalSessionID == focusedID || $0.id == focusedID
                }) {
                    logDebug(.navigation, "focusedSessionID changed → \(focusedID) → setSelection(\(session.id))")
                    controller.setSelection(toSessionID: session.id)
                }
            }
            .onChange(of: sessionManager.isSessionFocused) { _, isFocused in
                // Resync selection when a terminal becomes active, so arrow-key
                // drift in the monitor doesn't persist when returning to the terminal.
                // Skip if an activation is in flight — the focus event for the target
                // session hasn't arrived yet, so resyncing would flash the old session.
                if isFocused, sessionManager.activationTarget == nil,
                   let focusedID = sessionManager.focusedSessionID,
                   let session = sessionManager.sessions.first(where: {
                       $0.terminalSessionID == focusedID || $0.id == focusedID
                   }) {
                    logDebug(.navigation, "isSessionFocused → true → setSelection(\(session.id))")
                    controller.setSelection(toSessionID: session.id)
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
        ScrollViewReader { proxy in
            sessionListContent
                .onChange(of: controller.selectedSessionID) { _, _ in scrollToSelected(proxy) }
                .onChange(of: isMonitorWindowKey) { _, isKey in
                    if isKey { scrollToSelected(proxy) }
                }
                // Switching modes swaps the container (List ↔ LazyVStack) and its
                // row-id scheme, so re-reveal the selection in the new layout.
                .onChange(of: queueOrderMode) { _, _ in scrollToSelected(proxy) }
        }
    }

    @ViewBuilder
    private var sessionListContent: some View {
        if queueOrderMode == QueueOrderMode.grouped.rawValue {
            List {
                ForEach(sessionManager.sessionsByWindowGroup(), id: \.key) { group in
                    Section(header: Text(group.key)) {
                        ForEach(group.sessions) { session in
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

    /// True for the Fair/Prio modes, which render a `LazyVStack` keyed by
    /// `SectionRow.id`; false for Static/Grouped, whose `List` rows are keyed by
    /// the bare `session.id`. Determines which scroll-target key to use.
    private var usesSectionRowIDs: Bool {
        queueOrderMode != QueueOrderMode.grouped.rawValue
            && queueOrderMode != QueueOrderMode.static.rawValue
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let id = controller.selectedSessionID,
              let session = sessionManager.sessions.first(where: { $0.id == id }) else {
            logDebug(.navigation, "scrollToSelected skipped — no valid selection")
            return
        }

        // In the sectioned (Fair/Prio) layout a row only exists while it's
        // rendered — a session mid-DOWN-animation has no effective section and
        // isn't in `sectionedRows`, so scrolling to it would target a missing id
        // (and fire scrolls at a row set that's still moving).
        if usesSectionRowIDs, animationController.effectiveSection(for: session) == nil {
            logDebug(.navigation, "scrollToSelected skipped — selected row not rendered (mid-animation): \(id)")
            return
        }

        let target: String = usesSectionRowIDs ? SectionRow.sessionRowID(id) : id
        logDebug(.navigation, "scrollToSelected scheduling scrollTo(\(target))")

        // Coalesce: cancel any pending scroll and schedule one a frame out. Rapid
        // navigation collapses to a single scrollTo on the latest selection rather
        // than enqueuing many async calls that fight each other and thrash the
        // animating LazyVStack into a layout hang. The short delay also lets a
        // freshly-shown window complete a layout pass before we scroll.
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            proxy.scrollTo(target)
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
                    isActive: isActiveRow(session)
                )
            }
        }
        .onPreferenceChange(TodayTabWidthKey.self) { width in
            // Only write on an actual change — the dictionary feeds `stateBadgeOffset`,
            // so an unconditional assignment re-invalidates layout every pass.
            if width > 0, todayTabWidths[session.id] != width { todayTabWidths[session.id] = width }
        }
        .contentShape(Rectangle())
        .listRowBackground(
            isActiveRow(session)
                ? highlightColor.opacity(0.15)
                : Color.clear
        )
        .onTapGesture {
            activateSession(session)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func isActiveRow(_ session: Session) -> Bool {
        (sessionManager.isSessionFocused || isMonitorWindowKey) && controller.selectedSessionID == session.id
    }

    /// Row view for ScrollView (Fair/Prio mode with animations)
    @ViewBuilder
    private func scrollViewSessionRow(_ session: Session) -> some View {
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
            isActiveRow(session)
                ? highlightColor.opacity(0.15)
                : Color.clear
        )
        .overlay(alignment: .bottomTrailing) {
            if enableStats {
                BusyStatsCorner(
                    session: session,
                    highlightColor: highlightColor,
                    isActive: isActiveRow(session)
                )
            }
        }
        .onPreferenceChange(TodayTabWidthKey.self) { width in
            // Only write on an actual change — the dictionary feeds `stateBadgeOffset`,
            // so an unconditional assignment re-invalidates layout every pass.
            if width > 0, todayTabWidths[session.id] != width { todayTabWidths[session.id] = width }
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
        guard let id = controller.selectedSessionID,
              let session = sessionManager.sessions.first(where: { $0.id == id }) else { return }
        activateSession(session)
    }

    private func activateSession(_ session: Session) {
        // Only update color when clicking a different session (not Enter on already-selected)
        if controller.selectedSessionID != session.id {
            sessionManager.syncColorIndex(toSessionID: session.id)
        }
        sessionManager.beginActivation(targetSessionID: session.id)
        Task {
            do {
                try await TerminalActivation.activate(session: session, trigger: .guiSelect)
            } catch {
                BeaconManager.shared.show(sessionName: "Activation Failed", force: true)
            }
            sessionManager.endActivation()
        }
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
