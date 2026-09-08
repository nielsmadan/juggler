import CryptoKit
import Foundation

enum CodexHooksError: LocalizedError, Equatable {
    case hooksNotRegistered(String)
    case hooksUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .hooksNotRegistered:
            "Juggler's hooks aren't registered in hooks.json. Run \"Install Hooks\" first."
        case let .hooksUnsupported(path):
            "Codex hooks.json at \(path) has a shape Juggler can't safely edit. Fix or remove it, then retry."
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
        "Stop",
        "SessionEnd"
    ]

    /// Default hook timeout (seconds). Per-event values go through `timeoutSeconds(for:)`,
    /// which both the hooks.json writer and the trust hash use — they cannot drift apart.
    static let hookTimeoutSeconds = 5

    /// Codex clamps SessionEnd hooks to 3s and fingerprints the *post-clamp* timeout, so an
    /// entry written with `hookTimeoutSeconds` installs cleanly but never matches its trust
    /// record — the hook silently never runs.
    static let sessionEndTimeoutSeconds = 3

    static func timeoutSeconds(for event: String) -> Int {
        event == "SessionEnd" ? sessionEndTimeoutSeconds : hookTimeoutSeconds
    }

    static var codexDirectory: String {
        NSString(string: "~/.codex").expandingTildeInPath
    }

    static var hooksJSONPath: String {
        codexDirectory + "/hooks.json"
    }

    static var configTOMLPath: String {
        codexDirectory + "/config.toml"
    }

    /// Registering hook events in hooks.json is hooklinesinker's job; the feature flag and
    /// trust steps below stay here because no other agent needs them.
    /// Returns nil on success, or the CLI's own failure text.
    static func installHooks(client: HooklinesinkerClient = .shared) async -> String? {
        let result = await client.installHooks(agent: .codex)
        return result.isSuccess ? nil : result.failureMessage
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
            let line = removingTOMLComment(from: String(rawLine))
                .trimmingCharacters(in: .whitespaces)
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

    static func isAutoReviewEnabled(at path: String = configTOMLPath) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        var currentSection = ""
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = removingTOMLComment(from: String(rawLine))
                .trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }
            if currentSection.isEmpty,
               let reviewer = parseStringAssignment(line: line, key: "approvals_reviewer") {
                return reviewer == "auto_review"
            }
        }
        return false
    }

    // MARK: - Codex hook trust

    /// Computes the `trusted_hash` Codex stores in `[hooks.state]` for a command hook.
    /// Mirrors Codex's canonical fingerprint: SHA-256 over sorted-key, compact JSON of
    /// `{"event_name":...,"hooks":[{"async":false,"command":...,"timeout":N,"type":"command"}]}`,
    /// where N is the event's `timeoutSeconds(for:)` — Codex hashes the clamped value.
    static func computeTrustedHash(event: String, command: String) -> String {
        let handler: [String: Any] = [
            "async": false,
            "command": command,
            "timeout": timeoutSeconds(for: event),
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

    /// Writes `[hooks.state]` trust entries for every hook `hooks status --agent codex --json`
    /// reported into config.toml, so Codex runs them without the manual `/hooks` review step.
    /// Idempotent. Preserves all other config content. Backs up the pre-existing file on first
    /// modification (to <path>.juggler-backup). Throws when the CLI reported no registered
    /// hooks — trust entries can only be written for registered hooks.
    static func enableInCodex(
        at path: String = configTOMLPath,
        hooksJSONPath: String,
        entries: [HooklinesinkerHookEntry]
    ) throws {
        guard !entries.isEmpty else {
            throw CodexHooksError.hooksNotRegistered(hooksJSONPath)
        }

        let fm = FileManager.default
        let existed = fm.fileExists(atPath: path)
        let original = try existed ? String(contentsOfFile: path, encoding: .utf8) : ""

        let updated = upsertTrustEntries(
            original: original,
            entries: entries,
            hooksJSONPath: hooksJSONPath
        )
        if updated != original {
            let backupPath = path + ".juggler-backup"
            if existed, !fm.fileExists(atPath: backupPath) {
                try original.write(toFile: backupPath, atomically: true, encoding: .utf8)
            }
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Removes the `[hooks.state]` blocks Juggler wrote for the hooks the CLI reported, so a
    /// reset doesn't leave Codex trusting commands that no longer exist. Must be called while
    /// the hooks are still registered: the keys are built from the group indexes hooks.json
    /// currently holds. A block sitting at one of our keys whose stored hash isn't the one we
    /// would write belongs to someone else and is left alone. Returns true when the file changed.
    @discardableResult
    static func removeTrustEntries(
        at path: String = configTOMLPath,
        hooksJSONPath: String,
        entries: [HooklinesinkerHookEntry]
    ) throws -> Bool {
        guard !entries.isEmpty, FileManager.default.fileExists(atPath: path) else { return false }
        let original = try String(contentsOfFile: path, encoding: .utf8)
        let ours = trustedHashesByKey(entries: entries, hooksJSONPath: hooksJSONPath)

        let retained = splitSections(original).filter { section in
            guard let key = hookStateKey(section.first), let expected = ours[key] else { return true }
            return sectionHash(section) != expected
        }
        var updated = retained.flatMap(\.self).joined(separator: "\n")
        guard updated != original else { return false }

        while updated.hasSuffix("\n\n") {
            updated.removeLast()
        }
        if original.hasSuffix("\n"), !updated.isEmpty, !updated.hasSuffix("\n") {
            updated += "\n"
        }
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    /// Returns true only when config.toml has a matching `trusted_hash` for every event
    /// hooklinesinker registers. A short entry list, an unreadable config, or any hash
    /// mismatch → false.
    static func isEnabledInCodex(
        at path: String = configTOMLPath,
        hooksJSONPath: String,
        entries: [HooklinesinkerHookEntry]
    ) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              entries.count == agentEvents.count
        else {
            return false
        }

        let foundHashes = parseHookStateHashes(from: contents)
        return trustedHashesByKey(entries: entries, hooksJSONPath: hooksJSONPath)
            .allSatisfy { key, expected in foundHashes[key] == expected }
    }

    /// The `[hooks.state]` key → `trusted_hash` pair Juggler writes for each reported hook.
    /// The single place the key shape and the hashed command come together, so writing,
    /// checking and removing can never disagree about what "Juggler's entry" means.
    private static func trustedHashesByKey(
        entries: [HooklinesinkerHookEntry],
        hooksJSONPath: String
    ) -> [String: String] {
        var pairs: [String: String] = [:]
        for entry in entries {
            let key = trustEntryKey(
                event: entry.event, groupIndex: entry.groupIndex, hooksJSONPath: hooksJSONPath
            )
            pairs[key] = computeTrustedHash(event: entry.event, command: entry.command)
        }
        return pairs
    }

    private static func splitSections(_ contents: String) -> [[String]] {
        var sections: [[String]] = [[]]
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                sections.append([])
            }
            sections[sections.count - 1].append(line)
        }
        return sections
    }

    private static func hookStateKey(_ header: String?) -> String? {
        guard let trimmed = header?.trimmingCharacters(in: .whitespaces),
              trimmed.hasPrefix("[hooks.state.\""), trimmed.hasSuffix("\"]")
        else { return nil }
        return String(trimmed.dropFirst("[hooks.state.\"".count).dropLast("\"]".count))
    }

    private static func sectionHash(_ section: [String]) -> String? {
        for line in section.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let hash = parseStringAssignment(line: trimmed, key: "trusted_hash") {
                return hash
            }
        }
        return nil
    }

    /// True when config.toml already carries a matching trust entry for at least one currently
    /// registered Juggler hook. Refreshing trust the user already granted is maintenance;
    /// writing the first one for them is not — that grant is Codex's `/hooks` review to make.
    /// Matches a full key+hash pair rather than prefix-matching, so a user's own hook registered
    /// in the same hooks.json is never mistaken for consent.
    static func hasExistingTrustEntries(
        at path: String = configTOMLPath,
        hooksJSONPath: String,
        entries: [HooklinesinkerHookEntry]
    ) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        let found = parseHookStateHashes(from: contents)
        return trustedHashesByKey(entries: entries, hooksJSONPath: hooksJSONPath)
            .contains { key, expected in found[key] == expected }
    }

    /// True only when *every* current entry resolves to a present trust key+hash. A foreign
    /// hook appearing on an event we already hook shifts our group index (part of the key), so
    /// the entry stays installed but silently untrusted; this returns false there while
    /// `hasExistingTrustEntries` still returns true for the entries that did not move.
    static func allEntriesTrusted(
        at path: String = configTOMLPath,
        hooksJSONPath: String,
        entries: [HooklinesinkerHookEntry]
    ) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        let found = parseHookStateHashes(from: contents)
        let expected = trustedHashesByKey(entries: entries, hooksJSONPath: hooksJSONPath)
        guard !expected.isEmpty else { return false }
        return expected.allSatisfy { key, hash in found[key] == hash }
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
        case "SessionEnd": "session_end"
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
        entries: [HooklinesinkerHookEntry],
        hooksJSONPath: String
    ) -> String {
        let currentKeys = Set(entries.map {
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
        for entry in entries {
            let key = trustEntryKey(
                event: entry.event, groupIndex: entry.groupIndex, hooksJSONPath: hooksJSONPath
            )
            let hash = computeTrustedHash(event: entry.event, command: entry.command)
            blocks += "[hooks.state.\"\(key)\"]\ntrusted_hash = \"\(hash)\"\n\n"
        }
        if blocks.hasSuffix("\n") { blocks.removeLast() } // collapse to a single trailing newline

        let preserved = preservedLines.joined(separator: "\n")
        if preserved.isEmpty {
            return blocks
        }
        return preserved + "\n\n" + blocks
    }

    /// Returns the quoted string value from Juggler's known-shape TOML assignments.
    private static func parseStringAssignment(line: String, key: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard parts[0].trimmingCharacters(in: .whitespaces) == key else { return nil }
        let rhs = parts[1].trimmingCharacters(in: .whitespaces)
        guard let quote = rhs.first, quote == "\"" || quote == "'" else { return nil }

        var escaped = false
        for index in rhs.indices.dropFirst() {
            let character = rhs[index]
            if quote == "\"", character == "\\", !escaped {
                escaped = true
                continue
            }
            if character == quote, !escaped {
                return String(rhs[rhs.index(after: rhs.startIndex) ..< index])
            }
            escaped = false
        }
        return nil
    }

    private static func removingTOMLComment(from line: String) -> String {
        var quote: Character?
        var escaped = false

        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if activeQuote == "\"", character == "\\", !escaped {
                    escaped = true
                    continue
                }
                if character == activeQuote, !escaped {
                    quote = nil
                }
                escaped = false
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
        }
        return line
    }

    // MARK: - TOML helpers

    private static func editedTOML(original: String) -> String {
        if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[features]\nhooks = true\n"
        }

        var lines = original.components(separatedBy: "\n")
        var currentSection = ""
        var featuresEnd: Int? // index *after* last line of [features] (exclusive)
        var hooksLineIndex: Int?
        var legacyCodexHooksLineIndex: Int?

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
                    hooksLineIndex = idx
                }
                if parseBoolAssignment(line: line, key: "codex_hooks") != nil {
                    legacyCodexHooksLineIndex = idx
                }
            }
        }
        if currentSection == "features", featuresEnd == nil {
            featuresEnd = lines.count
        }

        if let hooksLineIndex {
            lines[hooksLineIndex] = "hooks = true"
            if let legacyCodexHooksLineIndex {
                lines.remove(at: legacyCodexHooksLineIndex)
            }
            return joinPreservingTrailingNewline(lines: lines, original: original)
        }

        if let legacyCodexHooksLineIndex {
            lines[legacyCodexHooksLineIndex] = "hooks = true"
            return joinPreservingTrailingNewline(lines: lines, original: original)
        }

        if let featuresEnd {
            lines.insert("hooks = true", at: featuresEnd)
            return joinPreservingTrailingNewline(lines: lines, original: original)
        }

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
