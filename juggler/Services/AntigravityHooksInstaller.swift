import Foundation

enum AntigravityHooksError: LocalizedError, Equatable {
    case hooksJSONUnparseable(String)

    var errorDescription: String? {
        switch self {
        case let .hooksJSONUnparseable(path):
            "Antigravity hooks.json at \(path) isn't valid JSON. Fix or remove it, then retry."
        }
    }
}

/// Installs Juggler's Antigravity (agy) hooks. Simpler than Codex: no feature flag and no
/// trust gate — just copy the notify script and merge a top-level `"juggler"` key into the
/// shared global hooks.json. `PreInvocation` → working, `Stop` → idle.
enum AntigravityHooksInstaller {
    static let agentEvents = ["PreInvocation", "Stop"]

    /// Top-level key Juggler owns in hooks.json. Merge replaces it wholesale; uninstall
    /// removes it — leaving every other tool's hooks untouched.
    static let jugglerHookName = "juggler"

    static let hookTimeoutSeconds = 5

    static var geminiDirectory: String {
        NSString(string: "~/.gemini").expandingTildeInPath
    }

    static var hooksDirectory: String {
        geminiDirectory + "/hooks/juggler"
    }

    static var notifyScriptPath: String {
        hooksDirectory + "/notify.sh"
    }

    /// Global, shared with the Antigravity 2.0 IDE. IDE sessions carry no terminal env, so
    /// the notify script leaves them untyped and HookServer drops them.
    static var hooksJSONPath: String {
        geminiDirectory + "/config/hooks.json"
    }

    static func hookCommand(for event: String, notifyScriptPath: String = Self.notifyScriptPath) -> String {
        "\(notifyScriptPath) \(event)"
    }

    /// Installs notify.sh and registers the Juggler events in hooks.json.
    /// Returns nil on success, or an error message on failure. Paths and the bundled-script
    /// URL are injectable for testing; production callers omit them.
    static func installHooks(
        bundledScriptURL: URL? = Bundle.main.url(forResource: "antigravity-notify", withExtension: "sh"),
        hooksDirectory: String = Self.hooksDirectory,
        notifyScriptPath: String = Self.notifyScriptPath,
        hooksJSONPath: String = Self.hooksJSONPath
    ) -> String? {
        guard let bundledScript = bundledScriptURL else {
            return "Antigravity notify.sh not found in app bundle"
        }

        do {
            try FileManager.default.createDirectory(
                atPath: hooksDirectory,
                withIntermediateDirectories: true
            )

            let destination = URL(fileURLWithPath: notifyScriptPath)
            if FileManager.default.fileExists(atPath: notifyScriptPath) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: bundledScript, to: destination)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: notifyScriptPath
            )

            try mergeHooksJSON(at: hooksJSONPath, notifyScriptPath: notifyScriptPath)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Sets the top-level `"juggler"` key in hooks.json to Juggler's handlers, preserving
    /// every other top-level key. `PreInvocation`/`Stop` take a flat handler list (no
    /// matcher/hooks wrapper). Backs up a pre-existing file once (to <path>.juggler-backup).
    /// Throws if an existing file isn't a JSON object — rather than silently overwriting it.
    static func mergeHooksJSON(at path: String, notifyScriptPath: String) throws {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: path)

        var root: [String: Any] = [:]
        if existed {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            // An empty / whitespace-only file (e.g. a `touch`ed placeholder, or an
            // interrupted write to this IDE-shared file) has nothing to preserve — treat it
            // as `{}` rather than blocking install. Only non-empty-but-unparseable content
            // throws, so a real config is never silently clobbered.
            let isBlank = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !isBlank {
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AntigravityHooksError.hooksJSONUnparseable(path)
                }
                root = parsed
            }
        }

        var jugglerHooks: [String: Any] = [:]
        for event in agentEvents {
            jugglerHooks[event] = [
                [
                    "type": "command",
                    "command": hookCommand(for: event, notifyScriptPath: notifyScriptPath),
                    "timeout": hookTimeoutSeconds
                ]
            ]
        }
        root[jugglerHookName] = jugglerHooks

        let jsonData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        if existed {
            let backupPath = path + ".juggler-backup"
            if !fm.fileExists(atPath: backupPath) {
                try fm.copyItem(atPath: path, toPath: backupPath)
            }
        }

        // hooks.json lives in ~/.gemini/config, which may not exist yet.
        try fm.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// True when hooks.json has Juggler's handler registered for every event in `agentEvents`.
    static func areHooksRegistered(
        hooksJSONPath: String = Self.hooksJSONPath,
        notifyScriptPath: String = Self.notifyScriptPath
    ) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hooksJSONPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jugglerHooks = root[jugglerHookName] as? [String: Any]
        else {
            return false
        }
        return agentEvents.allSatisfy { event in
            guard let handlers = jugglerHooks[event] as? [[String: Any]] else { return false }
            let expected = hookCommand(for: event, notifyScriptPath: notifyScriptPath)
            return handlers.contains { ($0["command"] as? String) == expected }
        }
    }
}
