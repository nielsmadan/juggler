import CryptoKit
import Foundation

enum CodexHooksError: LocalizedError, Equatable {
    case hooksJSONNotFound(String)
    case hooksJSONUnparseable(String)
    case jugglerHooksNotRegistered(String)

    var errorDescription: String? {
        switch self {
        case let .hooksJSONNotFound(path):
            "Codex hooks.json not found at \(path). Run \"Install Hooks\" first."
        case let .hooksJSONUnparseable(path):
            "Codex hooks.json at \(path) isn't valid JSON. Fix or remove it, then retry."
        case .jugglerHooksNotRegistered:
            "Juggler's hooks aren't registered in hooks.json. Run \"Install Hooks\" first."
        }
    }
}

enum CodexHooksInstaller {
    static let agentEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PreCompact",
        "PostCompact",
        "PermissionRequest",
        "Stop"
    ]

    /// Timeout (seconds) written into each hook entry in hooks.json. Must stay in sync with
    /// the value folded into `computeTrustedHash` — Codex's trust hash covers the timeout.
    static let hookTimeoutSeconds = 5

    static var codexDirectory: String {
        NSString(string: "~/.codex").expandingTildeInPath
    }

    static var hooksDirectory: String {
        codexDirectory + "/hooks/juggler"
    }

    static var notifyScriptPath: String {
        hooksDirectory + "/notify.sh"
    }

    static var hooksJSONPath: String {
        codexDirectory + "/hooks.json"
    }

    static var configTOMLPath: String {
        codexDirectory + "/config.toml"
    }

    /// Installs the notify.sh script and registers all events in hooks.json.
    /// Returns nil on success, or an error message on failure.
    /// Paths and the bundled-script URL are injectable for testing; production callers omit them.
    static func installHooks(
        bundledScriptURL: URL? = Bundle.main.url(forResource: "codex-notify", withExtension: "sh"),
        hooksDirectory: String = Self.hooksDirectory,
        notifyScriptPath: String = Self.notifyScriptPath,
        hooksJSONPath: String = Self.hooksJSONPath
    ) -> String? {
        guard let bundledScript = bundledScriptURL else {
            return "Codex notify.sh not found in app bundle"
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

    /// Merges Juggler's hook events into the given hooks.json. Removes any pre-existing Juggler
    /// entries before re-adding. Backs up the pre-existing file before writing (to
    /// <path>.juggler-backup). Throws if an existing file can't be parsed as JSON — rather than
    /// silently overwriting it.
    static func mergeHooksJSON(at path: String, notifyScriptPath: String) throws {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: path)

        var root: [String: Any] = [:]
        if existed {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexHooksError.hooksJSONUnparseable(path)
            }
            root = parsed
        }

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]

        for event in agentEvents {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries = entries.filter { group in
                !groupIsJuggler(group, notifyScriptPath: notifyScriptPath)
            }
            let jugglerEntry: [String: Any] = [
                "hooks": [
                    [
                        "type": "command",
                        "command": "\(notifyScriptPath) \(event)",
                        "timeout": hookTimeoutSeconds
                    ]
                ]
            ]
            entries.append(jugglerEntry)
            hooks[event] = entries
        }

        root["hooks"] = hooks

        let jsonData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        // Back up the pre-existing file before overwriting it (once).
        if existed {
            let backupPath = path + ".juggler-backup"
            if !fm.fileExists(atPath: backupPath) {
                try fm.copyItem(atPath: path, toPath: backupPath)
            }
        }
        try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// True if a hooks.json matcher group contains a handler invoking Juggler's notify.sh.
    /// Loose substring match on the command — catches entries from older installs whose
    /// event argument may have drifted.
    private static func groupIsJuggler(_ group: [String: Any], notifyScriptPath: String) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { handler in
            (handler["command"] as? String)?.contains(notifyScriptPath) == true
        }
    }

    /// Ensures `[features] hooks = true` exists in the given config.toml, migrating away from
    /// the deprecated `codex_hooks` key if present. Idempotent. Preserves existing sections and
    /// keys. Backs up the pre-existing file on first modification (to <path>.juggler-backup).
    static func enableFeatureFlag(at path: String = configTOMLPath) throws {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: path)
        let original = try existed ? String(contentsOfFile: path, encoding: .utf8) : ""

        let updated = editedTOML(original: original)
        if updated != original {
            let backupPath = path + ".juggler-backup"
            if existed, !fm.fileExists(atPath: backupPath) {
                try original.write(toFile: backupPath, atomically: true, encoding: .utf8)
            }
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Returns true if the hooks feature is enabled in the [features] section.
    /// Accepts the current `hooks` key and the deprecated `codex_hooks` alias.
    static func isFeatureFlagEnabled(at path: String = configTOMLPath) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        var currentSection = ""
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }
            if currentSection == "features" {
                if let parsed = parseBoolAssignment(line: line, key: "hooks") {
                    return parsed
                }
                if let parsed = parseBoolAssignment(line: line, key: "codex_hooks") {
                    return parsed
                }
            }
        }
        return false
    }

    // MARK: - Codex hook trust

    /// Computes the `trusted_hash` Codex stores in `[hooks.state]` for a command hook.
    /// Mirrors Codex's canonical fingerprint: SHA-256 over sorted-key, compact JSON of
    /// `{"event_name":...,"hooks":[{"async":false,"command":...,"timeout":5,"type":"command"}]}`.
    static func computeTrustedHash(event: String, command: String) -> String {
        let handler: [String: Any] = [
            "async": false,
            "command": command,
            "timeout": hookTimeoutSeconds,
            "type": "command"
        ]
        let identity: [String: Any] = [
            "event_name": snakeCaseEvent(event),
            "hooks": [handler]
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: identity,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    /// Writes `[hooks.state]` trust entries for every Juggler hook into config.toml, so Codex
    /// runs them without the manual `/hooks` review step. Idempotent. Preserves all other
    /// config content. Backs up the pre-existing file on first modification (to
    /// <path>.juggler-backup). Throws if hooks.json is missing, unparseable, or has no Juggler
    /// hooks registered — trust entries can only be written for registered hooks.
    static func enableInCodex(
        at path: String = configTOMLPath,
        hooksJSONPath: String = Self.hooksJSONPath,
        notifyScriptPath: String = Self.notifyScriptPath
    ) throws {
        let indices = try jugglerGroupIndices(
            hooksJSONPath: hooksJSONPath,
            notifyScriptPath: notifyScriptPath
        )

        let fm = FileManager.default
        let existed = fm.fileExists(atPath: path)
        let original = try existed ? String(contentsOfFile: path, encoding: .utf8) : ""

        let updated = upsertTrustEntries(
            original: original,
            indices: indices,
            hooksJSONPath: hooksJSONPath,
            notifyScriptPath: notifyScriptPath
        )
        if updated != original {
            let backupPath = path + ".juggler-backup"
            if existed, !fm.fileExists(atPath: backupPath) {
                try original.write(toFile: backupPath, atomically: true, encoding: .utf8)
            }
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Returns true only when config.toml has a matching `trusted_hash` for every Juggler hook
    /// registered in hooks.json. Any missing/unparseable hooks.json, unresolvable event, or
    /// hash mismatch → false.
    static func isEnabledInCodex(
        at path: String = configTOMLPath,
        hooksJSONPath: String = Self.hooksJSONPath,
        notifyScriptPath: String = Self.notifyScriptPath
    ) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              let indices = try? jugglerGroupIndices(
                  hooksJSONPath: hooksJSONPath,
                  notifyScriptPath: notifyScriptPath
              ),
              indices.count == agentEvents.count
        else {
            return false
        }

        let foundHashes = parseHookStateHashes(from: contents)
        for (event, groupIndex) in indices {
            let key = trustEntryKey(event: event, groupIndex: groupIndex, hooksJSONPath: hooksJSONPath)
            let expected = computeTrustedHash(
                event: event,
                command: hookCommand(for: event, notifyScriptPath: notifyScriptPath)
            )
            guard foundHashes[key] == expected else { return false }
        }
        return true
    }

    static func hookCommand(for event: String, notifyScriptPath: String = Self.notifyScriptPath) -> String {
        "\(notifyScriptPath) \(event)"
    }

    /// Reads and parses hooks.json, returning the Juggler matcher-group index for each of
    /// `agentEvents` that has a Juggler hook registered. Throws if the file is missing,
    /// unparseable, or contains no Juggler hooks at all.
    private static func jugglerGroupIndices(
        hooksJSONPath: String,
        notifyScriptPath: String
    ) throws -> [(event: String, groupIndex: Int)] {
        guard FileManager.default.fileExists(atPath: hooksJSONPath) else {
            throw CodexHooksError.hooksJSONNotFound(hooksJSONPath)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hooksJSONPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CodexHooksError.hooksJSONUnparseable(hooksJSONPath)
        }
        var result: [(event: String, groupIndex: Int)] = []
        for event in agentEvents {
            if let index = jugglerGroupIndex(in: root, event: event, notifyScriptPath: notifyScriptPath) {
                result.append((event, index))
            }
        }
        guard !result.isEmpty else {
            throw CodexHooksError.jugglerHooksNotRegistered(hooksJSONPath)
        }
        return result
    }

    /// Finds the matcher-group index in `hooks.json` whose handler command exactly matches
    /// Juggler's hook command for `event`. Returns the first match (post-dedup there is at
    /// most one). Returns nil if Juggler's hook isn't registered for the event.
    private static func jugglerGroupIndex(
        in hooksJSON: [String: Any],
        event: String,
        notifyScriptPath: String
    ) -> Int? {
        guard let hooks = hooksJSON["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]]
        else {
            return nil
        }
        let expectedCommand = hookCommand(for: event, notifyScriptPath: notifyScriptPath)
        return groups.firstIndex { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
            return handlers.contains { ($0["command"] as? String) == expectedCommand }
        }
    }

    /// Parses all `[hooks.state."<key>"]` → `trusted_hash` pairs from config.toml contents.
    private static func parseHookStateHashes(from contents: String) -> [String: String] {
        var found: [String: String] = [:]
        var currentKey: String?
        for rawLine in contents.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                if trimmed.hasPrefix("[hooks.state.\""), trimmed.hasSuffix("\"]") {
                    currentKey = String(trimmed.dropFirst("[hooks.state.\"".count).dropLast("\"]".count))
                } else {
                    currentKey = nil
                }
                continue
            }
            if let key = currentKey,
               let hash = parseStringAssignment(line: trimmed, key: "trusted_hash") {
                found[key] = hash
            }
        }
        return found
    }

    private static func snakeCaseEvent(_ event: String) -> String {
        switch event {
        case "SessionStart": "session_start"
        case "UserPromptSubmit": "user_prompt_submit"
        case "PreToolUse": "pre_tool_use"
        case "PostToolUse": "post_tool_use"
        case "PreCompact": "pre_compact"
        case "PostCompact": "post_compact"
        case "PermissionRequest": "permission_request"
        case "Stop": "stop"
        default: event.lowercased()
        }
    }

    /// Codex's `[hooks.state]` key: `<hooksJSONPath>:<snake_event>:<groupIndex>:<handlerIndex>`.
    /// The handler index is always 0 — Juggler registers a single-handler matcher group per event.
    private static func trustEntryKey(event: String, groupIndex: Int, hooksJSONPath: String) -> String {
        "\(hooksJSONPath):\(snakeCaseEvent(event)):\(groupIndex):0"
    }

    /// Re-appends a fresh `[hooks.state."..."]` block for each resolved Juggler hook, removing
    /// only the exact blocks it is about to rewrite. Leaves all other content untouched —
    /// including the user's own trust blocks (which, for an event the user also hooks, share
    /// the `<hooksJSONPath>:<event>:` prefix but differ in group index).
    ///
    /// We deliberately do NOT prefix-match for "stale-key cleanup": a `<path>:<event>:0:0`
    /// block, once Juggler moves to index 1, is the *user's* slot, not a stale Juggler key —
    /// deleting it un-trusts the user's hook. The only genuine orphan (Juggler moving 1→0,
    /// leaving a dead `:1:0`) is harmless: Codex never computes a key for a group index that
    /// no longer exists in hooks.json. `uninstall.sh` garbage-collects orphans on reset.
    private static func upsertTrustEntries(
        original: String,
        indices: [(event: String, groupIndex: Int)],
        hooksJSONPath: String,
        notifyScriptPath: String
    ) -> String {
        // Remove only the exact keys we are about to rewrite — never prefix-match.
        let currentKeys = Set(indices.map {
            trustEntryKey(event: $0.event, groupIndex: $0.groupIndex, hooksJSONPath: hooksJSONPath)
        })
        func isJugglerHeader(_ trimmed: String) -> Bool {
            guard trimmed.hasPrefix("[hooks.state.\""), trimmed.hasSuffix("\"]") else { return false }
            let key = String(trimmed.dropFirst("[hooks.state.\"".count).dropLast("\"]".count))
            return currentKeys.contains(key)
        }

        let lines = original.isEmpty ? [] : original.components(separatedBy: "\n")
        var preservedLines: [String] = []
        var skipping = false
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                skipping = isJugglerHeader(trimmed)
            }
            if !skipping {
                preservedLines.append(rawLine)
            }
        }
        while let last = preservedLines.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty {
            preservedLines.removeLast()
        }

        var blocks = ""
        for (event, groupIndex) in indices {
            let key = trustEntryKey(event: event, groupIndex: groupIndex, hooksJSONPath: hooksJSONPath)
            let hash = computeTrustedHash(
                event: event,
                command: hookCommand(for: event, notifyScriptPath: notifyScriptPath)
            )
            blocks += "[hooks.state.\"\(key)\"]\ntrusted_hash = \"\(hash)\"\n\n"
        }
        if blocks.hasSuffix("\n") { blocks.removeLast() } // collapse to a single trailing newline

        let preserved = preservedLines.joined(separator: "\n")
        if preserved.isEmpty {
            return blocks
        }
        return preserved + "\n\n" + blocks
    }

    /// Returns the string value if `line` is `<key> = "<value>"`, tolerating a trailing
    /// `# comment`. Pragmatic parser for Juggler's known-shape values — it extracts the
    /// first `"..."` quoted substring and does not handle escaped quotes or `#` inside the
    /// quoted string. Returns nil otherwise.
    private static func parseStringAssignment(line: String, key: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard parts[0].trimmingCharacters(in: .whitespaces) == key else { return nil }
        let rhs = parts[1]
        guard let open = rhs.firstIndex(of: "\"") else { return nil }
        let afterOpen = rhs.index(after: open)
        guard let close = rhs[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(rhs[afterOpen ..< close])
    }

    // MARK: - TOML helpers

    private static func editedTOML(original: String) -> String {
        // Case: missing or empty file
        if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[features]\nhooks = true\n"
        }

        var lines = original.components(separatedBy: "\n")
        var currentSection = ""
        var featuresEnd: Int? // index *after* last line of [features] (exclusive)
        var hooksIndex: Int? // line index of `hooks = ...` in [features]
        var legacyIndex: Int? // line index of deprecated `codex_hooks = ...` in [features]

        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                if currentSection == "features" {
                    featuresEnd = idx
                }
                currentSection = String(line.dropFirst().dropLast())
                continue
            }
            if currentSection == "features" {
                if parseBoolAssignment(line: line, key: "hooks") != nil {
                    hooksIndex = idx
                }
                if parseBoolAssignment(line: line, key: "codex_hooks") != nil {
                    legacyIndex = idx
                }
            }
        }
        if currentSection == "features", featuresEnd == nil {
            featuresEnd = lines.count
        }

        // `hooks` key already present: set it true, drop any deprecated alias.
        if let hooksIndex {
            lines[hooksIndex] = "hooks = true"
            if let legacyIndex {
                lines.remove(at: legacyIndex)
            }
            return joinPreservingTrailingNewline(lines: lines, original: original)
        }

        // Only the deprecated alias present: migrate it in place.
        if let legacyIndex {
            lines[legacyIndex] = "hooks = true"
            return joinPreservingTrailingNewline(lines: lines, original: original)
        }

        // [features] section exists but no flag: insert at end of section.
        if let featuresEnd {
            lines.insert("hooks = true", at: featuresEnd)
            return joinPreservingTrailingNewline(lines: lines, original: original)
        }

        // No [features] section: append one.
        var trailing = original
        if !trailing.hasSuffix("\n") { trailing += "\n" }
        trailing += "\n[features]\nhooks = true\n"
        return trailing
    }

    private static func joinPreservingTrailingNewline(lines: [String], original: String) -> String {
        var out = lines.joined(separator: "\n")
        if original.hasSuffix("\n"), !out.hasSuffix("\n") {
            out += "\n"
        }
        return out
    }

    /// Returns Bool if `line` is `<key> = true|false`, tolerating surrounding whitespace
    /// and a trailing `# comment`. Returns nil otherwise.
    private static func parseBoolAssignment(line: String, key: String) -> Bool? {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        guard lhs == key else { return nil }
        // Strip a trailing `# comment` — a bare bool value cannot legally contain `#`.
        var rhs = parts[1].trimmingCharacters(in: .whitespaces)
        if let hashIndex = rhs.firstIndex(of: "#") {
            rhs = String(rhs[..<hashIndex]).trimmingCharacters(in: .whitespaces)
        }
        switch rhs {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}
