import Foundation

enum SessionTitleMode: String, CaseIterable {
    case tabTitle = "tabTitle"
    case windowTitle = "windowTitle"
    case windowAndTabTitle = "windowAndTabTitle"
    case folderName = "folderName"
    case parentAndFolderName = "parentAndFolderName"

    var displayName: String {
        switch self {
        case .tabTitle: "Tab Title"
        case .windowTitle: "Window Title"
        case .windowAndTabTitle: "Window / Tab Title"
        case .folderName: "Folder Name"
        case .parentAndFolderName: "Parent / Folder Name"
        }
    }
}
