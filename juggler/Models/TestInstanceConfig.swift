import Foundation

enum TestInstanceConfig {
    static func hookPortOverride(_ defaults: UserDefaults = .standard) -> UInt16? {
        let raw = defaults.integer(forKey: "hookPort")
        guard raw > 0, raw <= 65535 else { return nil }
        return UInt16(raw)
    }

    static func hookPort(_ defaults: UserDefaults = .standard) -> UInt16 {
        hookPortOverride(defaults) ?? 7483
    }

    static func daemonSocketFilename(_ defaults: UserDefaults = .standard) -> String {
        if let port = hookPortOverride(defaults) {
            return "iterm2_daemon_\(port).sock"
        }
        return "iterm2_daemon.sock"
    }
}
