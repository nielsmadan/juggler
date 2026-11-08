import SwiftUI

struct RowActionSettings: DynamicProperty {
    @AppStorage private var showRename: Bool
    @AppStorage private var showNote: Bool
    @AppStorage private var showHide: Bool

    init(defaults: UserDefaults? = nil) {
        _showRename = AppStorage(wrappedValue: true, AppStorageKeys.monitorShowRenameButton, store: defaults)
        _showNote = AppStorage(wrappedValue: true, AppStorageKeys.monitorShowNoteButton, store: defaults)
        _showHide = AppStorage(wrappedValue: true, AppStorageKeys.monitorShowHideButton, store: defaults)
    }

    var actions: [SessionRowAction] {
        SessionRowAction.visible(rename: showRename, note: showNote, hide: showHide)
    }

    func binding(for action: SessionRowAction) -> Binding<Bool> {
        switch action {
        case .rename: $showRename
        case .note: $showNote
        case .hide: $showHide
        }
    }
}
