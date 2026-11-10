import ShortcutKit
import ShortcutKitUI
import SwiftUI

extension KeyBindings {
    private static let mergedContextID = "combined"

    func mergedIntoSingleGroup(displayName: LocalizedStringResource) -> KeyBindings {
        let entries = groups.flatMap(\.entries)
        guard !entries.isEmpty else { return KeyBindings() }
        return KeyBindings(groups: [Group(contextID: Self.mergedContextID, displayName: displayName, entries: entries)])
    }
}

struct CombinedShortcutLegend: View {
    @ObservedObject var registry: ShortcutRegistry
    let contextIDs: Set<String>
    let displayName: LocalizedStringResource
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        KeyBindingsLegendView(
            bindings: registry.bindings(for: contextIDs).mergedIntoSingleGroup(displayName: displayName),
            style: .embedded,
            options: options,
            label: label
        )
    }
}
