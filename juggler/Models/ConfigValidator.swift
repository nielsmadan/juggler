//
//  ConfigValidator.swift
//  Juggler
//

import Foundation

/// Kitty config file parsing — extracted from SettingsView for testability.
enum KittyConfigParser {
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
}

/// tmux config validation — extracted from SettingsView for testability.
enum TmuxConfigValidator {
    static func isConfigured(contents: String) -> Bool {
        contents.contains("update-environment")
            && (contents.contains("ITERM_SESSION_ID") || contents.contains("KITTY_WINDOW_ID"))
    }
}
