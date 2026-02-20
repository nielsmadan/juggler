//
//  LocalShortcut.swift
//  Juggler
//
//  A local (in-app) keyboard shortcut that can be recorded and matched.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct LocalShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt // NSEvent.ModifierFlags.rawValue

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// Match against an NSEvent (used by NSEvent monitors for keys like Tab that SwiftUI's focus system intercepts)
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        return eventMods == modifierFlags
    }

    /// Check if this shortcut matches a SwiftUI KeyPress event
    func matches(_ press: KeyPress) -> Bool {
        if modifierFlags.isEmpty {
            return matchesKey(press)
        }

        let pressModifiers = Self.eventModifiersToNSModifiers(press.modifiers)
        guard pressModifiers == modifierFlags else { return false }

        return matchesKey(press)
    }

    /// Compare key identity, handling special keys (Tab, etc.) where modifiers change press.characters
    private func matchesKey(_ press: KeyPress) -> Bool {
        if let keyEquivalent = Self.specialKeyEquivalent(keyCode: keyCode) {
            return press.key == keyEquivalent
        }
        return Self.keyToCharacter(keyCode: keyCode)?.lowercased() == press.characters.lowercased()
    }

    /// Map key codes to SwiftUI KeyEquivalent for special keys
    private static func specialKeyEquivalent(keyCode: UInt16) -> KeyEquivalent? {
        switch Int(keyCode) {
        case kVK_Tab: .tab
        case kVK_Return: .return
        case kVK_Delete: .delete
        case kVK_Escape: .escape
        case kVK_Space: .space
        case kVK_UpArrow: .upArrow
        case kVK_DownArrow: .downArrow
        case kVK_LeftArrow: .leftArrow
        case kVK_RightArrow: .rightArrow
        case kVK_Home: .home
        case kVK_End: .end
        case kVK_PageUp: .pageUp
        case kVK_PageDown: .pageDown
        default: nil
        }
    }

    /// Convert SwiftUI EventModifiers to NSEvent.ModifierFlags
    private static func eventModifiersToNSModifiers(_ modifiers: SwiftUI.EventModifiers) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    /// The display string for this shortcut (e.g., "⌘J", "⇧L")
    var displayString: String {
        let modifierString = modifierFlags.symbolicRepresentation

        if let specialKeyString = Self.specialKeyString(keyCode: keyCode) {
            return modifierString + specialKeyString
        }

        if let char = Self.keyToCharacter(keyCode: keyCode) {
            return modifierString + char.uppercased()
        }

        return modifierString + "?"
    }

    /// Translate key code to character using the current keyboard layout
    static func keyToCharacter(keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var length = 0
        var characters = [UniChar](repeating: 0, count: maxLength)

        let error = UCKeyTranslate(
            keyLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0, // No modifiers for translation
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &length,
            &characters
        )

        guard error == noErr, length > 0 else {
            return nil
        }

        return String(utf16CodeUnits: characters, count: length)
    }

    /// String representation for special keys
    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_End: "↘",
        kVK_Escape: "⎋",
        kVK_Home: "↖",
        kVK_Space: "Space",
        kVK_Tab: "tab",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_UpArrow: "↑",
        kVK_RightArrow: "→",
        kVK_DownArrow: "↓",
        kVK_LeftArrow: "←",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
    ]

    static func specialKeyString(keyCode: UInt16) -> String? {
        specialKeyNames[Int(keyCode)]
    }
}

// MARK: - NSEvent.ModifierFlags Extension

extension NSEvent.ModifierFlags {
    /// Symbolic representation of modifier flags (e.g., "⌃⌥⇧⌘")
    var symbolicRepresentation: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let localShortcutsDidChange = Notification.Name("localShortcutsDidChange")
}

// MARK: - UserDefaults Storage

extension LocalShortcut {
    func save(to key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(from key: String) -> LocalShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(LocalShortcut.self, from: data)
    }

    static func remove(from key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
