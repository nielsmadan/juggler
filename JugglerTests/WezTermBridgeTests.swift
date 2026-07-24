import Foundation
@testable import Juggler
import Testing

// `TerminalSessionInfo` and the bridge singleton are main-actor-isolated (the app target
// defaults actor isolation to MainActor), so the whole suite runs on the main actor to read
// results and touch the bridge without cross-actor warnings.
@Suite("WezTermBridge")
@MainActor
struct WezTermBridgeTests {
    // `wezterm cli list --format json` is a flat array of pane objects.
    private let sampleList = """
    [
        {"window_id": 0, "tab_id": 0, "pane_id": 0, "workspace": "default",
         "size": {"rows": 50, "cols": 200}, "title": "zsh", "cwd": "file:///Users/x"},
        {"window_id": 0, "tab_id": 0, "pane_id": 1, "workspace": "default",
         "size": {"rows": 50, "cols": 200}, "title": "vim", "cwd": "file:///Users/x"},
        {"window_id": 0, "tab_id": 1, "pane_id": 2, "workspace": "default",
         "size": {"rows": 50, "cols": 200}, "title": "htop", "cwd": "file:///Users/x"}
    ]
    """

    private func panes(_ json: String) -> [[String: Any]] {
        WezTermBridge.decodeWezTermPanes(json) ?? []
    }

    // MARK: - decodeWezTermPanes (parse-failure vs valid-array distinction)

    @Test func decodeWezTermPanes_validArray_returnsPanes() {
        #expect(WezTermBridge.decodeWezTermPanes(sampleList)?.count == 3)
    }

    @Test func decodeWezTermPanes_invalidJSON_returnsNil() {
        #expect(WezTermBridge.decodeWezTermPanes("not json") == nil)
    }

    @Test func decodeWezTermPanes_topLevelObject_returnsNil() {
        #expect(WezTermBridge.decodeWezTermPanes("{}") == nil)
    }

    @Test func decodeWezTermPanes_emptyArray_returnsEmpty() {
        #expect(WezTermBridge.decodeWezTermPanes("[]")?.isEmpty == true)
    }

    // MARK: - parseWezTermList

    @Test func parseWezTermList_secondPaneInTab_returnsIndices() {
        let info = WezTermBridge.parseWezTermList(panes(sampleList), paneID: "1")

        #expect(info != nil)
        #expect(info?.id == "1")
        #expect(info?.tabName == "vim")
        #expect(info?.windowName == "Window 0")
        #expect(info?.tabIndex == 0)
        #expect(info?.paneIndex == 1)
        #expect(info?.paneCount == 2)
        #expect(info?.isActive == false)
    }

    @Test func parseWezTermList_paneInSecondTab_returnsTabIndex() {
        let info = WezTermBridge.parseWezTermList(panes(sampleList), paneID: "2")

        #expect(info != nil)
        #expect(info?.tabName == "htop")
        #expect(info?.tabIndex == 1)
        #expect(info?.paneIndex == 0)
        #expect(info?.paneCount == 1)
    }

    @Test func parseWezTermList_paneNotFound_returnsNil() {
        #expect(WezTermBridge.parseWezTermList(panes(sampleList), paneID: "999") == nil)
    }

    @Test func parseWezTermList_emptyArray_returnsNil() {
        #expect(WezTermBridge.parseWezTermList([], paneID: "0") == nil)
    }

    @Test func parseWezTermList_stringPaneID_matches() {
        // `pane_id` may decode as a JSON string rather than an int; it must still match.
        let info = WezTermBridge.parseWezTermList(
            panes(#"[{"window_id":0,"tab_id":0,"pane_id":"5","title":"zsh"}]"#),
            paneID: "5"
        )

        #expect(info?.id == "5")
        #expect(info?.paneCount == 1)
    }

    @Test func parseWezTermList_multiWindow_scopesToWindow() {
        let json = """
        [
            {"window_id": 0, "tab_id": 0, "pane_id": 0, "title": "w0t0"},
            {"window_id": 1, "tab_id": 1, "pane_id": 1, "title": "w1t1a"},
            {"window_id": 1, "tab_id": 1, "pane_id": 2, "title": "w1t1b"},
            {"window_id": 1, "tab_id": 2, "pane_id": 3, "title": "w1t2"}
        ]
        """
        // Pane 3 is the second tab of window 1, so tabIndex is window-relative (1), and its
        // pane count/index must not include window 0's panes.
        let info = WezTermBridge.parseWezTermList(panes(json), paneID: "3")

        #expect(info?.windowName == "Window 1")
        #expect(info?.tabIndex == 1)
        #expect(info?.paneIndex == 0)
        #expect(info?.paneCount == 1)
    }

    @Test func parseWezTermList_duplicateTabIDAcrossWindows_doesNotMerge() {
        // Two windows share tab_id 5. The composite (window_id, tab_id) key must keep pane
        // counts scoped to the pane's own window — a tab_id-only filter would report 2.
        let json = """
        [
            {"window_id": 0, "tab_id": 5, "pane_id": 0, "title": "w0"},
            {"window_id": 1, "tab_id": 5, "pane_id": 1, "title": "w1"}
        ]
        """
        let info = WezTermBridge.parseWezTermList(panes(json), paneID: "1")

        #expect(info?.windowName == "Window 1")
        #expect(info?.paneCount == 1)
        #expect(info?.paneIndex == 0)
    }

    @Test func parseWezTermList_missingTitle_usesFallback() {
        let info = WezTermBridge.parseWezTermList(panes(#"[{"window_id": 3, "tab_id": 0, "pane_id": 7}]"#), paneID: "7")

        #expect(info != nil)
        #expect(info?.tabName == "Tab 1")
        #expect(info?.windowName == "Window 3")
        #expect(info?.paneCount == 1)
    }

    @Test func parseWezTermList_missingWindowID_usesFallbackName() {
        let info = WezTermBridge.parseWezTermList(panes(#"[{"tab_id": 0, "pane_id": 5, "title": "zsh"}]"#), paneID: "5")

        #expect(info != nil)
        #expect(info?.windowName == "WezTerm")
    }

    @Test func parseWezTermList_nullFields_usesFallbacks() {
        // JSON null decodes to NSNull (not a missing key); the `as? Int`/`as? String` casts
        // must fall through to the fallbacks.
        let info = WezTermBridge.parseWezTermList(
            panes(#"[{"window_id": null, "tab_id": null, "pane_id": 9, "title": null}]"#),
            paneID: "9"
        )

        #expect(info != nil)
        #expect(info?.tabName == "Tab 1")
        #expect(info?.windowName == "WezTerm")
        #expect(info?.paneCount == 1)
    }

    // MARK: - bridge behavior

    @Test func highlight_isNoOp() async throws {
        let bridge = WezTermBridge.shared

        // WezTerm has no external color mechanism — highlight must never throw.
        try await bridge.highlight(
            sessionID: "0",
            tabConfig: HighlightConfig(enabled: true, color: [255, 0, 0], duration: 1.0),
            paneConfig: HighlightConfig(enabled: true, color: [0, 0, 0], duration: 1.0)
        )
    }
}

/// Serialized: these mutate the shared `WezTermBridge`'s list-output provider seam.
@Suite("WezTermBridge getSessionInfo contract", .serialized)
@MainActor
struct WezTermBridgeSessionInfoTests {
    private let validList = #"[{"window_id":0,"tab_id":0,"pane_id":1,"title":"vim"}]"#

    private func reset() async {
        await WezTermBridge.shared.setListOutputProviderForTesting(nil)
        await WezTermBridge.shared.stop()
    }

    @Test func getSessionInfo_panePresent_returnsInfo() async throws {
        let bridge = WezTermBridge.shared
        await bridge.setListOutputProviderForTesting { validList }

        let info = try await bridge.getSessionInfo(sessionID: "1")

        #expect(info?.id == "1")
        #expect(info?.tabName == "vim")
        await reset()
    }

    @Test func getSessionInfo_paneAbsentFromValidList_returnsNil() async throws {
        let bridge = WezTermBridge.shared
        await bridge.setListOutputProviderForTesting { validList }

        // A well-formed list that lacks the pane is a *confirmed* removal → nil.
        let info = try await bridge.getSessionInfo(sessionID: "999")

        #expect(info == nil)
        await reset()
    }

    @Test func getSessionInfo_unparseableOutput_throws() async {
        let bridge = WezTermBridge.shared
        // Exit-0 but non-JSON output is "couldn't determine" — must throw, never resolve to
        // nil (a nil would let a live session be evicted as "gone").
        await bridge.setListOutputProviderForTesting { "not json" }

        await #expect(throws: TerminalBridgeError.self) {
            try await bridge.getSessionInfo(sessionID: "1")
        }
        await reset()
    }

    @Test func getSessionInfo_emptyOutput_throws() async {
        let bridge = WezTermBridge.shared
        await bridge.setListOutputProviderForTesting { "" }

        await #expect(throws: TerminalBridgeError.self) {
            try await bridge.getSessionInfo(sessionID: "1")
        }
        await reset()
    }

    @Test func getSessionInfo_providerThrows_rethrows() async {
        let bridge = WezTermBridge.shared
        await bridge.setListOutputProviderForTesting { throw TerminalBridgeError.connectionFailed }

        await #expect(throws: TerminalBridgeError.self) {
            try await bridge.getSessionInfo(sessionID: "1")
        }
        await reset()
    }

    @Test func stop_calledTwice_idempotent() async {
        let bridge = WezTermBridge.shared
        await bridge.stop()
        await bridge.stop()
    }
}
