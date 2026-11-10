import Foundation

enum SessionTitleMode: String, CaseIterable {
    case tabTitle
    case windowTitle
    case windowAndTabTitle
    case folderName
    case parentAndFolderName
    case agentTitle

    static let `default`: SessionTitleMode = .parentAndFolderName

    static func stored(in defaults: UserDefaults = .standard) -> SessionTitleMode {
        defaults.string(forKey: AppStorageKeys.sessionTitleMode).flatMap(SessionTitleMode.init(rawValue:)) ?? .default
    }

    var displayName: String {
        switch self {
        case .tabTitle: "Tab Title"
        case .windowTitle: "Window Title"
        case .windowAndTabTitle: "Window / Tab Title"
        case .folderName: "Folder Name"
        case .parentAndFolderName: "Parent / Folder Name"
        case .agentTitle: "Agent Session Title"
        }
    }
}
