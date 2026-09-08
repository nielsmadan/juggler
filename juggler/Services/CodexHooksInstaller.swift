import CryptoKit
import Foundation

enum CodexHooksError: LocalizedError, Equatable {
    case hooksNotRegistered(String)
    case hooksUnsupported(String)
    case configUnsupported

    var errorDescription: String? {
        switch self {
        case .hooksNotRegistered:
            "Juggler's hooks aren't registered in hooks.json. Run \"Install Hooks\" first."
        case let .hooksUnsupported(path):
            "Codex hooks.json at \(path) has a shape Juggler can't safely edit. Fix or remove it, then retry."
        case .configUnsupported:
            "Codex config.toml has malformed strings, brackets, or table headers. Fix it before enabling hooks."
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

        let updated = try editedTOML(original: original)
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
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              let lines = try? scannedTOMLLines(contents) else {
            return false
        }
        var currentSection = ""
        for (_, line) in lines {
            if line.hasPrefix("[") {
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
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              let lines = try? scannedTOMLLines(contents) else {
            return false
        }
        var currentSection = ""
        for (_, line) in lines {
            if line.hasPrefix("[") {
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

        let updated = try upsertTrustEntries(
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
    /// The single place the key shape and the hashed command come together for trust writing and checks.
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
        guard let lines = try? scannedTOMLLines(contents) else { return [:] }
        var found: [String: String] = [:]
        var currentKey: String?
        for (_, trimmed) in lines {
            if trimmed.hasPrefix("[") {
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
    ) throws -> String {
        let currentKeys = Set(entries.map {
            trustEntryKey(event: $0.event, groupIndex: $0.groupIndex, hooksJSONPath: hooksJSONPath)
        })
        func isJugglerHeader(_ trimmed: String) -> Bool {
            guard trimmed.hasPrefix("[hooks.state.\""), trimmed.hasSuffix("\"]") else { return false }
            let key = String(trimmed.dropFirst("[hooks.state.\"".count).dropLast("\"]".count))
            return currentKeys.contains(key)
        }

        let lines = try scannedTOMLLines(original)
        var preservedLines: [String] = []
        var skipping = false
        for (rawLine, statement) in lines {
            if statement.hasPrefix("[") {
                skipping = isJugglerHeader(statement)
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

    private static func scannedTOMLLines(_ contents: String) throws -> [(raw: String, statement: String)] {
        var scanner = TOMLStatementScanner()
        let lines = try contents.components(separatedBy: "\n").map { line in
            try (raw: line, statement: scanner.statement(in: line))
        }
        guard scanner.quote == nil, scanner.brackets.isEmpty else {
            throw CodexHooksError.configUnsupported
        }
        return lines
    }

    private struct TOMLStatementScanner {
        var quote: Character?
        var multiline = false
        var brackets: [Character] = []

        mutating func statement(in line: String) throws -> String {
            let startsStatement = quote == nil && brackets.isEmpty
            let characters = Array(line)
            var position = 0
            scan: while position < characters.count {
                let character = characters[position]
                if let quote {
                    try consumeQuoted(characters, quote: quote, position: &position)
                    continue
                }
                switch character {
                case "#":
                    break scan
                case "\"", "'":
                    quote = character
                    multiline = position + 2 < characters.count
                        && characters[position + 1] == character && characters[position + 2] == character
                    position += multiline ? 3 : 1
                case "[", "{":
                    brackets.append(character)
                    position += 1
                case "]", "}":
                    guard brackets.popLast() == (character == "]" ? "[" : "{") else {
                        throw CodexHooksError.configUnsupported
                    }
                    position += 1
                default:
                    position += 1
                }
            }
            guard quote == nil || multiline else { throw CodexHooksError.configUnsupported }
            let statement = startsStatement
                ? String(characters.prefix(position)).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            if statement.hasPrefix("["), quote != nil || !brackets.isEmpty || !statement.hasSuffix("]") {
                throw CodexHooksError.configUnsupported
            }
            return statement
        }

        private mutating func consumeQuoted(_ characters: [Character], quote: Character, position: inout Int) throws {
            if quote == "\"", characters[position] == "\\" {
                position += 2
                return
            }
            guard characters[position] == quote else {
                position += 1
                return
            }
            var count = 1
            if multiline {
                while position + count < characters.count, characters[position + count] == quote {
                    count += 1
                }
                if count < 3 {
                    position += count
                    return
                }
                guard count <= 5 else { throw CodexHooksError.configUnsupported }
            }
            self.quote = nil
            position += count
        }
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

    // MARK: - TOML helpers

    private static func editedTOML(original: String) throws -> String {
        if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[features]\nhooks = true\n"
        }

        let scannedLines = try scannedTOMLLines(original)
        var lines = scannedLines.map(\.raw)
        var currentSection = ""
        var featuresEnd: Int? // index *after* last line of [features] (exclusive)
        var hooksLineIndex: Int?
        var legacyCodexHooksLineIndex: Int?

        for (idx, scannedLine) in scannedLines.enumerated() {
            let line = scannedLine.statement
            if line.hasPrefix("[") {
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
