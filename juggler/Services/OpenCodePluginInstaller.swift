import Foundation

enum OpenCodePluginInstaller {
    /// Resolves the OpenCode config directory following OpenCode's search order:
    /// 1. $OPENCODE_CONFIG_DIR (dedicated override)
    /// 2. $XDG_CONFIG_HOME/opencode
    /// 3. ~/.config/opencode (default)
    static var configDirectory: String {
        if let openCodeDir = ProcessInfo.processInfo.environment["OPENCODE_CONFIG_DIR"],
           !openCodeDir.isEmpty {
            return (openCodeDir as NSString).expandingTildeInPath
        }
        return XDGPaths.configHome + "/opencode"
    }

    static var pluginFilePath: String {
        configDirectory + "/plugins/juggler-opencode.ts"
    }

    static func install() throws {
        guard let sourceURL = Bundle.main.url(forResource: "juggler-opencode", withExtension: "txt") else {
            throw NSError(domain: "OpenCodePluginInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Plugin resource not found in bundle"])
        }
        let pluginsDir = URL(fileURLWithPath: configDirectory).appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let pluginFile = pluginsDir.appendingPathComponent("juggler-opencode.ts")
        if FileManager.default.fileExists(atPath: pluginFile.path) {
            try FileManager.default.removeItem(at: pluginFile)
        }
        try FileManager.default.copyItem(at: sourceURL, to: pluginFile)
    }
}
