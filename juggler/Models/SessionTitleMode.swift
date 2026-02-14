import Foundation

enum SessionTitleMode: String, CaseIterable {
    case tabTitle
    case windowTitle
    case windowAndTabTitle
    case folderName
    case parentAndFolderName

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
