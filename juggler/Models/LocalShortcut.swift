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

    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else {
            return nil
        }
        keyCode = event.keyCode
        // Normalize modifiers to only include the standard ones
        let normalized = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        modifiers = normalized.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// Check if this shortcut matches a SwiftUI KeyPress event
    func matches(_ press: KeyPress) -> Bool {
        // For simple shortcuts without modifiers, just compare characters
        if modifierFlags.isEmpty {
            return Self.keyToCharacter(keyCode: keyCode)?.lowercased() == press.characters.lowercased()
        }

        // For shortcuts with modifiers, we need to check both
        let pressModifiers = Self.eventModifiersToNSModifiers(press.modifiers)
        guard pressModifiers == modifierFlags else { return false }

        // Compare the key character
        return Self.keyToCharacter(keyCode: keyCode)?.lowercased() == press.characters.lowercased()
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

        // Check for special keys first
        if let specialKeyString = Self.specialKeyString(keyCode: keyCode) {
            return modifierString + specialKeyString
        }

        // Otherwise translate key code to character
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
    static func specialKeyString(keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Return: "↩"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_End: "↘"
        case kVK_Escape: "⎋"
        case kVK_Home: "↖"
        case kVK_Space: "Space"
        case kVK_Tab: "⇥"
        case kVK_PageUp: "⇞"
        case kVK_PageDown: "⇟"
        case kVK_UpArrow: "↑"
        case kVK_RightArrow: "→"
        case kVK_DownArrow: "↓"
        case kVK_LeftArrow: "←"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default: nil
        }
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

// MARK: - UserDefaults Storage

extension LocalShortcut {
    /// Store to UserDefaults
    func save(to key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Load from UserDefaults
    static func load(from key: String) -> LocalShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(LocalShortcut.self, from: data)
    }

    /// Remove from UserDefaults
    static func remove(from key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
