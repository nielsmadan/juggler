import Foundation

enum TerminalType: String, Codable, CaseIterable {
    case iterm2
    case kitty
    case ghostty // Future
    case wezterm // Future

    var displayName: String {
        switch self {
        case .iterm2: "iTerm2"
        case .kitty: "Kitty"
        case .ghostty: "Ghostty"
        case .wezterm: "WezTerm"
        }
    }

    var iconName: String {
        switch self {
        case .iterm2: "apple.terminal.fill"
        case .kitty: "cat.fill"
        case .ghostty: "apple.terminal.fill"
        case .wezterm: "apple.terminal.fill"
        }
    }

}
