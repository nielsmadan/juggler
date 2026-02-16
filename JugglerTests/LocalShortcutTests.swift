//
//  LocalShortcutTests.swift
//  JugglerTests
//

import AppKit
import Carbon.HIToolbox
import Foundation
@testable import Juggler
import Testing

// MARK: - Special Key String Tests

@Test func specialKeyString_returnKey() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_Return)) == "↩")
}

@Test func specialKeyString_deleteKey() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_Delete)) == "⌫")
}

@Test func specialKeyString_forwardDeleteKey() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_ForwardDelete)) == "⌦")
}

@Test func specialKeyString_escapeKey() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_Escape)) == "⎋")
}

@Test func specialKeyString_spaceKey() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_Space)) == "Space")
}

@Test func specialKeyString_tabKey() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_Tab)) == "tab")
}

@Test func specialKeyString_arrowKeys() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_UpArrow)) == "↑")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_DownArrow)) == "↓")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_LeftArrow)) == "←")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_RightArrow)) == "→")
}

@Test func specialKeyString_homeEndPageKeys() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_Home)) == "↖")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_End)) == "↘")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_PageUp)) == "⇞")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_PageDown)) == "⇟")
}

@Test func specialKeyString_functionKeys() {
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F1)) == "F1")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F2)) == "F2")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F3)) == "F3")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F4)) == "F4")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F5)) == "F5")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F6)) == "F6")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F7)) == "F7")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F8)) == "F8")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F9)) == "F9")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F10)) == "F10")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F11)) == "F11")
    #expect(LocalShortcut.specialKeyString(keyCode: UInt16(kVK_F12)) == "F12")
}

@Test func specialKeyString_unknownKey_returnsNil() {
    // Key code 0 is 'A' - not a special key
    #expect(LocalShortcut.specialKeyString(keyCode: 0) == nil)
    // Key code 1 is 'S' - not a special key
    #expect(LocalShortcut.specialKeyString(keyCode: 1) == nil)
}

// MARK: - Modifier Symbolic Representation Tests

@Test func symbolicRepresentation_commandOnly() {
    let flags: NSEvent.ModifierFlags = .command
    #expect(flags.symbolicRepresentation == "⌘")
}

@Test func symbolicRepresentation_shiftOnly() {
    let flags: NSEvent.ModifierFlags = .shift
    #expect(flags.symbolicRepresentation == "⇧")
}

@Test func symbolicRepresentation_optionOnly() {
    let flags: NSEvent.ModifierFlags = .option
    #expect(flags.symbolicRepresentation == "⌥")
}

@Test func symbolicRepresentation_controlOnly() {
    let flags: NSEvent.ModifierFlags = .control
    #expect(flags.symbolicRepresentation == "⌃")
}

@Test func symbolicRepresentation_commandShift() {
    let flags: NSEvent.ModifierFlags = [.command, .shift]
    #expect(flags.symbolicRepresentation == "⇧⌘")
}

@Test func symbolicRepresentation_allModifiers() {
    let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    #expect(flags.symbolicRepresentation == "⌃⌥⇧⌘")
}

@Test func symbolicRepresentation_empty() {
    let flags: NSEvent.ModifierFlags = []
    #expect(flags.symbolicRepresentation == "")
}

// MARK: - LocalShortcut Codable Tests

@Test func localShortcut_codableRoundtrip() throws {
    let original = LocalShortcut(keyCode: 38, modifiers: [.command, .shift]) // ⌘⇧J

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(LocalShortcut.self, from: data)

    #expect(decoded.keyCode == original.keyCode)
    #expect(decoded.modifiers == original.modifiers)
    #expect(decoded == original)
}

@Test func localShortcut_codableRoundtrip_noModifiers() throws {
    let original = LocalShortcut(keyCode: 36, modifiers: []) // Return key, no modifiers

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(LocalShortcut.self, from: data)

    #expect(decoded.keyCode == original.keyCode)
    #expect(decoded.modifiers == 0)
    #expect(decoded == original)
}

// MARK: - LocalShortcut ModifierFlags Tests

@Test func localShortcut_modifierFlags_convertsCorrectly() {
    let shortcut = LocalShortcut(keyCode: 0, modifiers: [.command, .option])
    #expect(shortcut.modifierFlags.contains(.command))
    #expect(shortcut.modifierFlags.contains(.option))
    #expect(!shortcut.modifierFlags.contains(.shift))
    #expect(!shortcut.modifierFlags.contains(.control))
}
