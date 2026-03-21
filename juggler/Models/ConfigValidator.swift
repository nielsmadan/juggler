//
//  ConfigValidator.swift
//  Juggler
//

import Foundation

/// Resolves `$XDG_CONFIG_HOME`, falling back to `~/.config`.
enum XDGPaths {
    static var configHome: String {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           !xdg.isEmpty {
            return (xdg as NSString).expandingTildeInPath
        }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/.config"
    }
}

/// Kitty config file parsing — extracted from SettingsView for testability.
enum KittyConfigParser {
    /// Resolves the kitty config directory following kitty's search order:
    /// 1. $KITTY_CONFIG_DIRECTORY (exclusive override)
    /// 2. $XDG_CONFIG_HOME/kitty
    /// 3. ~/.config/kitty (default)
    static var configDirectory: String {
        if let kittyDir = ProcessInfo.processInfo.environment["KITTY_CONFIG_DIRECTORY"],
           !kittyDir.isEmpty {
            return (kittyDir as NSString).expandingTildeInPath
        }
        return XDGPaths.configHome + "/kitty"
    }

    /// Full path to kitty.conf using the resolved config directory.
    static var confFilePath: String {
        configDirectory + "/kitty.conf"
    }

    static func hasRemoteControl(in contents: String) -> Bool {
        contents.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("#") && trimmed.hasPrefix("allow_remote_control")
                && (trimmed.contains("yes") || trimmed.contains("socket"))
        }
    }

    static func hasListenOn(in contents: String) -> Bool {
        contents.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("listen_on") && !trimmed.hasPrefix("#")
        }
    }

    static func hasWatcher(in contents: String) -> Bool {
        contents.contains("juggler_watcher.py")
    }

    struct Status {
        var remoteControlEnabled = false
        var listenOnConfigured = false
        var watcherInstalled = false
    }

    static func status() -> Status {
        guard let contents = try? String(contentsOfFile: confFilePath, encoding: .utf8) else {
            return Status()
        }
        return Status(
            remoteControlEnabled: hasRemoteControl(in: contents),
            listenOnConfigured: hasListenOn(in: contents),
            watcherInstalled: hasWatcher(in: contents)
        )
    }

    static func appendToConf(_ line: String) -> String? {
        ConfigFileWriter.appendLine(
            line,
            toFileAt: confFilePath,
            createDirectories: true,
            duplicateCheck: .directiveKey
        )
    }
}

/// tmux config validation — extracted from SettingsView for testability.
enum TmuxConfigValidator {
    static func isConfigured(contents: String) -> Bool {
        contents.contains("update-environment")
            && (contents.contains("ITERM_SESSION_ID") || contents.contains("KITTY_WINDOW_ID"))
    }
}
