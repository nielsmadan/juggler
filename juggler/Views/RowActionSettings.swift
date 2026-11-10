import SwiftUI

struct RowActionSettings: DynamicProperty {
    @AppStorage private var first: String
    @AppStorage private var second: String
    @AppStorage private var third: String

    init(defaults: UserDefaults? = nil) {
        _first = Self.storage(for: .first, defaults: defaults)
        _second = Self.storage(for: .second, defaults: defaults)
        _third = Self.storage(for: .third, defaults: defaults)
    }

    var actions: [SessionRowAction] {
        RowActionPosition.allCases.compactMap(action(at:))
    }

    func action(at position: RowActionPosition) -> SessionRowAction? {
        SessionRowAction(rawValue: value(at: position).wrappedValue)
    }

    func binding(for position: RowActionPosition) -> Binding<SessionRowAction?> {
        let raw = value(at: position)
        return Binding(
            get: { SessionRowAction(rawValue: raw.wrappedValue) },
            set: { raw.wrappedValue = SessionRowAction.storageValue(for: $0) }
        )
    }

    private func value(at position: RowActionPosition) -> Binding<String> {
        switch position {
        case .first: $first
        case .second: $second
        case .third: $third
        }
    }

    private static func storage(for position: RowActionPosition, defaults: UserDefaults?) -> AppStorage<String> {
        AppStorage(wrappedValue: position.defaultAction.rawValue, position.storageKey, store: defaults)
    }
}
