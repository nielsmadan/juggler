import Foundation

enum PiExtensionInstaller {
    /// Resolves Pi's agent config directory. Pi honors `PI_CODING_AGENT_DIR`
    /// (default `~/.pi/agent`); extensions are auto-discovered from its
    /// `extensions/` subdirectory. Global extensions need no trust step.
    /// Mirrors hooklinesinker's own resolution, so the UI can name the file it wrote.
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
        extensionsDirectory + "/hooklinesinker-pi.ts"
    }

    /// Writing the extension is hooklinesinker's job; installing also clears the legacy
    /// `juggler-pi.ts` this app used to write.
    static func install(client: HooklinesinkerClient = .shared) async throws {
        let result = await client.installHooks(agent: .pi)
        guard result.isSuccess else {
            throw HooklinesinkerClientError.commandFailed(
                command: "hooks install --agent pi",
                status: result.exitStatus,
                standardError: result.standardError
            )
        }
    }
}
