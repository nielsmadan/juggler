import Foundation
import ShortcutField

extension Shortcut {
    func save(to key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(from key: String) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    static func remove(from key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension Notification.Name {
    static let localShortcutsDidChange = Notification.Name("localShortcutsDidChange")
}
