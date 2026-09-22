import Foundation

/// Replaces the home-directory prefix with `~` in project paths shown in the monitor.
enum HomePathFormatter {
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home || path == home + "/" { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
