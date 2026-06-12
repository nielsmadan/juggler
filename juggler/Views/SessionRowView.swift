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

    /// Color for the "where you came from" residual highlight: the session's palette
    /// color by its list index — the app's usual per-position color scheme (same basis
    /// as `syncColorIndex`). Unlike the keyboard-selected `highlightColor` (the cycling
    /// `activeColor`), it does NOT change tint as the user navigates the popover. It can
    /// still change if the list reorders, like every other session color in the app.
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
        sessionManager.syncColorIndex(toSessionID: session.id)
        Task {
            do {
                try await TerminalActivation.activate(session: session, trigger: .guiSelect)
            } catch {
                BeaconManager.shared.show(sessionName: "Activation Failed", force: true)
            }
        }
        onActivate?()
    }
}
