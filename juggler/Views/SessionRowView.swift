//
//  SessionRowView.swift
//  Juggler
//
//  Created by Niels Madan on 22.01.26.
//

import SwiftUI

struct SessionRowView: View {
    let session: Session
    var isKeyboardSelected: Bool = false
    var onActivate: (() -> Void)?
    @Environment(SessionManager.self) private var sessionManager
    @State private var showRenameSheet = false
    @AppStorage(AppStorageKeys.useCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.sessionTitleMode) private var sessionTitleModeRaw: String = SessionTitleMode.tabTitle.rawValue

    private var titleMode: SessionTitleMode {
        SessionTitleMode(rawValue: sessionTitleModeRaw) ?? .tabTitle
    }

    private var isCurrent: Bool {
        sessionManager.currentSession?.id == session.id
    }

    private var highlightColor: Color {
        if useCyclingColors {
            let index = sessionManager.sessions.firstIndex(where: { $0.id == session.id }) ?? 0
            return CyclingColors.palette[index % CyclingColors.palette.count]
        } else {
            return Color.accentColor
        }
    }

    var body: some View {
        HStack {
            Image(systemName: session.state.iconName)
                .font(.system(size: 10))

            Text(sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode))
                .lineLimit(1)

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
                : (isCurrent ? highlightColor.opacity(0.1) : Color.clear)
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
                showRenameSheet = true
            }

            if session.state == .backburner {
                Button("Reactivate") {
                    sessionManager.reactivateSession(terminalSessionID: session.id)
                }
            } else {
                Button("Backburner") {
                    sessionManager.backburnerSession(terminalSessionID: session.id)
                }
            }

            Divider()

            Button("Remove", role: .destructive) {
                sessionManager.removeSession(sessionID: session.id)
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSessionView(session: session)
                .environment(sessionManager)
        }
    }

    private func activateSession() {
        Task {
            try? await TerminalActivation.activate(session: session, trigger: .guiSelect)
        }
        onActivate?()
    }
}
