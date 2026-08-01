import Foundation
import Testing

@Suite("juggler-pi.ts — permission event contract")
struct PiExtensionBehaviorTests {
    private struct RunResult: Decodable {
        let events: [String]
        let registeredChannels: [String]
        let subscribedChannels: [String]
    }

    private static var extensionPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("juggler/Resources/pi-extension/juggler-pi.txt")
            .path
    }

    private func runExtension(actions: String) throws -> RunResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-extension-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let extensionURL = directory.appendingPathComponent("juggler-pi.ts")
        let harnessURL = directory.appendingPathComponent("harness.mjs")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: Self.extensionPath),
            to: extensionURL
        )
        try Self.harness(actions: actions).write(to: harnessURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = try URL(fileURLWithPath: Self.nodePath())
        process.arguments = [
            "--experimental-strip-types",
            harnessURL.path,
            extensionURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["NODE_NO_WARNINGS"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let log = String(decoding: data, as: UTF8.self)
        try #require(process.terminationStatus == 0, "Node harness failed:\n\(log)")
        return try JSONDecoder().decode(RunResult.self, from: data)
    }

    private static func nodePath() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v node"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let path = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(process.terminationStatus == 0 && !path.isEmpty, "Node 22.6+ is required")

        let versionProcess = Process()
        versionProcess.executableURL = URL(fileURLWithPath: path)
        versionProcess.arguments = ["--version"]
        let versionOutput = Pipe()
        versionProcess.standardOutput = versionOutput
        versionProcess.standardError = versionOutput
        try versionProcess.run()
        versionProcess.waitUntilExit()

        let version = String(
            decoding: versionOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let versionComponents = version.dropFirst().split(separator: ".").compactMap { Int($0) }
        let majorVersion = versionComponents.first ?? 0
        let minorVersion = versionComponents.dropFirst().first ?? 0
        let supportsTypeStripping = majorVersion > 22 || (majorVersion == 22 && minorVersion >= 6)
        try #require(versionProcess.terminationStatus == 0 && supportsTypeStripping, "Node 22.6+ is required")
        return path
    }

    private static func harness(actions: String) -> String {
        """
        import { pathToFileURL } from "node:url";

        const lifecycleHandlers = new Map();
        const eventHandlers = new Map();
        const registeredChannels = [];
        const posts = [];
        globalThis.fetch = async (_url, options) => {
          posts.push(JSON.parse(String(options.body)));
          return new Response(null, { status: 200 });
        };

        const { default: installExtension } = await import(pathToFileURL(process.argv[2]).href);
        const pi = {
          events: {
            on(channel, handler) {
              registeredChannels.push(channel);
              eventHandlers.set(channel, handler);
              return () => eventHandlers.delete(channel);
            },
          },
          on(event, handler) {
            lifecycleHandlers.set(event, handler);
          },
        };
        installExtension(pi);

        const ctx = {
          hasUI: true,
          sessionManager: {
            getSessionId() {
              return "pi-parent";
            },
          },
        };

        \(actions)
        await lifecycleHandlers.get("session_shutdown")({ reason: "reload" }, ctx);
        process.stdout.write(JSON.stringify({
          events: posts.map((post) => post.event),
          registeredChannels,
          subscribedChannels: [...eventHandlers.keys()],
        }));
        """
    }

    @Test func promptAndDecisionProducePermissionLifecycle() throws {
        let result = try runExtension(actions: """
        await lifecycleHandlers.get("session_start")({}, ctx);
        eventHandlers.get("permissions:ui_prompt")({ requestId: "prompt-1" });
        eventHandlers.get("permissions:decision")({
          result: "deny",
          resolution: "user_denied",
        });
        """)

        #expect(result.events == [
            "session_start",
            "permission_prompt",
            "permission_resolved"
        ])
        #expect(result.registeredChannels == [
            "permissions:ui_prompt",
            "permissions:decision"
        ])
        #expect(result.subscribedChannels.isEmpty)
    }

    @Test func ignoresDecisionsWithoutPendingPromptAndSilentDecisions() throws {
        let result = try runExtension(actions: """
        await lifecycleHandlers.get("session_start")({}, ctx);
        eventHandlers.get("permissions:decision")({
          result: "allow",
          resolution: "user_approved",
        });
        eventHandlers.get("permissions:ui_prompt")({ requestId: "prompt-1" });
        eventHandlers.get("permissions:decision")({
          result: "allow",
          resolution: "policy_allow",
        });
        if (posts.some((post) => post.event === "permission_resolved")) {
          throw new Error("silent decision resolved a pending prompt");
        }
        eventHandlers.get("permissions:decision")({
          result: "deny",
          resolution: "user_denied",
        });
        """)

        #expect(result.events == [
            "session_start",
            "permission_prompt",
            "permission_resolved"
        ])
    }

    @Test func settledSessionDiscardsPendingPrompts() throws {
        let result = try runExtension(actions: """
        await lifecycleHandlers.get("session_start")({}, ctx);
        eventHandlers.get("permissions:ui_prompt")({ requestId: "prompt-1" });
        await lifecycleHandlers.get("agent_settled")({}, ctx);
        eventHandlers.get("permissions:decision")({
          result: "deny",
          resolution: "user_denied",
        });
        """)

        #expect(result.events == [
            "session_start",
            "permission_prompt",
            "agent_settled"
        ])
    }

    @Test func childSessionDoesNotPostParentLifecycleEvents() throws {
        let result = try runExtension(actions: """
        ctx.hasUI = false;
        await lifecycleHandlers.get("session_start")({}, ctx);
        await lifecycleHandlers.get("agent_start")({}, ctx);
        await lifecycleHandlers.get("agent_settled")({}, ctx);
        """)

        #expect(result.events.isEmpty)
    }
}
