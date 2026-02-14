import SwiftUI

struct SettingWithDescription<Content: View>: View {
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
