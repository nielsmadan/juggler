//
//  WezTermConfigValidator.swift
//  Juggler
//

import Foundation

/// WezTerm config file detection — used by WezTermSetupView and IntegrationSettingsView.
enum WezTermConfigValidator {
    /// Resolves the WezTerm config file path following WezTerm's search order:
    /// 1. $WEZTERM_CONFIG_FILE (exclusive override)
    /// 2. ~/.wezterm.lua
    /// 3. $XDG_CONFIG_HOME/wezterm/wezterm.lua
    /// 4. ~/.config/wezterm/wezterm.lua (default)
    static var configFilePath: String {
        if let override = ProcessInfo.processInfo.environment["WEZTERM_CONFIG_FILE"], !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dotLua = home + "/.wezterm.lua"
        if FileManager.default.fileExists(atPath: dotLua) {
            return dotLua
        }
        return XDGPaths.configHome + "/wezterm/wezterm.lua"
    }

    static var luaSnippetPath: String {
        (configFilePath as NSString).deletingLastPathComponent + "/juggler_wezterm.lua"
    }

    /// True if the user's wezterm.lua contains a non-commented require for juggler_wezterm.
    static func hasRequireLine(in contents: String) -> Bool {
        contents.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Lua comments start with --
            guard !trimmed.hasPrefix("--") else { return false }
            return trimmed.contains("juggler_wezterm")
                && (trimmed.contains("require") || trimmed.contains("dofile"))
        }
    }

    struct Status {
        var luaSnippetInstalled = false
        var requireLinePresent = false
    }

    static func status() -> Status {
        let snippetInstalled = FileManager.default.fileExists(atPath: luaSnippetPath)
        let requireLine: Bool = {
            guard let contents = try? String(contentsOfFile: configFilePath, encoding: .utf8) else { return false }
            return hasRequireLine(in: contents)
        }()
        return Status(luaSnippetInstalled: snippetInstalled, requireLinePresent: requireLine)
    }
}
