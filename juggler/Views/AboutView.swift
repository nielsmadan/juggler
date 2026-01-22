//
//  AboutView.swift
//  Juggler
//

import SwiftUI

struct AboutView: View {
    private let updateManager = UpdateManager.shared

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Juggler")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(version)" + (build.isEmpty ? "" : " (\(build))"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Check for Updates...") {
                updateManager.checkForUpdates()
            }

            Text("Copyright © 2026 Niels Madan")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 300)
    }
}
