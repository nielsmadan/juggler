//
//  LogsSettingsView.swift
//  Juggler
//

import SwiftUI

struct LogsSettingsView: View {
    @State private var logManager = LogManager.shared
    @State private var filterLevel: LogLevel?
    @State private var filterCategory: LogCategory?
    @State private var autoScroll = true
    @AppStorage(AppStorageKeys.verboseLogging) private var verboseLogging = false

    private var filteredEntries: [LogEntry] {
        logManager.entries.filter { entry in
            if let level = filterLevel, entry.level != level {
                return false
            }
            if let category = filterCategory, entry.category != category {
                return false
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Toggle("Verbose Logging", isOn: $verboseLogging)

                Spacer()

                Picker("Level", selection: $filterLevel) {
                    Text("All Levels").tag(nil as LogLevel?)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level as LogLevel?)
                    }
                }
                .frame(width: 150)

                Picker("Category", selection: $filterCategory) {
                    Text("All Categories").tag(nil as LogCategory?)
                    ForEach(LogCategory.allCases, id: \.self) { category in
                        Text(category.rawValue.capitalized).tag(category as LogCategory?)
                    }
                }
                .frame(width: 240)

                Toggle("Auto-scroll", isOn: $autoScroll)
            }
            .padding()

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                List(filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                        .id(entry.id)
                }
                .onChange(of: filteredEntries.count) { _, _ in
                    if autoScroll, let last = filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(filteredEntries.count) entries")
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Copy All") {
                    let text = logManager.exportAll()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }

                Button("Clear") {
                    logManager.clear()
                }
            }
            .padding()
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.icon)
                .foregroundStyle(entry.level.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(3)

                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
