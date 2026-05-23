import AppKit
import Foundation
import ShortcutField
import SwiftUI

extension DiscreteShortcut {
    func save(to key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(from key: String) -> DiscreteShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        if let shortcut = try? JSONDecoder().decode(DiscreteShortcut.self, from: data) {
            return shortcut
        }
        // Fallback: decode the pre-2.0 ShortcutField wire format `{keyCode, modifiers}`
        // so user-recorded shortcuts persist across the package upgrade.
        return (try? JSONDecoder().decode(LegacyShortcut.self, from: data))
            .map { DiscreteShortcut(keyCode: $0.keyCode, modifiers: NSEvent.ModifierFlags(rawValue: $0.modifiers)) }
    }

    static func remove(from key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Match against a SwiftUI `KeyPress`. Only meaningful for single-step
    /// shortcuts — multi-step sequences need the stateful ``ShortcutMatcher``
    /// (which only consumes `NSEvent`s, not `KeyPress`).
    @available(macOS 14.0, *)
    func matches(_ press: KeyPress) -> Bool {
        guard steps.count == 1 else { return false }
        return steps[0].matches(press)
    }
}

private struct LegacyShortcut: Decodable {
    let keyCode: UInt16
    let modifiers: UInt
}

extension Notification.Name {
    static let localShortcutsDidChange = Notification.Name("localShortcutsDidChange")
}
