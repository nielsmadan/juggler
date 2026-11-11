import Carbon.HIToolbox
import ShortcutKit
import ShortcutKitUI
import SwiftUI

struct SessionMonitorView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppStorageKeys.queueOrderMode) private var queueOrderMode: String = QueueOrderMode.default.rawValue
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.enableStats) private var enableStats = true
    @AppStorage(AppStorageKeys.showShortcutHelper) private var showShortcutHelper = true
    @AppStorage(AppStorageKeys.beaconEnabled) private var beaconEnabled = true
    @AppStorage(AppStorageKeys.autoAdvanceOnBusy) private var autoAdvanceOnBusy = false
    @AppStorage(AppStorageKeys.autoRestartOnIdle) private var autoRestartOnIdle = false
    @AppStorage(AppStorageKeys.prioritizePermissionSessions) private var prioritizePermissionSessions = false
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleModeRaw: String = SessionTitleMode
        .default.rawValue
    @AppStorage(AppStorageKeys.controlBarHintDismissed) private var controlBarHintDismissed = false
    @AppStorage(AppStorageKeys.monitorReplaceHomeWithTilde) private var monitorReplaceHomeWithTilde = false
    private var rowActionSettings = RowActionSettings()
    private var rowSlotSettings = RowSlotSettings()

    private var titleMode: SessionTitleMode {
        SessionTitleMode(rawValue: sessionTitleModeRaw) ?? .default
    }

    private var rowActions: [SessionRowAction] {
        rowActionSettings.actions
    }

    private var selectionSource: SessionListController.SelectionSource {
        .init(sessionManager: sessionManager)
    }

    private var controlBarDividerColor: Color {
        colorScheme == .dark
            ? Color(red: 205 / 255, green: 205 / 255, blue: 205 / 255)
            : Color(red: 50 / 255, green: 50 / 255, blue: 50 / 255)
    }

    @State private var controller = SessionListController()
    @State private var isMonitorWindowKey = false
    @State private var scrollTask: Task<Void, Never>?
    /// Per-session stats-corner widths, captured via PreferenceKey so row content clears the corner.
    @State private var cornerWidths: [String: CGFloat] = [:]

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
            .keyWindowShortcutContext(ShortcutCenter.shared.sessionListContext,
                                      isActive: isMonitorWindowKey) { action, _ in
                handleSessionListAction(action)
            }
            .keyWindowShortcutContext(ShortcutCenter.shared.sessionMonitorContext,
                                      isActive: isMonitorWindowKey) { action, _ in
                handleSessionMonitorAction(action)
            }
            .shortcutHintHUD(
                presenter: ShortcutCenter.shared.hintPresenter,
                options: ShortcutCenter.shared.hintOptions
            )
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
                            BeaconManager.shared.show(
                                sessionName: "Session No Longer Available",
                                force: true
                            )
                        }
                    },
                    onCancel: { controller.sessionToEditNote = nil }
                )
            }
            .onChange(of: sessionManager.listedSessions) { _, newSessions in
                controller.syncMonitorSelection(sessionManager: sessionManager)
                let alive = Set(newSessions.map(\.id))
                let liveCornerWidths = cornerWidths.filter { alive.contains($0.key) }
                if liveCornerWidths != cornerWidths { cornerWidths = liveCornerWidths }
            }
            .onChange(of: sessionManager.orderedVisibleSessions().map(\.id)) {
                controller.syncMonitorSelection(sessionManager: sessionManager)
            }
            .onAppear {
                controller.ownerLabel = "Monitor"
                controller.syncMonitorSelection(sessionManager: sessionManager)
            }
            .onDisappear {
                scrollTask?.cancel()
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
            .onChange(of: selectionSource) { previous, current in
                controller.syncCurrentSelection(from: previous, to: current, sessions: sessionManager.listedSessions)
            }
            .onChange(of: sessionManager.focusedSessionID) { _, newFocusedID in
                controller.selectListedSession(matching: newFocusedID, in: sessionManager.listedSessions)
            }
            .onChange(of: sessionManager.isSessionFocused) { _, isFocused in
                // Resync selection when a terminal becomes active, so arrow-key
                // drift in the monitor doesn't persist when returning to the terminal.
                // Skip if an activation is in flight — the focus event for the target
                // session hasn't arrived yet, so resyncing would flash the old session.
                if isFocused, sessionManager.activationTarget == nil {
                    controller.selectListedSession(
                        matching: sessionManager.focusedSessionID,
                        in: sessionManager.listedSessions
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, WindowManager.shared.isMainWindow(window) {
                    isMonitorWindowKey = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, WindowManager.shared.isMainWindow(window) {
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
            if let emptyState = sessionManager.listEmptyState {
                ContentUnavailableView(
                    emptyState.title,
                    systemImage: emptyState.icon,
                    description: Text(emptyState.description)
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
                ForEach(sessionManager.listedSessions) { session in
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
                    reduceMotion ? nil : .easeInOut(duration: SectionAnimationTiming.upMoveDuration),
                    value: sessionManager.listedSessions.map(\.id)
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
              let session = sessionManager.listedSessions.first(where: { $0.id == id }) else {
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

            toggleButton(
                isOn: $prioritizePermissionSessions,
                action: .permissionFirst,
                icon: "hand.raised.fill",
                activeColor: CyclingColors.palette[2],
                help: "Permission first: keep sessions waiting for permission above idle sessions",
                isEnabled: permissionFirstAvailable,
                disabledHelp: "Permission First is disabled in Static and Grouped modes because those modes preserve fixed session ordering"
            )
            toggleButton(isOn: $autoAdvanceOnBusy, action: .autoNext, icon: "forward.fill",
                         activeColor: CyclingColors.palette[0],
                         help: "Auto-advance: go to next session when current goes busy")
            toggleButton(isOn: $autoRestartOnIdle, action: .autoRestart, icon: "autostartstop",
                         activeColor: CyclingColors.palette[3],
                         help: "Auto-restart: when all sessions are busy and one becomes idle, jump to it")
            toggleButton(isOn: $beaconEnabled, action: .beacon, icon: "light.panel",
                         activeColor: CyclingColors.palette[4],
                         help: "Beacon: show session name when cycling")
            Button {
                controller.toggleHiddenVisibility(sessionManager: sessionManager)
                ShortcutCenter.shared.sessionMonitorContext.notify(.toggleHiddenVisibility)
            } label: {
                Image(systemName: sessionManager.showsHiddenSessions ? "eye" : "eye.slash")
                    .font(.callout)
                    .frame(width: 32, height: 28)
                    .background(sessionManager.showsHiddenSessions ? Color.accentColor : Color.clear)
                    .foregroundStyle(sessionManager.showsHiddenSessions ? .white : .primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Hidden: reveal hidden sessions in Session Monitor and the popover")
            .accessibilityLabel("Show Hidden")
            .accessibilityValue(sessionManager.showsHiddenSessions ? "On" : "Off")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
    }

    private func toggleButton(
        isOn: Binding<Bool>,
        action: MonitorControlAction,
        icon: String,
        activeColor: Color,
        help: String,
        isEnabled: Bool = true,
        disabledHelp: String? = nil
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            ShortcutCenter.shared.sessionListContext.notifyHint(for: action.shortcutAction)
        } label: {
            Image(systemName: icon)
                .font(.callout)
                .frame(width: 16, height: 16)
                .frame(width: 32)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? activeColor : Color.clear)
                .foregroundStyle(isOn.wrappedValue ? .white : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(isEnabled ? help : disabledHelp ?? help)
        .accessibilityLabel(action.title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    // MARK: - Row Views

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

    @ViewBuilder
    private func listSessionRow(_ session: Session) -> some View {
        let rowInsets = SessionMonitorRowLayout.listInsets

        HStack(alignment: .top, spacing: 8) {
            agentColumn(session)
            sessionContent(session, rowInsets: rowInsets)
        }
        .padding(.vertical, rowInsets.vertical)
        .padding(.horizontal, rowInsets.horizontal)
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
        .onPreferenceChange(BusyStatsCornerWidthKey.self) { width in
            recordCornerWidth(width, for: session.id)
        }
        .contentShape(Rectangle())
        .opacity(session.isHidden ? 0.55 : 1)
        .listRowBackground(
            isActiveRow(session)
                ? highlightColor.opacity(0.15)
                : Color.clear
        )
        .activatableSessionRow(isSelected: isActiveRow(session), children: .contain) { activateSession(session) }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func isActiveRow(_ session: Session) -> Bool {
        (sessionManager.isSessionFocused || isMonitorWindowKey) && controller.selectedSessionID == session.id
    }

    @ViewBuilder
    private func scrollViewSessionRow(_ session: Session) -> some View {
        let isDownAnimation = animationController.isDownAnimating(sessionID: session.id)
        let rowInsets = SessionMonitorRowLayout.scrollInsets

        let row = HStack(alignment: .top, spacing: 8) {
            agentColumn(session)
            sessionContent(session, rowInsets: rowInsets)
        }
        .padding(.vertical, rowInsets.vertical)
        .padding(.horizontal, rowInsets.horizontal)
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
        .onPreferenceChange(BusyStatsCornerWidthKey.self) { width in
            recordCornerWidth(width, for: session.id)
        }
        .overlay(alignment: .leading) {
            if showsPrioMarker(session) {
                PrioMarker()
            }
        }
        .contentShape(Rectangle())
        .opacity(session.isHidden ? 0.55 : 1)
        .activatableSessionRow(isSelected: isActiveRow(session), children: .contain) { activateSession(session) }
        .transition(rowTransition(isDownAnimation: isDownAnimation))

        if isDownAnimation {
            row
        } else {
            row.matchedGeometryEffect(id: session.id, in: sessionAnimation)
        }
    }

    private func rowTransition(isDownAnimation: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: isDownAnimation ? .curvedEnterFromAbove : .fadeInFromAbove,
            removal: isDownAnimation ? .curvedExitDown : .identity
        )
    }

    @ViewBuilder
    private func sessionContent(
        _ session: Session,
        rowInsets: SessionMonitorRowLayout.Insets
    ) -> some View {
        let cornerWidth = cornerWidths[session.id] ?? BusyStatsCornerLayout.estimatedTodayTabWidth
        let slots = rowSlotSettings.slots
        let reserves = SessionRowGeometry.slotReserves(
            cornerWidth: cornerWidth,
            statsEnabled: enableStats,
            rowHorizontalPadding: rowInsets.horizontal,
            showsActions: !rowActions.isEmpty
        )
        VStack(alignment: .leading, spacing: SessionMonitorRowLayout.titleToSlotsSpacing) {
            sessionTitle(session)
                .padding(.trailing, reserves.top)
            LiveSessionSlotGrid(
                slots: slots,
                resolve: { now in
                    ResolvedSlotGrid.resolve(
                        slots,
                        session: session,
                        now: now,
                        abbreviateHome: monitorReplaceHomeWithTilde
                    )
                },
                reserves: reserves
            )
            if let note = session.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, reserves.bottom)
            }
        }
        .frame(maxWidth: .infinity, minHeight: SessionMonitorRowLayout.contentMinHeight, alignment: .topLeading)
        .overlay {
            GeometryReader { geo in
                let controlAreaHeight = SessionRowGeometry.controlAreaHeight(
                    contentHeight: geo.size.height,
                    statsEnabled: enableStats,
                    rowVerticalPadding: rowInsets.vertical
                )
                trailingControls(
                    session,
                    height: controlAreaHeight,
                    actionTopOffset: SessionRowActionLayout.topOffset(rowVerticalPadding: rowInsets.vertical)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: rowInsets.horizontal)
            }
        }
    }

    // Only write on an actual change: the width feeds the slot reserves,
    // so an unconditional assignment re-invalidates layout every pass.
    private func recordCornerWidth(_ width: CGFloat, for sessionID: String) {
        guard width > 0, cornerWidths[sessionID] != width else { return }
        cornerWidths[sessionID] = width
    }

    private func sessionTitle(_ session: Session) -> some View {
        HStack(spacing: 4) {
            Text(sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode))
                .font(.headline)
                .lineLimit(1)
            if session.isHidden {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .accessibilityLabel("Hidden session")
            }
        }
    }

    private func trailingControls(_ session: Session, height: CGFloat, actionTopOffset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            stateBadge(session)
                .frame(height: height, alignment: .center)
            if !rowActions.isEmpty {
                sessionActions(session, height: height)
                    .frame(height: height, alignment: .top)
                    .offset(y: actionTopOffset)
            }
        }
    }

    private func sessionActions(_ session: Session, height: CGFloat) -> some View {
        let metrics = SessionRowActionLayout.metrics(actionCount: rowActions.count, availableHeight: height)
        return VStack(spacing: metrics.spacing) {
            ForEach(Array(rowActions.enumerated()), id: \.offset) { _, action in
                rowActionButton(
                    icon: action.icon(for: session),
                    label: action.label(for: session),
                    metrics: metrics,
                    isEnabled: action.isAvailable(in: currentQueueOrderMode),
                    disabledHelp: action.unavailableHelp
                ) {
                    performRowAction(action, session: session)
                }
            }
        }
        .padding(.trailing, SessionRowActionLayout.trailingPadding)
    }

    private func rowActionButton(
        icon: String,
        label: String,
        metrics: SessionRowActionLayout.Metrics,
        isEnabled: Bool,
        disabledHelp: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: metrics.iconSize))
                .frame(width: SessionRowActionLayout.buttonSize, height: metrics.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(isEnabled ? label : disabledHelp ?? label)
        .accessibilityLabel(label)
    }

    private func performRowAction(_ action: SessionRowAction, session: Session) {
        switch action {
        case .rename:
            controller.sessionToRename = session
        case .note:
            controller.sessionToEditNote = session
        case .hide:
            controller.toggleHidden(sessionID: session.id, sessionManager: sessionManager)
        case .prio:
            controller.togglePrioritized(sessionID: session.id, mode: currentQueueOrderMode,
                                         sessionManager: sessionManager)
        }
        switch action.shortcut {
        case let .list(shortcut): ShortcutCenter.shared.sessionListContext.notifyHint(for: shortcut)
        case let .monitor(shortcut): ShortcutCenter.shared.sessionMonitorContext.notify(shortcut)
        }
    }

    private func handleSessionMonitorAction(_ action: SessionMonitorAction) {
        switch action {
        case .toggleSelectedHidden:
            guard let session = controller.selectedSession(in: sessionManager.listedSessions) else { return }
            controller.toggleHidden(sessionID: session.id, sessionManager: sessionManager)
        case .toggleHiddenVisibility:
            controller.toggleHiddenVisibility(sessionManager: sessionManager)
        case .toggleSelectedPrioritized:
            guard let session = controller.selectedSession(in: sessionManager.listedSessions) else { return }
            controller.togglePrioritized(sessionID: session.id, mode: currentQueueOrderMode,
                                         sessionManager: sessionManager)
        }
    }

    private func stateBadge(_ session: Session) -> some View {
        VStack(spacing: 2) {
            Image(systemName: session.state.iconName)
                .font(.system(size: 16))
            Text(session.state.displayText)
                .font(.caption)
        }
        .frame(width: StateBadgeLayout.frameWidth)
        .padding(.trailing, StateBadgeLayout.trailingPadding)
    }

    private func handleSessionListAction(_ action: SessionListAction) {
        switch action {
        case .activate: activateSelected()
        case .moveDown: controller.moveSelection(by: 1, in: sessionManager.orderedVisibleSessions())
        case .moveUp: controller.moveSelection(by: -1, in: sessionManager.orderedVisibleSessions())
        case .backburner: controller.backburnerSelected(sessionManager: sessionManager)
        case .sendToBack: controller.sendToBackSelected(sessionManager: sessionManager)
        case .reactivateSelected: controller.reactivateSelected(sessionManager: sessionManager)
        case .reactivateAll: controller.reactivateAll(sessionManager: sessionManager)
        case .rename, .editNote: handleEditorAction(action)
        case .cycleModeForward: queueOrderMode = controller.cycleMode(forward: true, currentMode: queueOrderMode)
        case .cycleModeBackward: queueOrderMode = controller.cycleMode(forward: false, currentMode: queueOrderMode)
        case .toggleBeacon: beaconEnabled.toggle()
        case .toggleAutoNext: autoAdvanceOnBusy.toggle()
        case .toggleAutoRestart: autoRestartOnIdle.toggle()
        case .togglePermissionFirst:
            if permissionFirstAvailable { prioritizePermissionSessions.toggle() }
        }
    }

    private func handleEditorAction(_ action: SessionListAction) {
        switch action {
        case .rename: controller.renameSelected(sessions: sessionManager.listedSessions)
        case .editNote: controller.editNoteSelected(sessions: sessionManager.listedSessions)
        default: assertionFailure("Unexpected editor action")
        }
    }

    private var permissionFirstAvailable: Bool {
        QueueOrderMode(rawValue: queueOrderMode)?.supportsPermissionPriority == true
    }

    private var currentQueueOrderMode: QueueOrderMode? {
        QueueOrderMode(rawValue: queueOrderMode)
    }

    private func showsPrioMarker(_ session: Session) -> Bool {
        PrioMarker.isShown(for: session, mode: currentQueueOrderMode)
    }

    private func activateSelected() {
        guard let session = controller.selectedSession(in: sessionManager.listedSessions) else { return }
        activateSession(session)
    }

    private func activateSession(_ session: Session) {
        guard sessionManager.listedSessions.contains(where: { $0.id == session.id }) else { return }
        if controller.selectedSessionID != session.id {
            sessionManager.syncColorIndex(toSessionID: session.id)
        }
        ShortcutCenter.shared.sessionListContext.notifyHint(for: .activate)
        Task {
            _ = await SessionActivator.shared.activate(session: session, trigger: .guiSelect, policy: .explicit)
        }
    }

    // MARK: - Shortcuts Reference

    @ViewBuilder
    private var shortcutsReference: some View {
        CombinedShortcutLegend(
            registry: ShortcutCenter.shared.registry,
            contextIDs: ["sessionList", "sessionMonitor"],
            displayName: "Shortcuts",
            options: LegendOptions(
                columns: .fixed(3),
                size: .medium,
                showsHeaderDivider: false,
                labelWidth: .fixed(79),
                appearance: LegendAppearance(headerFont: LegendFont(size: 12))
            ),
            label: { entry in
                SessionListAction(rawValue: entry.actionID)?.legendLabel
            }
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
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
