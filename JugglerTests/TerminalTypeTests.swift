import Foundation
@testable import Juggler
import Testing

@Test func terminalType_bundleIdentifier() {
    #expect(TerminalType.iterm2.bundleIdentifier == "com.googlecode.iterm2")
    #expect(TerminalType.kitty.bundleIdentifier == "net.kovidgoyal.kitty")
    #expect(TerminalType.ghostty.bundleIdentifier == "com.mitchellh.ghostty")
    #expect(TerminalType.wezterm.bundleIdentifier == "com.github.wez.wezterm")
}

@Test func terminalType_iconName() {
    #expect(TerminalType.iterm2.iconName == "apple.terminal.fill")
    #expect(TerminalType.kitty.iconName == "cat.fill")
    #expect(TerminalType.ghostty.iconName == "apple.terminal.fill")
    #expect(TerminalType.wezterm.iconName == "apple.terminal.fill")
}
