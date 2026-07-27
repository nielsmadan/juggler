import Foundation
@testable import Juggler
import Testing

private func withAntigravityTempDir(_ body: (URL) throws -> Void) rethrows {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("antigravity-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

@Suite("AntigravityHooksInstaller — hooks.json merge")
struct AntigravityHooksJSONTests {
    private let notifyPath = "/Users/me/.gemini/hooks/juggler/notify.sh"

    private func loadRoot(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as? [String: Any] ?? [:]
    }

    @Test func mergeIntoMissingFile_addsJugglerKeyWithAllEvents() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)

            let root = try loadRoot(path)
            let juggler = try #require(root["juggler"] as? [String: Any])
            #expect(juggler.count == AntigravityHooksInstaller.agentEvents.count)
            for event in AntigravityHooksInstaller.agentEvents {
                #expect(juggler[event] != nil, "missing event \(event)")
            }
        }
    }

    // PreInvocation/Stop take a FLAT handler list — not the {matcher, hooks:[…]} wrapper.
    @Test func handlersAreFlat_withCommandAndTimeout() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)

            let root = try loadRoot(path)
            let juggler = try #require(root["juggler"] as? [String: Any])
            let handlers = try #require(juggler["Stop"] as? [[String: Any]])
            let handler = try #require(handlers.first)
            #expect(handler["type"] as? String == "command")
            #expect(handler["command"] as? String == "\(notifyPath) Stop")
            #expect(handler["timeout"] as? Int == AntigravityHooksInstaller.hookTimeoutSeconds)
            #expect(handler["hooks"] == nil)
        }
    }

    @Test func mergePreservesOtherTopLevelKeys() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            try """
            {"other-tool": {"PreToolUse": [{"matcher": "run_command", "hooks": [{"command": "echo hi"}]}]}}
            """.write(toFile: path, atomically: true, encoding: .utf8)

            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)

            let root = try loadRoot(path)
            #expect(root["other-tool"] != nil, "must not clobber another tool's hooks")
            #expect(root["juggler"] != nil)
        }
    }

    @Test func mergeIsIdempotent_replacesJugglerKey() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)
            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)

            let root = try loadRoot(path)
            let juggler = try #require(root["juggler"] as? [String: Any])
            let handlers = try #require(juggler["Stop"] as? [[String: Any]])
            #expect(handlers.count == 1, "re-merge must not duplicate handlers")
        }
    }

    @Test func mergeThrowsOnUnparseableJSON() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            try "{ not json".write(toFile: path, atomically: true, encoding: .utf8)

            #expect(throws: AntigravityHooksError.self) {
                try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)
            }
        }
    }

    @Test func mergeBacksUpPreexistingFile() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            try #"{"other-tool": {}}"#.write(toFile: path, atomically: true, encoding: .utf8)

            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)

            #expect(FileManager.default.fileExists(atPath: path + ".juggler-backup"))
        }
    }

    @Test func areHooksRegistered_trueAfterMerge_falseBefore() throws {
        try withAntigravityTempDir { dir in
            let path = dir.appendingPathComponent("hooks.json").path
            #expect(!AntigravityHooksInstaller.areHooksRegistered(
                hooksJSONPath: path, notifyScriptPath: notifyPath
            ))

            try AntigravityHooksInstaller.mergeHooksJSON(at: path, notifyScriptPath: notifyPath)

            #expect(AntigravityHooksInstaller.areHooksRegistered(
                hooksJSONPath: path, notifyScriptPath: notifyPath
            ))
        }
    }
}
