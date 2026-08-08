import Foundation
@testable import Juggler
import Testing

@Suite("BeaconMetadata")
struct BeaconMetadataTests {
    @Test func resolve_singleTerminalAndHarness_hasNoSubtitle() {
        let target = makeSession("target")
        let other = makeSession("other")

        #expect(BeaconMetadata.resolve(for: target, among: [target, other]).subtitle == nil)
    }

    @Test func resolve_multipleTerminals_includesTerminalName() {
        let target = makeSession("target", terminalType: .iterm2)
        let other = makeSession("other", terminalType: .kitty)

        #expect(BeaconMetadata.resolve(for: target, among: [target, other]).subtitle == "iTerm2")
    }

    @Test func resolve_multipleHarnesses_includesHarnessName() {
        let target = makeSession("target", agent: "claude-code")
        let other = makeSession("other", agent: "codex")

        #expect(BeaconMetadata.resolve(for: target, among: [target, other]).subtitle == "Claude Code")
    }

    @Test func resolve_multipleTerminalsAndHarnesses_joinsBothNames() {
        let target = makeSession("target", terminalType: .iterm2, agent: "claude-code")
        let other = makeSession("other", terminalType: .kitty, agent: "codex")

        #expect(BeaconMetadata.resolve(for: target, among: [target, other]).subtitle == "iTerm2 · Claude Code")
    }

    @Test func resolve_backburneredSessionContributesTerminal() {
        let target = makeSession("target", terminalType: .iterm2)
        let backburnered = makeSession("other", terminalType: .wezterm, state: .backburner)

        #expect(BeaconMetadata.resolve(for: target, among: [target, backburnered]).subtitle == "iTerm2")
    }

    @Test func resolve_backburneredSessionContributesHarness() {
        let target = makeSession("target", agent: "claude-code")
        let backburnered = makeSession("other", agent: "pi", state: .backburner)

        #expect(BeaconMetadata.resolve(for: target, among: [target, backburnered]).subtitle == "Claude Code")
    }

    private func makeSession(
        _ id: String,
        terminalType: TerminalType = .iterm2,
        agent: String = "claude-code",
        state: SessionState = .idle
    ) -> Session {
        Session(
            claudeSessionID: id,
            terminalSessionID: id,
            terminalType: terminalType,
            agent: agent,
            projectPath: "/test/\(id)",
            state: state,
            startedAt: Date()
        )
    }
}
