import Foundation

enum TerminalType: String, Codable, CaseIterable {
    case iterm2
    case kitty // Future
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
}
