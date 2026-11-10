import SwiftUI

struct SessionMenuInfoLine: Identifiable {
    let slot: RowSlot
    let text: String

    var id: RowSlot { slot }

    static let slots: [RowSlot] = [
        .folderPath, .gitBranch, .agentTitle, .tabTitle, .windowTitle, .model, .effort, .permissionMode,
        .currentTool, .lastProblem, .subagents, .contextPercent, .turns, .runTime
    ]

    static let wideSlots: Set<RowSlot> = [.folderPath, .agentTitle]

    static func lines(for session: Session, now: Date, abbreviateHome: Bool) -> [SessionMenuInfoLine] {
        slots.compactMap { slot in
            slot.value(for: session, now: now, abbreviateHome: abbreviateHome)
                .map { SessionMenuInfoLine(slot: slot, text: $0) }
        }
    }
}

struct SessionMenuView: View {
    let controller: SessionMenuController
    let onSizeChange: (CGSize) -> Void
    @AppStorage(AppStorageKeys.monitorReplaceHomeWithTilde) private var monitorReplaceHomeWithTilde = false
    @State private var draft = ""
    @FocusState private var draftIsFocused: Bool

    var body: some View {
        let session = controller.session
        VStack(alignment: .leading, spacing: 12) {
            header(session)
            if let session {
                TimelineView(.periodic(from: .now, by: SessionSlotGridLayout.runTimeRefreshInterval)) { context in
                    info(session, now: context.date)
                }
            }
            Divider()
            switch controller.mode {
            case .menu: actions(session)
            case .rename: editor(placeholder: "Custom name", initial: session?.customName)
            case .note: editor(placeholder: "Note", initial: session?.note)
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(Color.black)
        .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 2))
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .keyWindowShortcutContext(ShortcutCenter.shared.sessionListContext,
                                  isActive: controller.acceptsShortcuts) { action, _ in
            controller.perform(.list(action))
        }
        .keyWindowShortcutContext(ShortcutCenter.shared.sessionMonitorContext,
                                  isActive: controller.acceptsShortcuts) { action, _ in
            controller.perform(.monitor(action))
        }
    }

    private func header(_ session: Session?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if session?.isPrioritized == true {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Prioritized")
                }
                if session?.isHidden == true {
                    Image(systemName: "eye.slash")
                        .accessibilityLabel("Hidden")
                }
                Text(controller.sessionName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let session {
                Text("\(session.agentDisplayName) · \(session.state.displayText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func info(_ session: Session, now: Date) -> some View {
        let lines = SessionMenuInfoLine.lines(for: session, now: now, abbreviateHome: monitorReplaceHomeWithTilde)
        let wide = lines.filter { SessionMenuInfoLine.wideSlots.contains($0.slot) }
        let paired = lines.filter { !SessionMenuInfoLine.wideSlots.contains($0.slot) }
        return VStack(alignment: .leading, spacing: 4) {
            if let note = session.note {
                iconRow(note, icon: "note.text", iconWidth: Self.infoIconWidth)
                    .truncationMode(.tail)
                    .accessibilityLabel("Note: \(note)")
            }
            ForEach(wide) { infoLine($0) }
            LazyVGrid(columns: Self.infoColumns, alignment: .leading, spacing: 4) {
                ForEach(paired) { infoLine($0) }
            }
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(.secondary)
    }

    private static let infoIconWidth: CGFloat = 14
    private static let actionIconWidth: CGFloat = 20
    private static let infoColumns = [
        GridItem(.flexible(), spacing: 12, alignment: .leading),
        GridItem(.flexible(), spacing: 12, alignment: .leading)
    ]

    private func infoLine(_ line: SessionMenuInfoLine) -> some View {
        iconRow(line.text, icon: line.slot.systemImage, iconWidth: Self.infoIconWidth)
            .truncationMode(.middle)
            .accessibilityLabel("\(line.slot.displayName): \(line.text)")
    }

    private func iconRow(_ text: String, icon: String, iconWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    private func actions(_ session: Session?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SessionMenuController.actions, id: \.self) { action in
                actionRow(action, session: session ?? controller.target)
            }
        }
    }

    private func actionRow(_ action: SessionRowAction, session: Session) -> some View {
        let isAvailable = controller.isAvailable(action)
        let label = action.label(for: session)
        let shortcut = action.shortcutDisplayString(
            list: ShortcutCenter.shared.sessionListContext,
            monitor: ShortcutCenter.shared.sessionMonitorContext
        )
        return Button {
            controller.perform(action)
        } label: {
            HStack {
                iconRow(label, icon: action.icon(for: session), iconWidth: Self.actionIconWidth)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.4)
        .help(isAvailable ? label : action.unavailableHelp ?? label)
        .accessibilityHint(shortcut.map { "Shortcut \($0)" } ?? "")
    }

    private func editor(placeholder: String, initial: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($draftIsFocused)
                .onSubmit { controller.save(draft) }
            HStack {
                Text("Esc to go back")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if controller.mode == .rename {
                    Button("Clear") { controller.clearName() }
                }
                Button("Save") { controller.save(draft) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            draft = initial ?? ""
            // SwiftUI drops a focus request made before the new field is in the window.
            DispatchQueue.main.async { draftIsFocused = true }
        }
    }
}
