import Foundation
import Testing

func preservePersistentDefaults(_ keys: String...) throws -> () -> Void {
    let defaults = UserDefaults.standard
    let domain = try #require(Bundle.main.bundleIdentifier)
    let stored = defaults.persistentDomain(forName: domain) ?? [:]
    return {
        for key in keys {
            if let value = stored[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
