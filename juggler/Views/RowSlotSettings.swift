import SwiftUI

struct RowSlotSettings: DynamicProperty {
    @AppStorage(AppStorageKeys.monitorSlotTopLeading)
    private var topLeading = RowSlotPosition.topLeading.defaultSlot.rawValue
    @AppStorage(AppStorageKeys.monitorSlotTopTrailing)
    private var topTrailing = RowSlotPosition.topTrailing.defaultSlot.rawValue
    @AppStorage(AppStorageKeys.monitorSlotBottomLeading)
    private var bottomLeading = RowSlotPosition.bottomLeading.defaultSlot.rawValue
    @AppStorage(AppStorageKeys.monitorSlotBottomTrailing)
    private var bottomTrailing = RowSlotPosition.bottomTrailing.defaultSlot.rawValue

    var slots: [RowSlotPosition: RowSlot] {
        Dictionary(uniqueKeysWithValues: RowSlotPosition.allCases.map { ($0, slot(at: $0)) })
    }

    func slot(at position: RowSlotPosition) -> RowSlot {
        RowSlot(rawValue: storage(for: position).wrappedValue) ?? .none
    }

    func binding(for position: RowSlotPosition) -> Binding<RowSlot> {
        let raw = storage(for: position)
        return Binding(
            get: { RowSlot(rawValue: raw.wrappedValue) ?? .none },
            set: { raw.wrappedValue = $0.rawValue }
        )
    }

    private func storage(for position: RowSlotPosition) -> Binding<String> {
        switch position {
        case .topLeading: $topLeading
        case .topTrailing: $topTrailing
        case .bottomLeading: $bottomLeading
        case .bottomTrailing: $bottomTrailing
        }
    }
}
