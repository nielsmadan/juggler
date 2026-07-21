import Foundation

enum PiExtensionInstaller {
    /// Resolves Pi's agent config directory. Pi honors `PI_CODING_AGENT_DIR`
    /// (default `~/.pi/agent`); extensions are auto-discovered from its
    /// `extensions/` subdirectory. Global extensions need no trust step.
    static var agentDirectory: String {
        if let piDir = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"],
           !piDir.isEmpty {
            return (piDir as NSString).expandingTildeInPath
        }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/.pi/agent"
    }

    static var extensionsDirectory: String {
        agentDirectory + "/extensions"
    }

    static var extensionFilePath: String {
        extensionsDirectory + "/juggler-pi.ts"
    }

    static func install() throws {
        guard let sourceURL = Bundle.main.url(forResource: "juggler-pi", withExtension: "txt") else {
            throw NSError(domain: "PiExtensionInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Extension resource not found in bundle"])
        }
        try FileManager.default.createDirectory(atPath: extensionsDirectory, withIntermediateDirectories: true)
        let extensionFile = URL(fileURLWithPath: extensionFilePath)
        if FileManager.default.fileExists(atPath: extensionFilePath) {
            try FileManager.default.removeItem(at: extensionFile)
        }
        try FileManager.default.copyItem(at: sourceURL, to: extensionFile)
    }
}
