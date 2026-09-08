import Foundation

enum OpenCodePluginInstaller {
    /// Resolves the OpenCode config directory following OpenCode's search order:
    /// 1. $OPENCODE_CONFIG_DIR (dedicated override)
    /// 2. $XDG_CONFIG_HOME/opencode
    /// 3. ~/.config/opencode (default)
    /// Mirrors hooklinesinker's own resolution, so the UI can name the file it wrote.
    static var configDirectory: String {
        if let openCodeDir = ProcessInfo.processInfo.environment["OPENCODE_CONFIG_DIR"],
           !openCodeDir.isEmpty {
            return (openCodeDir as NSString).expandingTildeInPath
        }
        return XDGPaths.configHome + "/opencode"
    }

    static var pluginFilePath: String {
        configDirectory + "/plugins/hooklinesinker-opencode.ts"
    }

    /// Writing the plugin is hooklinesinker's job; installing also clears the legacy
    /// `juggler-opencode.ts` this app used to write.
    static func install(client: HooklinesinkerClient = .shared) async throws {
        let result = await client.installHooks(agent: .opencode)
        guard result.isSuccess else {
            throw HooklinesinkerClientError.commandFailed(
                command: "hooks install --agent opencode",
                status: result.exitStatus,
                standardError: result.standardError
            )
        }
    }
}
