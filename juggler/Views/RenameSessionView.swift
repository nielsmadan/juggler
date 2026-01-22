//
//  RenameSessionView.swift
//  Juggler
//

import SwiftUI

struct RenameSessionView: View {
    let session: Session
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var customName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Session")
                .font(.headline)

            TextField("Custom name", text: $customName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sessionManager.renameSession(terminalSessionID: session.id, customName: customName)
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tab name: \(session.terminalTabName ?? "Unknown")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Path: \(session.projectPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Clear") {
                    sessionManager.renameSession(terminalSessionID: session.id, customName: nil)
                    dismiss()
                }

                Button("Save") {
                    sessionManager.renameSession(terminalSessionID: session.id, customName: customName)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            customName = session.customName ?? ""
        }
    }
}
