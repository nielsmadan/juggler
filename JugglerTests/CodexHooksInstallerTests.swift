import Foundation
@testable import Juggler
import Testing

// MARK: - Shared temp-file helpers

/// Creates a unique temp directory, runs `body`, and removes the directory afterward —
/// so tests never leak temp files. `body` receives the directory URL.
private func withTempDir(_ body: (URL) throws -> Void) rethrows {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

/// Creates a temp directory containing `config.toml` (written with `contents` when non-nil),
/// runs `body` with the file path, and removes the directory afterward.
private func withTempFile(contents: String? = nil, _ body: (String) throws -> Void) rethrows {
    try withTempDir { dir in
        let path = dir.appendingPathComponent("config.toml").path
        if let contents {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
        }
        try body(path)
    }
}

/// Sets up a realistic Codex fixture in a temp dir: a `hooks.json` with Juggler's hooks
/// registered (via `mergeHooksJSON`, exactly as `installHooks` would), plus a `config.toml`
/// path (written with `config` when non-nil). When `preexistingHooksJSON` is supplied, it is
/// written first so Juggler's entries are appended *after* the user's — exercising group
/// indices ≥ 1. `body` receives the config path, hooks.json path, and notify-script path.
private func withCodexFixture(
    config: String? = nil,
    preexistingHooksJSON: String? = nil,
    _ body: (_ configPath: String, _ hooksJSONPath: String, _ notifyPath: String) throws -> Void
) throws {
    try withTempDir { dir in
        let configPath = dir.appendingPathComponent("config.toml").path
        if let config {
            try config.write(toFile: configPath, atomically: true, encoding: .utf8)
        }
        let hooksJSONPath = dir.appendingPathComponent("hooks.json").path
        let notifyPath = dir.appendingPathComponent("hooks/juggler/notify.sh").path
        if let preexistingHooksJSON {
            try preexistingHooksJSON.write(toFile: hooksJSONPath, atomically: true, encoding: .utf8)
        }
        try CodexHooksInstaller.mergeHooksJSON(at: hooksJSONPath, notifyScriptPath: notifyPath)
        try body(configPath, hooksJSONPath, notifyPath)
    }
}

private func readFile(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

// MARK: - hooks.json merge

@Suite("CodexHooksInstaller — hooks.json merge")
struct CodexHooksJSONTests {
    private let notifyPath = "/Users/me/.codex/hooks/juggler/notify.sh"

    @Test func mergeHooksJSON_intoMissingFile_addsAllEvents() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)

            let obj = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: hooksJSON))
            ) as? [String: Any]
            let hooks = obj?["hooks"] as? [String: Any]
            for event in CodexHooksInstaller.agentEvents {
                #expect(hooks?[event] != nil, "missing event \(event)")
            }
            #expect((hooks?.count ?? 0) == CodexHooksInstaller.agentEvents.count)
        }
    }

    @Test func mergeHooksJSON_preservesNonJugglerHooksAndAppendsLast() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try """
            {"hooks": {"SessionStart": [{"hooks": [{"type":"command","command":"echo other"}]}]}}
            """.write(toFile: hooksJSON, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)

            let obj = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: hooksJSON))
            ) as? [String: Any]
            let sessionStart = (obj?["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
            #expect((sessionStart?.count ?? 0) == 2)
            // The user's hook stays at index 0; Juggler's is appended at index 1.
            #expect(handlerCommand(sessionStart?[0]) == "echo other")
            #expect(handlerCommand(sessionStart?[1]) == "\(notifyPath) SessionStart")
        }
    }

    /// Pulls the first handler's `command` out of a hooks.json matcher group.
    private func handlerCommand(_ group: [String: Any]?) -> String? {
        (group?["hooks"] as? [[String: Any]])?.first?["command"] as? String
    }

    @Test func mergeHooksJSON_deduplicatesPreviousJugglerEntries() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)
            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)

            let obj = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: hooksJSON))
            ) as? [String: Any]
            let sessionStart = (obj?["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
            #expect((sessionStart?.count ?? 0) == 1)
        }
    }

    // A stale Juggler entry whose event argument has drifted is still recognized
    // structurally (by notify.sh path in the command) and replaced, not duplicated.
    @Test func mergeHooksJSON_deduplicatesStructurallyDespiteDriftedArg() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try """
            {"hooks": {"SessionStart": [{"hooks": [{"type":"command",\
            "command":"\(notifyPath) SomethingOld"}]}]}}
            """.write(toFile: hooksJSON, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)

            let obj = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: hooksJSON))
            ) as? [String: Any]
            let sessionStart = (obj?["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
            #expect((sessionStart?.count ?? 0) == 1)
        }
    }

    @Test func mergeHooksJSON_throwsAndPreservesUnparseableExistingFile() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            let garbage = "{ this is not json"
            try garbage.write(toFile: hooksJSON, atomically: true, encoding: .utf8)

            #expect(throws: CodexHooksError.hooksJSONUnparseable(hooksJSON)) {
                try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)
            }
            // Original file untouched — no silent overwrite.
            #expect(readFile(hooksJSON) == garbage)
        }
    }

    @Test func mergeHooksJSON_backsUpPreexistingFileOnceOnly() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            let original = """
            {"hooks": {"SessionStart": [{"hooks": [{"type":"command","command":"echo other"}]}]}}
            """
            try original.write(toFile: hooksJSON, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)
            #expect(readFile(hooksJSON + ".juggler-backup") == original)

            // A second merge must NOT clobber the backup with the now-Juggler-modified file.
            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)
            #expect(readFile(hooksJSON + ".juggler-backup") == original)
        }
    }

    // The handler Juggler writes must match what `computeTrustedHash` folds into the hash —
    // `type: "command"` and `timeout: hookTimeoutSeconds`.
    @Test func mergeHooksJSON_writesExpectedHandlerStructure() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: notifyPath)

            let obj = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: hooksJSON))
            ) as? [String: Any]
            let group = (obj?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
            let handler = (group?.first?["hooks"] as? [[String: Any]])?.first
            #expect(handler?["type"] as? String == "command")
            #expect(handler?["command"] as? String == "\(notifyPath) Stop")
            #expect(handler?["timeout"] as? Int == CodexHooksInstaller.hookTimeoutSeconds)
        }
    }
}

// MARK: - config.toml feature flag

@Suite("CodexHooksInstaller — config.toml feature flag")
struct CodexConfigTOMLTests {
    @Test func missingFile_createsWithSectionAndFlag() throws {
        try withTempFile { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("[features]"))
            #expect(out.contains("hooks = true"))
        }
    }

    @Test func emptyFile_addsSectionAndFlag() throws {
        try withTempFile(contents: "") { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("[features]"))
            #expect(out.contains("hooks = true"))
        }
    }

    @Test func fileWithOtherSection_appendsFeaturesAtEnd() throws {
        try withTempFile(contents: """
        [profiles.default]
        model = "gpt-5"
        """) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("[profiles.default]"))
            #expect(out.contains("model = \"gpt-5\""))
            #expect(out.contains("[features]"))
            #expect(out.contains("hooks = true"))
        }
    }

    @Test func featuresSectionExists_appendsKeyInSection() throws {
        try withTempFile(contents: """
        [features]
        some_other_flag = true
        """) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("some_other_flag = true"))
            #expect(out.contains("hooks = true"))
        }
    }

    @Test func flagSetToFalse_flipsToTrue() throws {
        try withTempFile(contents: """
        [features]
        hooks = false
        """) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("hooks = true"))
            #expect(!out.contains("hooks = false"))
        }
    }

    @Test func flagAlreadyTrue_isIdempotent() throws {
        try withTempFile(contents: """
        [features]
        hooks = true
        """) { path in
            let before = readFile(path)
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(readFile(path) == before)
        }
    }

    // Deprecated `codex_hooks` is migrated to the current `hooks` key.
    @Test func deprecatedKey_isMigratedToHooks() throws {
        try withTempFile(contents: """
        [features]
        codex_hooks = true
        """) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("hooks = true"))
            #expect(!out.contains("codex_hooks"))
        }
    }

    // When both keys exist, `codex_hooks` is dropped and `hooks` is kept.
    @Test func deprecatedKeyAlongsideHooks_dropsDeprecated() throws {
        try withTempFile(contents: """
        [features]
        codex_hooks = true
        hooks = true
        other = true
        """) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.contains("hooks = true"))
            #expect(out.contains("other = true"))
            #expect(!out.contains("codex_hooks"))
        }
    }

    // A trailing `# comment` on the flag line is recognized — no duplicate key inserted.
    // The comment is dropped as part of idempotent normalization.
    @Test func commentedFlagLine_isRecognizedAndNotDuplicated() throws {
        try withTempFile(contents: "[features]\nhooks = true # already on\n") { path in
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == true)
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.components(separatedBy: "hooks = true").count == 2) // exactly one occurrence
            #expect(!out.contains("already on")) // comment dropped on normalization
        }
    }

    @Test func isFeatureFlagEnabled_reflectsState() throws {
        try withTempFile(contents: "[features]\nhooks = false\n") { path in
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == false)
        }
        try withTempFile(contents: "[features]\nhooks = true\n") { path in
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == true)
        }
        try withTempFile(contents: "[features]\ncodex_hooks = true\n") { path in
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == true)
        }
        try withTempFile(contents: "") { path in
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == false)
        }
    }

    // Fix 9: a no-op call (file already correct) must not drop a `.juggler-backup`.
    @Test func enableFeatureFlag_noOpDoesNotCreateBackup() throws {
        try withTempFile(contents: "[features]\nhooks = true\n") { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(!FileManager.default.fileExists(atPath: path + ".juggler-backup"))
        }
    }

    // Fix 9: a real modification backs up the pre-existing file with its original content.
    @Test func enableFeatureFlag_modificationBacksUpOriginal() throws {
        let original = "[features]\nhooks = false\n"
        try withTempFile(contents: original) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(readFile(path + ".juggler-backup") == original)
        }
    }

    // `joinPreservingTrailingNewline` (private) is exercised through `enableFeatureFlag`:
    // a trailing newline is preserved when present and not added when absent.
    @Test func enableFeatureFlag_preservesTrailingNewlinePresence() throws {
        try withTempFile(contents: "[features]\nhooks = false\n") { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(readFile(path).hasSuffix("\n"))
        }
        try withTempFile(contents: "[features]\nhooks = false") { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(!readFile(path).hasSuffix("\n"))
        }
    }
}

// MARK: - trust hashes

@Suite("CodexHooksInstaller — trust hashes")
struct CodexTrustHashTests {
    private let notify = "/Users/nielsmadan/.codex/hooks/juggler/notify.sh"

    // Vectors captured from a real Codex 0.130.0 config.toml after the user trusted
    // the hooks via /hooks. Reproducing these proves our hash matches Codex's — and
    // pins the `hookTimeoutSeconds` value the hash folds in.
    @Test func computeTrustedHash_matchesKnownVectors() {
        let vectors: [(event: String, hash: String)] = [
            ("SessionStart", "sha256:69df9d8472ca7e042284549900dd402e90f4288ca8dba3cd942d157b58974ae4"),
            ("UserPromptSubmit", "sha256:c641f6a7879d9e3a7b22246294f183f51b1f97b38c59ea2ede4107418ebc1ca8"),
            ("PreToolUse", "sha256:4d6bf9b67886d30fb217a2aaa308595ede23120d19e24d60ccffc25557b99353"),
            ("PostToolUse", "sha256:1d6920b973f1588a5661f3bcd65ceab21ac45d44916068af8e6ab0d8a1dbf84b"),
            ("PermissionRequest", "sha256:06ab5162f48890ad940cc32c42cc91a16704d8150ceeefec166bd4114bd17c8b"),
            ("Stop", "sha256:5d85c4575b9b7606183bfc238b05451bc88a23d7ab720101367bbb00d9d93201")
        ]
        for vector in vectors {
            let hash = CodexHooksInstaller.computeTrustedHash(
                event: vector.event,
                command: "\(notify) \(vector.event)"
            )
            #expect(hash == vector.hash, "hash mismatch for \(vector.event)")
        }
    }

    @Test func computeTrustedHash_isDeterministicAndWellFormed() {
        let first = CodexHooksInstaller.computeTrustedHash(
            event: "PreCompact", command: "\(notify) PreCompact"
        )
        let second = CodexHooksInstaller.computeTrustedHash(
            event: "PreCompact", command: "\(notify) PreCompact"
        )
        #expect(first == second)
        #expect(first.hasPrefix("sha256:"))
        #expect(first.count == "sha256:".count + 64)
    }
}

// MARK: - enable in Codex

@Suite("CodexHooksInstaller — enable in Codex")
struct CodexEnableInCodexTests {
    @Test func enableInCodex_thenIsEnabled_roundTrips() throws {
        try withCodexFixture { config, hooksJSON, notify in
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == false)
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == true)
        }
    }

    @Test func enableInCodex_isIdempotent() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            let first = readFile(config)
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(readFile(config) == first)
        }
    }

    @Test func enableInCodex_preservesOtherContent() throws {
        let config = """
        model = "gpt-5"

        [features]
        hooks = true

        [hooks.state."/some/other/hooks.json:stop:0:0"]
        trusted_hash = "sha256:deadbeef"
        """
        try withCodexFixture(config: config) { configPath, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: configPath, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            let out = readFile(configPath)
            #expect(out.contains("model = \"gpt-5\""))
            #expect(out.contains("[features]"))
            #expect(out.contains("[hooks.state.\"/some/other/hooks.json:stop:0:0\"]"))
            #expect(out.contains("sha256:deadbeef"))
            // No pre-existing user hooks → Juggler's groups are at index 0.
            #expect(out.contains("\(hooksJSON):session_start:0:0"))
            #expect(out.contains("\(hooksJSON):post_compact:0:0"))
        }
    }

    // Fix 1, the core bug: when the user already has a hook for an event, Juggler's hook
    // is appended at group index ≥ 1 and the trust key must reflect that real index.
    @Test func enableInCodex_userHasPreexistingHook_usesRealGroupIndex() throws {
        let preexisting = """
        {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user-hook"}]}]}}
        """
        try withCodexFixture(preexistingHooksJSON: preexisting) { config, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            let out = readFile(config)
            #expect(out.contains("\(hooksJSON):session_start:1:0"))
            #expect(!out.contains("\(hooksJSON):session_start:0:0"))
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == true)
        }
    }

    // Critical #1 regression: when the user has their own hook for one of Juggler's events
    // in the same hooks.json, Codex stores the user's trust block under `<path>:<event>:0:0`.
    // That block is the USER's, not Juggler's — it must survive `enableInCodex` untouched.
    // Juggler's own block is written at its real (appended) group index.
    @Test func enableInCodex_preservesUserOwnedTrustBlockAtIndexZero() throws {
        let preexisting = """
        {"hooks":{\
        "SessionStart":[{"hooks":[{"type":"command","command":"echo user-ss"}]}],\
        "Stop":[{"hooks":[{"type":"command","command":"echo user-stop"}]}]}}
        """
        try withCodexFixture(preexistingHooksJSON: preexisting) { config, hooksJSON, notify in
            // Seed user-owned trust blocks at index 0 (the user's hooks sit at group 0).
            try """
            [hooks.state."\(hooksJSON):session_start:0:0"]
            trusted_hash = "sha256:USERHASH_SS"

            [hooks.state."\(hooksJSON):stop:0:0"]
            trusted_hash = "sha256:USERHASH_STOP"
            """.write(toFile: config, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            var out = readFile(config)
            // The user's own blocks survive, hash values intact.
            #expect(out.contains("\(hooksJSON):session_start:0:0"))
            #expect(out.contains("sha256:USERHASH_SS"))
            #expect(out.contains("\(hooksJSON):stop:0:0"))
            #expect(out.contains("sha256:USERHASH_STOP"))
            // Juggler's own blocks are written at the real appended index (1).
            #expect(out.contains("\(hooksJSON):session_start:1:0"))
            #expect(out.contains("\(hooksJSON):stop:1:0"))

            // Idempotent: a second run still preserves the user's blocks.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            out = readFile(config)
            #expect(out.contains("sha256:USERHASH_SS"))
            #expect(out.contains("sha256:USERHASH_STOP"))
        }
    }

    @Test func enableInCodex_throwsWhenHooksJSONMissing() throws {
        try withTempDir { dir in
            let config = dir.appendingPathComponent("config.toml").path
            let missing = dir.appendingPathComponent("hooks.json").path
            #expect(throws: CodexHooksError.hooksJSONNotFound(missing)) {
                try CodexHooksInstaller.enableInCodex(
                    at: config, hooksJSONPath: missing, notifyScriptPath: "/x/notify.sh"
                )
            }
        }
    }

    @Test func enableInCodex_throwsWhenHooksJSONUnparseable() throws {
        try withTempDir { dir in
            let config = dir.appendingPathComponent("config.toml").path
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try "{ not json".write(toFile: hooksJSON, atomically: true, encoding: .utf8)
            #expect(throws: CodexHooksError.hooksJSONUnparseable(hooksJSON)) {
                try CodexHooksInstaller.enableInCodex(
                    at: config, hooksJSONPath: hooksJSON, notifyScriptPath: "/x/notify.sh"
                )
            }
        }
    }

    @Test func enableInCodex_throwsWhenNoJugglerHooksRegistered() throws {
        try withTempDir { dir in
            let config = dir.appendingPathComponent("config.toml").path
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            // Valid JSON, but contains only a non-Juggler hook.
            try """
            {"hooks": {"SessionStart": [{"hooks": [{"type":"command","command":"echo user"}]}]}}
            """.write(toFile: hooksJSON, atomically: true, encoding: .utf8)
            #expect(throws: CodexHooksError.jugglerHooksNotRegistered(hooksJSON)) {
                try CodexHooksInstaller.enableInCodex(
                    at: config, hooksJSONPath: hooksJSON, notifyScriptPath: "/x/notify.sh"
                )
            }
        }
    }

    @Test func enableInCodex_modificationBacksUpOriginalOnceOnly() throws {
        let original = "[features]\nhooks = true\n"
        try withCodexFixture(config: original) { config, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(readFile(config + ".juggler-backup") == original)
            // A second (no-op) run must not overwrite the backup.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(readFile(config + ".juggler-backup") == original)
        }
    }

    @Test func enableInCodex_noBackupWhenConfigCreatedFromScratch() throws {
        try withCodexFixture { config, hooksJSON, notify in
            // config.toml didn't pre-exist → Juggler creates it, no backup.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(!FileManager.default.fileExists(atPath: config + ".juggler-backup"))
            // A second (no-op) run still makes no backup.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(!FileManager.default.fileExists(atPath: config + ".juggler-backup"))
        }
    }

    // enableInCodex writes trust blocks only for events that actually have a Juggler hook
    // registered — it does not invent keys for unregistered events.
    @Test func enableInCodex_partialRegistration_writesOnlyRegisteredEvents() throws {
        try withTempDir { dir in
            let config = dir.appendingPathComponent("config.toml").path
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            let notify = "/x/notify.sh"
            // Only SessionStart has a Juggler hook registered.
            try """
            {"hooks": {"SessionStart": [{"hooks": [\
            {"type":"command","command":"\(notify) SessionStart","timeout":5}]}]}}
            """.write(toFile: hooksJSON, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            let out = readFile(config)
            #expect(out.contains("\(hooksJSON):session_start:0:0"))
            #expect(!out.contains(":stop:"))
            #expect(!out.contains(":pre_tool_use:"))
        }
    }

    // A genuine orphan (a Juggler key at a group index that no longer exists) is harmless and
    // is deliberately left untouched — exact-key matching never prefix-matches. This pins the
    // Critical-#1 design decision so it isn't "fixed" by reintroducing prefix cleanup.
    @Test func enableInCodex_leavesGenuineOrphanUntouched() throws {
        try withCodexFixture { config, hooksJSON, notify in
            // No user hook → Juggler resolves to index 0. Seed a stale `:1:0` orphan.
            try """
            [hooks.state."\(hooksJSON):session_start:1:0"]
            trusted_hash = "sha256:ORPHAN"
            """.write(toFile: config, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            let out = readFile(config)
            #expect(out.contains("\(hooksJSON):session_start:0:0")) // Juggler's real key
            #expect(out.contains("\(hooksJSON):session_start:1:0")) // orphan left intact
            #expect(out.contains("sha256:ORPHAN"))
        }
    }

    @Test func isEnabledInCodex_falsePaths() throws {
        try withTempDir { dir in
            let hooksJSON = dir.appendingPathComponent("hooks.json").path
            try CodexHooksInstaller.mergeHooksJSON(at: hooksJSON, notifyScriptPath: "/x/notify.sh")
            let config = dir.appendingPathComponent("config.toml").path

            // Missing config.toml.
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: "/x/notify.sh"
            ) == false)

            // config.toml exists but has no trust blocks.
            try "[features]\nhooks = true\n".write(toFile: config, atomically: true, encoding: .utf8)
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: "/x/notify.sh"
            ) == false)

            // Missing hooks.json.
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config,
                hooksJSONPath: dir.appendingPathComponent("missing.json").path,
                notifyScriptPath: "/x/notify.sh"
            ) == false)

            // Unparseable hooks.json.
            let bad = dir.appendingPathComponent("bad.json").path
            try "{ not json".write(toFile: bad, atomically: true, encoding: .utf8)
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: bad, notifyScriptPath: "/x/notify.sh"
            ) == false)
        }
    }

    // isEnabledInCodex must never go falsely-green: if an event isn't registered, return false.
    @Test func isEnabledInCodex_falseWhenAnEventNotRegistered() throws {
        try withCodexFixture { config, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == true)

            // Drop one event from hooks.json.
            var root = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: hooksJSON))
            ) as! [String: Any]
            var hooks = root["hooks"] as! [String: Any]
            hooks["Stop"] = nil
            root["hooks"] = hooks
            try JSONSerialization.data(withJSONObject: root)
                .write(to: URL(fileURLWithPath: hooksJSON))

            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == false)
        }
    }

    @Test func isEnabledInCodex_falseWhenStoredHashIsWrong() throws {
        try withCodexFixture { config, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            // Replace the first stored hash with a well-formed but wrong digest.
            var lines = readFile(config).components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { $0.hasPrefix("trusted_hash = ") }) {
                lines[i] = "trusted_hash = \"sha256:\(String(repeating: "0", count: 64))\""
            }
            try lines.joined(separator: "\n").write(toFile: config, atomically: true, encoding: .utf8)

            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == false)
        }
    }

    // Fix 4: a trailing `# comment` on a `trusted_hash` line is tolerated by the parser.
    @Test func isEnabledInCodex_toleratesTrailingCommentOnTrustedHash() throws {
        try withCodexFixture { config, hooksJSON, notify in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            )
            let commented = readFile(config)
                .components(separatedBy: "\n")
                .map { $0.hasPrefix("trusted_hash = ") ? $0 + " # codex note" : $0 }
                .joined(separator: "\n")
            try commented.write(toFile: config, atomically: true, encoding: .utf8)

            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, notifyScriptPath: notify
            ) == true)
        }
    }
}

// MARK: - install hooks

@Suite("CodexHooksInstaller — install hooks")
struct CodexInstallHooksTests {
    @Test func installHooks_placesScriptAndMergesHooksJSON() throws {
        try withTempDir { dir in
            let bundledScript = dir.appendingPathComponent("codex-notify.sh")
            try "#!/bin/bash\necho hi\n".write(to: bundledScript, atomically: true, encoding: .utf8)
            let hooksDir = dir.appendingPathComponent("hooks/juggler").path
            let notifyPath = hooksDir + "/notify.sh"
            let hooksJSONPath = dir.appendingPathComponent("hooks.json").path

            let error = CodexHooksInstaller.installHooks(
                bundledScriptURL: bundledScript,
                hooksDirectory: hooksDir,
                notifyScriptPath: notifyPath,
                hooksJSONPath: hooksJSONPath
            )
            #expect(error == nil)
            #expect(FileManager.default.fileExists(atPath: notifyPath))
            #expect(FileManager.default.fileExists(atPath: hooksJSONPath))
        }
    }

    @Test func installHooks_returnsErrorWhenBundledScriptMissing() {
        // Returns early before touching the filesystem.
        #expect(CodexHooksInstaller.installHooks(bundledScriptURL: nil) != nil)
    }

    @Test func installHooks_setsExecutablePermissionOnScript() throws {
        try withTempDir { dir in
            let bundledScript = dir.appendingPathComponent("codex-notify.sh")
            try "#!/bin/bash\necho hi\n".write(to: bundledScript, atomically: true, encoding: .utf8)
            let hooksDir = dir.appendingPathComponent("hooks/juggler").path
            let notifyPath = hooksDir + "/notify.sh"
            let hooksJSONPath = dir.appendingPathComponent("hooks.json").path

            _ = CodexHooksInstaller.installHooks(
                bundledScriptURL: bundledScript,
                hooksDirectory: hooksDir,
                notifyScriptPath: notifyPath,
                hooksJSONPath: hooksJSONPath
            )
            let perms = try FileManager.default.attributesOfItem(atPath: notifyPath)[.posixPermissions]
            #expect((perms as? NSNumber)?.intValue == 0o755)
        }
    }

    @Test func installHooks_reinstallOverwritesStaleScript() throws {
        try withTempDir { dir in
            let hooksDir = dir.appendingPathComponent("hooks/juggler").path
            try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
            let notifyPath = hooksDir + "/notify.sh"
            try "STALE".write(toFile: notifyPath, atomically: true, encoding: .utf8)

            let bundledScript = dir.appendingPathComponent("codex-notify.sh")
            try "FRESH".write(to: bundledScript, atomically: true, encoding: .utf8)
            let hooksJSONPath = dir.appendingPathComponent("hooks.json").path

            let error = CodexHooksInstaller.installHooks(
                bundledScriptURL: bundledScript,
                hooksDirectory: hooksDir,
                notifyScriptPath: notifyPath,
                hooksJSONPath: hooksJSONPath
            )
            #expect(error == nil)
            #expect(readFile(notifyPath) == "FRESH")
        }
    }
}

// MARK: - CodexHooksError

@Suite("CodexHooksError")
struct CodexHooksErrorTests {
    // The error messages surface verbatim to the user via CodexSetupController.errorMessage.
    @Test func errorDescriptionsAreActionableAndIncludeThePath() {
        let notFound = CodexHooksError.hooksJSONNotFound("/p/hooks.json").errorDescription
        #expect(notFound?.contains("/p/hooks.json") == true)
        #expect(notFound?.contains("Install Hooks") == true)

        let unparseable = CodexHooksError.hooksJSONUnparseable("/p/hooks.json").errorDescription
        #expect(unparseable?.contains("/p/hooks.json") == true)
        #expect(unparseable?.contains("valid JSON") == true)

        let notRegistered = CodexHooksError.jugglerHooksNotRegistered("/p/hooks.json").errorDescription
        #expect(notRegistered?.contains("Install Hooks") == true)
    }
}
