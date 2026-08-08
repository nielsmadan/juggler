import AppKit
@testable import Juggler
import ShortcutField
import Testing

@Suite("Shortcut+Persistence", .serialized)
struct ShortcutPersistenceTests {
    private let testKey = "test.shortcut.persistence"

    @Test func load_currentFormat_roundTrips() {
        let shortcut = DiscreteShortcut(keyCode: 5, modifiers: .command)
        shortcut.save(to: testKey)
        defer { DiscreteShortcut.remove(from: testKey) }

        #expect(DiscreteShortcut.load(from: testKey) == shortcut)
    }

    @Test func load_legacyFormat_decodesViaFallback() {
        // Pre-2.0 ShortcutField wire format: a flat `{keyCode, modifiers}` object.
        let cmd = NSEvent.ModifierFlags.command.rawValue
        let legacyJSON = #"{"keyCode":5,"modifiers":\#(cmd)}"#
        UserDefaults.standard.set(Data(legacyJSON.utf8), forKey: testKey)
        defer { DiscreteShortcut.remove(from: testKey) }

        #expect(DiscreteShortcut.load(from: testKey) == DiscreteShortcut(keyCode: 5, modifiers: .command))
    }

    @Test func load_garbageData_returnsNil() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: testKey)
        defer { DiscreteShortcut.remove(from: testKey) }

        #expect(DiscreteShortcut.load(from: testKey) == nil)
    }

    @Test func load_missingKey_returnsNil() {
        DiscreteShortcut.remove(from: testKey)
        #expect(DiscreteShortcut.load(from: testKey) == nil)
    }

    @Test func loadDefaulted_missingKey_returnsDefault() {
        DiscreteShortcut.remove(from: testKey)
        let fallback = DiscreteShortcut(keyCode: 35, modifiers: [])

        #expect(DiscreteShortcut.load(from: testKey, defaultingTo: fallback) == fallback)
    }

    @Test func loadDefaulted_explicitlyUnbound_returnsNil() {
        DiscreteShortcut.unbind(from: testKey)
        defer { DiscreteShortcut.remove(from: testKey) }

        #expect(DiscreteShortcut.load(
            from: testKey,
            defaultingTo: DiscreteShortcut(keyCode: 35, modifiers: [])
        ) == nil)
    }

    @Test func save_afterUnbind_replacesUnboundValue() {
        DiscreteShortcut.unbind(from: testKey)
        defer { DiscreteShortcut.remove(from: testKey) }
        let shortcut = DiscreteShortcut(keyCode: 5, modifiers: .command)

        shortcut.save(to: testKey)

        #expect(DiscreteShortcut.load(
            from: testKey,
            defaultingTo: DiscreteShortcut(keyCode: 35, modifiers: [])
        ) == shortcut)
    }
}
