import Foundation
@testable import Juggler
import Testing

@Suite("TerminalType")
struct TerminalTypeTests {
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
    // MARK: - TerminalType displayName Tests

    @Test func terminalType_displayName() {
        #expect(TerminalType.iterm2.displayName == "iTerm2")
        #expect(TerminalType.kitty.displayName == "Kitty")
        #expect(TerminalType.ghostty.displayName == "Ghostty")
        #expect(TerminalType.wezterm.displayName == "WezTerm")
    }

    // MARK: - TerminalType Codable Tests

    @Test func terminalType_codableRoundtrip() throws {
        for type in TerminalType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(TerminalType.self, from: data)
            #expect(decoded == type)
        }
    }
}
