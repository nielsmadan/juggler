import SwiftUI

struct SessionNoteEditorView: View {
    let sessionName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var note: String
    @FocusState private var noteIsFocused: Bool

    init(
        sessionName: String,
        note: String?,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sessionName = sessionName
        self.onSave = onSave
        self.onCancel = onCancel
        _note = State(initialValue: note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Note")
                .font(.headline)
            Text(sessionName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            TextField("Note", text: $note)
                .textFieldStyle(.roundedBorder)
                .focused($noteIsFocused)
                .onSubmit { onSave(note) }
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Save") { onSave(note) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            // Defer one runloop tick: present() fires .onAppear before it makes the
            // panel key, and SwiftUI drops a focus request made on a non-key window.
            DispatchQueue.main.async { noteIsFocused = true }
        }
    }
}
