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

/// The `(event, groupIndex, command)` triples `hooks status --agent codex --json` reports,
/// using the canonical command hooklinesinker installs. `groupIndex` is the index of our
/// matcher group within that event's array — 1 when the user already hooks the same event.
private func codexEntries(
    events: [String] = CodexHooksInstaller.agentEvents,
    groupIndex: Int = 0,
    binary: String = "/Users/me/.local/share/hooklinesinker/bin/hooklinesinker"
) -> [HooklinesinkerHookEntry] {
    events.map {
        HooklinesinkerHookEntry(
            event: $0,
            groupIndex: groupIndex,
            command: "\(binary) ingest --agent codex --event \($0)"
        )
    }
}

/// Sets up a Codex fixture in a temp dir: a `config.toml` path (written with `config` when
/// non-nil), the `hooks.json` path the CLI would report, and the entries it would report for
/// it. `body` receives the config path, hooks.json path, and those entries.
private func withCodexFixture(
    config: String? = nil,
    entries: [HooklinesinkerHookEntry]? = nil,
    _ body: (
        _ configPath: String,
        _ hooksJSONPath: String,
        _ entries: [HooklinesinkerHookEntry]
    ) throws -> Void
) throws {
    try withTempDir { dir in
        let configPath = dir.appendingPathComponent("config.toml").path
        if let config {
            try config.write(toFile: configPath, atomically: true, encoding: .utf8)
        }
        let hooksJSONPath = dir.appendingPathComponent("hooks.json").path
        try body(configPath, hooksJSONPath, entries ?? codexEntries())
    }
}

private func readFile(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
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

    // The comment is dropped as part of idempotent normalization.
    @Test func commentedFlagLine_isRecognizedAndNotDuplicated() throws {
        try withTempFile(contents: "[features]\nhooks = true # already on\n") { path in
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == true)
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            let out = readFile(path)
            #expect(out.components(separatedBy: "hooks = true").count == 2) // exactly one occurrence
            #expect(!out.contains("already on"))
        }
    }

    @Test func featureFlagEditPreservesMultilineExamplesAndCommentedTables() throws {
        let prefix = "instructions = '''\napprovals_reviewer = \"auto_review\"\n[features]\nhooks = true\n'''\n\n"
        let original = prefix + "[features] # user annotation\nhooks = false\n"
            + "[profiles.review] # personal settings\nmodel = \"keep\"\n"
        let expected = prefix + "[features] # user annotation\nhooks = true\n"
            + "[profiles.review] # personal settings\nmodel = \"keep\"\n"
        try withTempFile(contents: original) { path in
            #expect(CodexHooksInstaller.isAutoReviewEnabled(at: path) == false)
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == false)
            for _ in 0 ..< 2 {
                try CodexHooksInstaller.enableFeatureFlag(at: path)
                #expect(readFile(path) == expected)
                #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path))
            }
            #expect(readFile(path + ".juggler-backup") == original)
        }
    }

    @Test func featureFlagEditRejectsUnterminatedValuesWithoutWriting() throws {
        let original = "[features]\nhooks = false\n[profiles.review]\ninstructions = '''unfinished\n"
        try withTempFile(contents: original) { path in
            #expect(throws: CodexHooksError.configUnsupported) {
                try CodexHooksInstaller.enableFeatureFlag(at: path)
            }
            #expect(readFile(path) == original)
            #expect(CodexHooksInstaller.isFeatureFlagEnabled(at: path) == false)
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

    @Test func isAutoReviewEnabled_readsTopLevelReviewer() throws {
        try withTempFile(contents: "approvals_reviewer = \"auto_review\" # enabled\n") { path in
            #expect(CodexHooksInstaller.isAutoReviewEnabled(at: path))
        }
        try withTempFile(contents: "approvals_reviewer = 'auto_review'\n") { path in
            #expect(CodexHooksInstaller.isAutoReviewEnabled(at: path))
        }
        try withTempFile(contents: "approvals_reviewer = \"user\"\n") { path in
            #expect(!CodexHooksInstaller.isAutoReviewEnabled(at: path))
        }
    }

    @Test func isAutoReviewEnabled_ignoresProfileReviewer() throws {
        try withTempFile(contents: """
        [profiles.automatic]
        approvals_reviewer = "auto_review"
        """) { path in
            #expect(!CodexHooksInstaller.isAutoReviewEnabled(at: path))
        }
        try withTempFile(contents: """
        [profiles.automatic] # selected with --profile automatic
        approvals_reviewer = "auto_review"
        """) { path in
            #expect(!CodexHooksInstaller.isAutoReviewEnabled(at: path))
        }
    }

    @Test func enableFeatureFlag_noOpDoesNotCreateBackup() throws {
        try withTempFile(contents: "[features]\nhooks = true\n") { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(!FileManager.default.fileExists(atPath: path + ".juggler-backup"))
        }
    }

    @Test func enableFeatureFlag_modificationBacksUpOriginal() throws {
        let original = "[features]\nhooks = false\n"
        try withTempFile(contents: original) { path in
            try CodexHooksInstaller.enableFeatureFlag(at: path)
            #expect(readFile(path + ".juggler-backup") == original)
        }
    }

    // Exercises the private `joinPreservingTrailingNewline` through `enableFeatureFlag`.
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

@Suite("CodexSetupController — permission event preference")
struct CodexSetupControllerTests {
    @Test @MainActor func autoReviewDetected_defaultsPreferenceOn() throws {
        let suiteName = "CodexSetupControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try withTempFile(contents: "approvals_reviewer = \"auto_review\"\n") { path in
            let controller = CodexSetupController()
            controller.initializePermissionEventPreference(defaults: defaults, configTOMLPath: path)
            #expect(defaults.bool(forKey: AppStorageKeys.codexIgnorePermissionEvents))
        }
    }

    @Test @MainActor func explicitPreference_isPreserved() throws {
        let suiteName = "CodexSetupControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: AppStorageKeys.codexIgnorePermissionEvents)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try withTempFile(contents: "approvals_reviewer = \"auto_review\"\n") { path in
            let controller = CodexSetupController()
            controller.initializePermissionEventPreference(defaults: defaults, configTOMLPath: path)
            #expect(defaults.object(forKey: AppStorageKeys.codexIgnorePermissionEvents) as? Bool == false)
        }
    }
}

// MARK: - trust hashes

@Suite("CodexHooksInstaller — trust hashes")
struct CodexTrustHashTests {
    private let notify = "/Users/nielsmadan/.codex/hooks/juggler/notify.sh"

    // Vectors captured from a real Codex 0.130.0 config.toml after the user trusted
    // the hooks via /hooks. Reproducing these proves our hash matches Codex's — and
    // pins the default timeout the hash folds in.
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
        try withCodexFixture { config, hooksJSON, entries in
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == true)
        }
    }

    // The hash must be built from the command the CLI reports, not one Juggler reconstructs:
    // a change to hooklinesinker's command line would otherwise silently produce hashes Codex
    // rejects.
    @Test func trustHashesUseTheCommandTheCLIReported() throws {
        let entries = codexEntries(binary: "/opt/custom/hooklinesinker")
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let out = readFile(config)
            for entry in entries {
                let expected = CodexHooksInstaller.computeTrustedHash(
                    event: entry.event, command: entry.command
                )
                #expect(out.contains(expected), "missing hash for \(entry.event)")
            }
            // A hash built from the old notify.sh command would not appear.
            let legacy = CodexHooksInstaller.computeTrustedHash(
                event: "Stop", command: "/Users/me/.codex/hooks/juggler/notify.sh Stop"
            )
            #expect(!out.contains(legacy))
        }
    }

    // The state that motivated this check: the user enabled the feature flag but chose Codex's
    // own /hooks review over Juggler's button, so no Juggler trust entry exists to refresh.
    @Test func hasExistingTrustEntries_featureFlagOnButNeverTrusted_false() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, entries in
            #expect(CodexHooksInstaller.hasExistingTrustEntries(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
        }
    }

    @Test func hasExistingTrustEntries_afterEnableInCodex_true() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(CodexHooksInstaller.hasExistingTrustEntries(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ))
        }
    }

    @Test func allEntriesTrusted_afterEnableInCodex_true() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(CodexHooksInstaller.allEntriesTrusted(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ))
        }
    }

    @Test func allEntriesTrusted_neverTrusted_false() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, entries in
            #expect(CodexHooksInstaller.allEntriesTrusted(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
        }
    }

    // A foreign hook appearing on one event shifts our group index there: that entry is now
    // untrusted (its key moved) while the rest still resolve. `allEntriesTrusted` must catch
    // this exact partial-trust state that `hasExistingTrustEntries` cannot.
    @Test func allEntriesTrusted_whenOneEntryIndexShifted_false() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let shifted = entries.map { entry in
                entry.event == "SessionEnd"
                    ? HooklinesinkerHookEntry(event: entry.event, groupIndex: 1, command: entry.command)
                    : entry
            }
            #expect(CodexHooksInstaller.allEntriesTrusted(
                at: config, hooksJSONPath: hooksJSON, entries: shifted
            ) == false)
            #expect(CodexHooksInstaller.hasExistingTrustEntries(
                at: config, hooksJSONPath: hooksJSON, entries: shifted
            ))
        }
    }

    // A user's own hook trusted in the same hooks.json is not Juggler's consent.
    @Test func hasExistingTrustEntries_foreignTrustEntryOnly_false() throws {
        let foreign = """
        [features]
        hooks = true

        [hooks.state."/some/other/hooks.json:session_start:0:0"]
        trusted_hash = "sha256:deadbeef"
        """
        try withCodexFixture(config: foreign) { config, hooksJSON, entries in
            #expect(CodexHooksInstaller.hasExistingTrustEntries(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
        }
    }

    @Test func hasExistingTrustEntries_missingConfig_false() throws {
        try withCodexFixture { _, hooksJSON, entries in
            #expect(CodexHooksInstaller.hasExistingTrustEntries(
                at: "/nonexistent/config.toml", hooksJSONPath: hooksJSON, entries: entries
            ) == false)
        }
    }

    @Test func enableInCodex_isIdempotent() throws {
        try withCodexFixture(config: "[features]\nhooks = true\n") { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let first = readFile(config)
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
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
        try withCodexFixture(config: config) { configPath, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: configPath, hooksJSONPath: hooksJSON, entries: entries
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

    @Test func enableInCodex_preservesCommentedTablesAfterOwnedTrust() throws {
        let entries = codexEntries(events: ["Stop"])
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            let header = "[hooks.state.\"\(hooksJSON):stop:0:0\"]"
            let retained = """
            [mcp_servers."review# ]"] # user annotation
            command = "keep-server"
            arguments = [
                ["one", "two"], # nested array
            ]

            [[projects]] # personal projects
            name = "keep-project"
            """
            let original = "\(header) # previous trust\ntrusted_hash = \"sha256:OLD\"\n\n" + retained
            try original.write(toFile: config, atomically: true, encoding: .utf8)
            let hash = CodexHooksInstaller.computeTrustedHash(event: "Stop", command: entries[0].command)
            let expected = retained + "\n\n\(header)\ntrusted_hash = \"\(hash)\"\n"

            for _ in 0 ..< 2 {
                try CodexHooksInstaller.enableInCodex(at: config, hooksJSONPath: hooksJSON, entries: entries)
                #expect(readFile(config) == expected)
            }
            #expect(readFile(config + ".juggler-backup") == original)
        }
    }

    @Test(arguments: ["\"\"\"", "'''", "\"\"\"\"", "'''''"])
    func enableInCodex_preservesTrustHeadersInsideMultilineValues(delimiter: String) throws {
        let entries = codexEntries(events: ["Stop"])
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            let header = "[hooks.state.\"\(hooksJSON):stop:0:0\"]"
            let prefix = "instructions = \(delimiter)\n\(header)\ntrusted_hash = \"example\"\n\(delimiter)\n\n"
            let suffix = "[features] # user annotation\nhooks = true"
            let original = prefix + "\(header)\ntrusted_hash = \"sha256:OLD\"\n\n" + suffix
            try original.write(toFile: config, atomically: true, encoding: .utf8)
            let hash = CodexHooksInstaller.computeTrustedHash(event: "Stop", command: entries[0].command)

            try CodexHooksInstaller.enableInCodex(at: config, hooksJSONPath: hooksJSON, entries: entries)

            #expect(readFile(config) == prefix + suffix + "\n\n\(header)\ntrusted_hash = \"\(hash)\"\n")
        }
    }

    @Test(arguments: ["\"\"\"unfinished", "\"unfinished", "[1, 2", "{name = \"unfinished\"", "\"\"\"bad\"\"\"\"\"\""])
    func enableInCodex_rejectsUncertainTableBoundariesWithoutWriting(value: String) throws {
        try withCodexFixture { config, hooksJSON, entries in
            let original = """
            [hooks.state."\(hooksJSON):stop:0:0"]
            trusted_hash = "sha256:OLD"
            [profiles.review]
            setting = \(value)
            """
            try original.write(toFile: config, atomically: true, encoding: .utf8)
            try "recovery".write(toFile: config + ".juggler-backup", atomically: true, encoding: .utf8)

            #expect(throws: CodexHooksError.configUnsupported) {
                try CodexHooksInstaller.enableInCodex(at: config, hooksJSONPath: hooksJSON, entries: entries)
            }
            #expect(readFile(config) == original)
            #expect(readFile(config + ".juggler-backup") == "recovery")
        }
    }

    @Test func multilineTrustExampleDoesNotAuthorizeTrustRefresh() throws {
        let entries = codexEntries(events: ["Stop"])
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            let hash = CodexHooksInstaller.computeTrustedHash(event: "Stop", command: entries[0].command)
            let original = "instructions = '''\n[hooks.state.\"\(hooksJSON):stop:0:0\"]\n"
                + "trusted_hash = \"\(hash)\"\n'''\n"
            try original.write(toFile: config, atomically: true, encoding: .utf8)

            #expect(CodexHooksInstaller.hasExistingTrustEntries(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
            #expect(CodexHooksInstaller.allEntriesTrusted(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
        }
    }

    // The core bug this guards: when the user already has a hook for an event, ours is
    // appended at group index ≥ 1 and the trust key must reflect that real index — which is
    // now the index the CLI reports rather than one Juggler re-derives.
    @Test func enableInCodex_userHasPreexistingHook_usesRealGroupIndex() throws {
        let entries = codexEntries(groupIndex: 1)
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let out = readFile(config)
            #expect(out.contains("\(hooksJSON):session_start:1:0"))
            #expect(!out.contains("\(hooksJSON):session_start:0:0"))
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == true)
        }
    }

    // When the user has their own hook for one of our events in the same hooks.json, Codex
    // stores the user's trust block under `<path>:<event>:0:0`. That block is the USER's, not
    // Juggler's — it must survive `enableInCodex` untouched.
    @Test func enableInCodex_preservesUserOwnedTrustBlockAtIndexZero() throws {
        let entries = codexEntries(groupIndex: 1)
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            // Seed user-owned trust blocks at index 0 (the user's hooks sit at group 0).
            try """
            [hooks.state."\(hooksJSON):session_start:0:0"]
            trusted_hash = "sha256:USERHASH_SS"

            [hooks.state."\(hooksJSON):stop:0:0"]
            trusted_hash = "sha256:USERHASH_STOP"
            """.write(toFile: config, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
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
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            out = readFile(config)
            #expect(out.contains("sha256:USERHASH_SS"))
            #expect(out.contains("sha256:USERHASH_STOP"))
        }
    }

    // `hooks status` reports no entries when nothing of ours is registered — there is no hook
    // to trust, and writing a key for one would be a lie.
    @Test func enableInCodex_throwsWhenNothingIsRegistered() throws {
        try withCodexFixture(entries: []) { config, hooksJSON, entries in
            #expect(throws: CodexHooksError.hooksNotRegistered(hooksJSON)) {
                try CodexHooksInstaller.enableInCodex(
                    at: config, hooksJSONPath: hooksJSON, entries: entries
                )
            }
        }
    }

    @Test func enableInCodex_modificationBacksUpOriginalOnceOnly() throws {
        let original = "[features]\nhooks = true\n"
        try withCodexFixture(config: original) { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(readFile(config + ".juggler-backup") == original)
            // A second (no-op) run must not overwrite the backup.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(readFile(config + ".juggler-backup") == original)
        }
    }

    @Test func enableInCodex_noBackupWhenConfigCreatedFromScratch() throws {
        try withCodexFixture { config, hooksJSON, entries in
            // config.toml didn't pre-exist → Juggler creates it, no backup.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(!FileManager.default.fileExists(atPath: config + ".juggler-backup"))
            // A second (no-op) run still makes no backup.
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(!FileManager.default.fileExists(atPath: config + ".juggler-backup"))
        }
    }

    @Test func enableInCodex_partialRegistration_writesOnlyRegisteredEvents() throws {
        let entries = codexEntries(events: ["SessionStart"])
        try withCodexFixture(entries: entries) { config, hooksJSON, _ in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let out = readFile(config)
            #expect(out.contains("\(hooksJSON):session_start:0:0"))
            #expect(!out.contains(":stop:"))
            #expect(!out.contains(":pre_tool_use:"))
        }
    }

    // A genuine orphan (a Juggler key at a group index that no longer exists) is harmless and
    // is deliberately left untouched — exact-key matching never prefix-matches. This pins the
    // design decision so it isn't "fixed" by reintroducing prefix cleanup.
    @Test func enableInCodex_leavesGenuineOrphanUntouched() throws {
        try withCodexFixture { config, hooksJSON, entries in
            // Entries resolve to index 0. Seed a stale `:1:0` orphan.
            try """
            [hooks.state."\(hooksJSON):session_start:1:0"]
            trusted_hash = "sha256:ORPHAN"
            """.write(toFile: config, atomically: true, encoding: .utf8)

            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let out = readFile(config)
            #expect(out.contains("\(hooksJSON):session_start:0:0")) // Juggler's real key
            #expect(out.contains("\(hooksJSON):session_start:1:0")) // orphan left intact
            #expect(out.contains("sha256:ORPHAN"))
        }
    }

    @Test func isEnabledInCodex_falsePaths() throws {
        try withCodexFixture { config, hooksJSON, entries in
            // Missing config.toml.
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)

            // config.toml exists but has no trust blocks.
            try "[features]\nhooks = true\n".write(toFile: config, atomically: true, encoding: .utf8)
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)

            // The CLI reported nothing registered.
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: []
            ) == false)
        }
    }

    @Test func isEnabledInCodex_falseWhenAnEventNotRegistered() throws {
        try withCodexFixture { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == true)

            // The CLI now reports one fewer registered event.
            let short = entries.filter { $0.event != "Stop" }
            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: short
            ) == false)
        }
    }

    @Test func isEnabledInCodex_falseWhenStoredHashIsWrong() throws {
        try withCodexFixture { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            // Replace the first stored hash with a well-formed but wrong digest.
            var lines = readFile(config).components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { $0.hasPrefix("trusted_hash = ") }) {
                lines[i] = "trusted_hash = \"sha256:\(String(repeating: "0", count: 64))\""
            }
            try lines.joined(separator: "\n").write(toFile: config, atomically: true, encoding: .utf8)

            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == false)
        }
    }

    @Test func isEnabledInCodex_toleratesTrailingCommentOnTrustedHash() throws {
        try withCodexFixture { config, hooksJSON, entries in
            try CodexHooksInstaller.enableInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            )
            let commented = readFile(config)
                .components(separatedBy: "\n")
                .map { $0.hasPrefix("trusted_hash = ") ? $0 + " # codex note" : $0 }
                .joined(separator: "\n")
            try commented.write(toFile: config, atomically: true, encoding: .utf8)

            #expect(CodexHooksInstaller.isEnabledInCodex(
                at: config, hooksJSONPath: hooksJSON, entries: entries
            ) == true)
        }
    }
}

// MARK: - SessionEnd timeout clamp

@Suite("CodexHooksInstaller — SessionEnd timeout clamp")
struct CodexSessionEndTimeoutTests {
    @Test func sessionEndUsesClampedTimeout() {
        #expect(CodexHooksInstaller.timeoutSeconds(for: "SessionEnd") == 3)
    }

    @Test func otherEventsUseDefaultTimeout() {
        for event in CodexHooksInstaller.agentEvents where event != "SessionEnd" {
            #expect(
                CodexHooksInstaller.timeoutSeconds(for: event) == CodexHooksInstaller.hookTimeoutSeconds,
                "unexpected timeout for \(event)"
            )
        }
    }

    // Digest of the 3s canonical form, computed independently of this code. Unlike the vectors
    // in CodexTrustHashTests it is not captured from a Codex-written config, so it pins the
    // canonicalization and that the clamp reaches the hash — not that 3 is Codex's real clamp.
    // That value comes from Codex 0.145.0's `clamping SessionEnd hook timeout to 3s` and from
    // observing SessionEnd actually fire; a future clamp change would pass this test silently.
    @Test func trustHashFoldsInClampedTimeout() {
        let hash = CodexHooksInstaller.computeTrustedHash(
            event: "SessionEnd", command: "/tmp/notify.sh SessionEnd"
        )
        #expect(hash == "sha256:6235468b2904e507eb76f6ef4c0ee7abffdf69edc69e0efeb4109b301d433088")
    }
}

// MARK: - CodexHooksError

@Suite("CodexHooksError")
struct CodexHooksErrorTests {
    // The error messages surface verbatim to the user via CodexSetupController.errorMessage.
    @Test func errorDescriptionsAreActionable() {
        let notRegistered = CodexHooksError.hooksNotRegistered("/p/hooks.json").errorDescription
        #expect(notRegistered?.contains("Install Hooks") == true)

        let unsupported = CodexHooksError.hooksUnsupported("/p/hooks.json").errorDescription
        #expect(unsupported?.contains("/p/hooks.json") == true)
    }
}
