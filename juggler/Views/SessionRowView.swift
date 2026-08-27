//
//  SessionRowView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import ShortcutKit
import SwiftUI

struct SessionRowView: View {
    let session: Session
    let controller: SessionListController
    var isKeyboardSelected: Bool = false
    var onActivate: (() -> Void)?
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleModeRaw: String = SessionTitleMode
        .default.rawValue

    private var titleMode: SessionTitleMode {
        SessionTitleMode(rawValue: sessionTitleModeRaw) ?? .default
    }

    private var isCurrent: Bool {
        sessionManager.currentReferenceSessionID == session.id
    }

    private var highlightColor: Color {
        useCyclingColors ? sessionManager.activeColor : Color.accentColor
    }

    /// Indexed palette color, not the cycling `activeColor` — must not re-tint as the user navigates.
    private var referenceColor: Color {
        guard useCyclingColors,
              let index = sessionManager.sessions.firstIndex(where: { $0.id == session.id })
        else { return Color.accentColor }
        return CyclingColors.color(at: index)
    }

    var body: some View {
        HStack {
            Image(systemName: session.state.iconName)
                .font(.system(size: 10))

            Text(sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode))
                .lineLimit(1)

            if let remoteHost = session.remoteHost {
                Text("SSH")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
                    .help(remoteHost)
            }

            Spacer()

            Text(session.state.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isKeyboardSelected
                ? highlightColor.opacity(0.2)
                : (isCurrent ? referenceColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isKeyboardSelected ? highlightColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            activateSession()
        }
        .contextMenu {
            Button("Rename...") {
                performContextAction(.rename)
            }

            if session.state == .backburner {
                Button("Reactivate") {
                    performContextAction(.reactivate)
                }
            } else {
                Button("Backburner") {
                    performContextAction(.backburner)
                }
            }

            Divider()

            Button("Remove", role: .destructive) {
                sessionManager.removeSession(sessionID: session.id)
            }
        }
    }

    private func activateSession() {
        sessionManager.syncColorIndex(toSessionID: session.id)
        ShortcutCenter.shared.sessionListContext.notifyHint(for: .activate)
        Task {
            _ = await SessionActivator.shared.activate(session: session, trigger: .guiSelect)
        }
        onActivate?()
    }

    private func performContextAction(_ action: SessionRowContextAction) {
        let shortcutAction = controller.performContextAction(action, on: session, sessionManager: sessionManager)
        ShortcutCenter.shared.sessionListContext.notifyHint(for: shortcutAction)
    }
}
