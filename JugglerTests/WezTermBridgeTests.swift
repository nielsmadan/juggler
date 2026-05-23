import Foundation
@testable import Juggler
import Testing

@Suite("WezTermBridge")
struct WezTermBridgeTests {
    // MARK: - parseWezTermListOutput Tests

    @Test func parseWezTermListOutput_validOutput_returnsInfo() async {
        let bridge = WezTermBridge.shared
        let json = """
        [
            {
                "window_id": 0,
                "tab_id": 0,
                "pane_id": 0,
                "workspace": "default",
                "title": "My Tab",
                "cwd": "file:///Users/me",
                "is_active": true
            },
            {
                "window_id": 0,
                "tab_id": 0,
                "pane_id": 1,
                "workspace": "default",
                "title": "My Tab",
                "cwd": "file:///Users/me",
                "is_active": false
            }
        ]
        """

        let info = await bridge.parseWezTermListOutput(json, paneID: "0")

        #expect(info != nil)
        #expect(info?.id == "0")
        #expect(info?.tabName == "My Tab")
        #expect(info?.windowName == "Window 0")
        #expect(info?.tabIndex == 0)
        #expect(info?.paneIndex == 0)
        #expect(info?.paneCount == 2)
        #expect(info?.isActive == true)
    }

    @Test func parseWezTermListOutput_secondPaneInTab_returnsCorrectIndex() async {
        let bridge = WezTermBridge.shared
        let json = """
        [
            {"window_id": 0, "tab_id": 0, "pane_id": 10, "title": "T", "is_active": false},
            {"window_id": 0, "tab_id": 0, "pane_id": 11, "title": "T", "is_active": true}
        ]
        """

        let info = await bridge.parseWezTermListOutput(json, paneID: "11")

        #expect(info?.paneIndex == 1)
        #expect(info?.paneCount == 2)
    }

    @Test func parseWezTermListOutput_paneNotFound_returnsNil() async {
        let bridge = WezTermBridge.shared
        let json = """
        [{"window_id": 0, "tab_id": 0, "pane_id": 0, "title": "T", "is_active": true}]
        """

        let info = await bridge.parseWezTermListOutput(json, paneID: "999")

        #expect(info == nil)
    }

    @Test func parseWezTermListOutput_invalidJSON_returnsNil() async {
        let bridge = WezTermBridge.shared

        let info = await bridge.parseWezTermListOutput("not json", paneID: "0")

        #expect(info == nil)
    }

    @Test func parseWezTermListOutput_emptyArray_returnsNil() async {
        let bridge = WezTermBridge.shared

        let info = await bridge.parseWezTermListOutput("[]", paneID: "0")

        #expect(info == nil)
    }

    @Test func parseWezTermListOutput_missingTitle_usesFallback() async {
        let bridge = WezTermBridge.shared
        let json = """
        [{"window_id": 0, "tab_id": 0, "pane_id": 0, "is_active": false}]
        """

        let info = await bridge.parseWezTermListOutput(json, paneID: "0")

        #expect(info != nil)
        #expect(info?.tabName == "Tab 1")
        #expect(info?.windowName == "WezTerm")
        #expect(info?.isActive == false)
    }

    @Test func parseWezTermListOutput_multipleTabsInWindow_findsCorrectTab() async {
        let bridge = WezTermBridge.shared
        let json = """
        [
            {"window_id": 0, "tab_id": 0, "pane_id": 100, "title": "First", "is_active": false},
            {"window_id": 0, "tab_id": 1, "pane_id": 200, "title": "Second", "is_active": true}
        ]
        """

        let info = await bridge.parseWezTermListOutput(json, paneID: "200")

        #expect(info?.tabName == "Second")
        #expect(info?.tabIndex == 1)
        #expect(info?.paneIndex == 0)
        #expect(info?.paneCount == 1)
    }

    @Test func parseWezTermListOutput_topLevelObject_returnsNil() async {
        let bridge = WezTermBridge.shared

        let info = await bridge.parseWezTermListOutput("{}", paneID: "0")

        #expect(info == nil)
    }

    // MARK: - bridge no-op paths

    @Test func getSessionInfo_unregisteredSession_returnsNil() async throws {
        let bridge = WezTermBridge.shared

        let info = try await bridge.getSessionInfo(sessionID: "missing-pane")

        #expect(info == nil)
    }

    @Test func highlight_isNoOp_whenDisabled() async throws {
        let bridge = WezTermBridge.shared

        try await bridge.highlight(
            sessionID: "any",
            tabConfig: HighlightConfig(enabled: false, color: [0, 0, 0], duration: 0),
            paneConfig: HighlightConfig(enabled: false, color: [0, 0, 0], duration: 0)
        )
    }

    @Test func stop_calledTwice_idempotent() async {
        let bridge = WezTermBridge.shared
        await bridge.stop()
        await bridge.stop()
    }

    // MARK: - Highlight OSC encoding

    @Test func rgbToHex_standardColor() async {
        let bridge = WezTermBridge.shared
        let result = await bridge.rgbToHex([255, 128, 0])
        #expect(result == "FF8000")
    }

    @Test func rgbToHex_black() async {
        let bridge = WezTermBridge.shared
        let result = await bridge.rgbToHex([0, 0, 0])
        #expect(result == "000000")
    }

    @Test func rgbToHex_tooFewElements_returnsFallback() async {
        let bridge = WezTermBridge.shared
        let result = await bridge.rgbToHex([255])
        #expect(result == "FF0000")
    }

    @Test func userVarOSC_setColor() async {
        let bridge = WezTermBridge.shared
        let payload = await bridge.userVarOSCPayload(name: "juggler_color", value: "FFA500")
        // OSC 1337 SetUserVar=<name>=<base64(value)>BEL
        // base64("FFA500") == "RkZBNTAw"
        let expected = "\u{1B}]1337;SetUserVar=juggler_color=RkZBNTAw\u{07}"
        #expect(payload == expected)
    }

    @Test func userVarOSC_clearColor() async {
        let bridge = WezTermBridge.shared
        let payload = await bridge.userVarOSCPayload(name: "juggler_color", value: "")
        // Empty value → base64("") == ""
        let expected = "\u{1B}]1337;SetUserVar=juggler_color=\u{07}"
        #expect(payload == expected)
    }

    // MARK: - reconcile

    @Test func reconcile_withoutWezTermBinary_isNoOp() async {
        let bridge = WezTermBridge.shared
        await bridge.stop() // Clear wezTermPath
        // Without start() succeeding, wezTermPath is nil; reconcile should silently return.
        await bridge.reconcile()
    }

    @Test func registerPane_isAccepted() async {
        let bridge = WezTermBridge.shared
        await bridge.registerPane(paneID: "test-pane-42")
        // No assertion: this is a no-throw smoke test ensuring the method exists and is idempotent.
        await bridge.registerPane(paneID: "test-pane-42")
    }
}
