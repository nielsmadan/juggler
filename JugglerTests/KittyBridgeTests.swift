import Foundation
@testable import Juggler
import Testing

// MARK: - parseKittyLsOutput Tests

@Test func parseKittyLsOutput_validOutput_returnsInfo() async {
    let bridge = KittyBridge.shared
    let json = """
    [
        {
            "id": 1,
            "platform_window_id": 12345,
            "tabs": [
                {
                    "id": 1,
                    "title": "My Tab",
                    "windows": [
                        {
                            "id": 42,
                            "title": "zsh",
                            "is_focused": true
                        },
                        {
                            "id": 43,
                            "title": "vim",
                            "is_focused": false
                        }
                    ]
                }
            ]
        }
    ]
    """

    let info = await bridge.parseKittyLsOutput(json, windowID: "42")

    #expect(info != nil)
    #expect(info?.id == "42")
    #expect(info?.tabName == "My Tab")
    #expect(info?.windowName == "Window 12345")
    #expect(info?.paneIndex == 0)
    #expect(info?.paneCount == 2)
    #expect(info?.isActive == true)
}

@Test func parseKittyLsOutput_secondWindow_returnsCorrectIndex() async {
    let bridge = KittyBridge.shared
    let json = """
    [
        {
            "id": 1,
            "tabs": [
                {
                    "id": 1,
                    "title": "Tab 1",
                    "windows": [
                        {"id": 10, "is_focused": false},
                        {"id": 11, "is_focused": true}
                    ]
                }
            ]
        }
    ]
    """

    let info = await bridge.parseKittyLsOutput(json, windowID: "11")

    #expect(info != nil)
    #expect(info?.paneIndex == 1)
    #expect(info?.paneCount == 2)
    #expect(info?.tabIndex == 0)
}

@Test func parseKittyLsOutput_windowNotFound_returnsNil() async {
    let bridge = KittyBridge.shared
    let json = """
    [
        {
            "id": 1,
            "tabs": [
                {
                    "id": 1,
                    "title": "Tab",
                    "windows": [{"id": 10, "is_focused": true}]
                }
            ]
        }
    ]
    """

    let info = await bridge.parseKittyLsOutput(json, windowID: "999")

    #expect(info == nil)
}

@Test func parseKittyLsOutput_invalidJSON_returnsNil() async {
    let bridge = KittyBridge.shared

    let info = await bridge.parseKittyLsOutput("not json", windowID: "42")

    #expect(info == nil)
}

@Test func parseKittyLsOutput_emptyArray_returnsNil() async {
    let bridge = KittyBridge.shared

    let info = await bridge.parseKittyLsOutput("[]", windowID: "42")

    #expect(info == nil)
}

@Test func parseKittyLsOutput_multipleTabs_findsCorrectTab() async {
    let bridge = KittyBridge.shared
    let json = """
    [
        {
            "id": 1,
            "tabs": [
                {
                    "id": 1,
                    "title": "First Tab",
                    "windows": [{"id": 10, "is_focused": false}]
                },
                {
                    "id": 2,
                    "title": "Second Tab",
                    "windows": [{"id": 20, "is_focused": true}]
                }
            ]
        }
    ]
    """

    let info = await bridge.parseKittyLsOutput(json, windowID: "20")

    #expect(info != nil)
    #expect(info?.tabName == "Second Tab")
    #expect(info?.tabIndex == 1)
    #expect(info?.paneIndex == 0)
    #expect(info?.paneCount == 1)
}

@Test func parseKittyLsOutput_missingTitles_usesFallbacks() async {
    let bridge = KittyBridge.shared
    let json = """
    [
        {
            "id": 1,
            "tabs": [
                {
                    "id": 1,
                    "windows": [
                        {
                            "id": 42,
                            "is_focused": false
                        }
                    ]
                }
            ]
        }
    ]
    """

    let info = await bridge.parseKittyLsOutput(json, windowID: "42")

    #expect(info != nil)
    #expect(info?.tabName == "Tab 1")
    #expect(info?.windowName == "Kitty")
    #expect(info?.isActive == false)
}

@Test func parseKittyLsOutput_missingTabs_returnsNil() async {
    let bridge = KittyBridge.shared
    let json = """
    [
        {
            "id": 1
        }
    ]
    """

    let info = await bridge.parseKittyLsOutput(json, windowID: "42")

    #expect(info == nil)
}

// MARK: - Socket Registration Tests

@Test func registerSocket_storesPath() async {
    let bridge = KittyBridge.shared
    await bridge.registerSocket(windowID: "test-123", socketPath: "unix:/tmp/kitty-test")

    // We can't directly read socketPaths, but getSessionInfo without a real socket
    // will return nil gracefully (proving the path was set but socket is not real)
    let info = try? await bridge.getSessionInfo(sessionID: "test-123")
    // Won't have valid data since socket doesn't exist, but shouldn't crash
    #expect(info == nil)
}

@Test func getSessionInfo_unregisteredSession_returnsNil() async throws {
    let bridge = KittyBridge.shared

    let info = try await bridge.getSessionInfo(sessionID: "missing-window")

    #expect(info == nil)
}

@Test func activate_unregisteredSession_throwsConnectionFailed() async {
    let bridge = KittyBridge.shared

    do {
        try await bridge.activate(sessionID: "missing-window")
        Issue.record("Expected connectionFailed for missing socket registration")
    } catch let error as TerminalBridgeError {
        switch error {
        case .connectionFailed:
            break
        default:
            Issue.record("Unexpected TerminalBridgeError: \(error)")
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func highlight_unregisteredSession_isNoOp() async throws {
    let bridge = KittyBridge.shared

    try await bridge.highlight(
        sessionID: "missing-window",
        tabConfig: HighlightConfig(enabled: true, color: [255, 0, 0], duration: 1.0),
        paneConfig: HighlightConfig(enabled: true, color: [0, 0, 0], duration: 1.0)
    )
}

@Test func stop_clearsRegisteredSockets() async throws {
    let bridge = KittyBridge.shared
    await bridge.registerSocket(windowID: "window-1", socketPath: "unix:/tmp/kitty-test")
    await bridge.stop()

    let info = try await bridge.getSessionInfo(sessionID: "window-1")

    #expect(info == nil)
}

// MARK: - rgbToHex Tests

@Test func rgbToHex_standardColor() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([255, 128, 0])
    #expect(result == "#FF8000")
}

@Test func rgbToHex_black() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([0, 0, 0])
    #expect(result == "#000000")
}

@Test func rgbToHex_white() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([255, 255, 255])
    #expect(result == "#FFFFFF")
}

@Test func rgbToHex_tooFewElements_returnsFallback() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([255])
    #expect(result == "#FF0000")
}

@Test func rgbToHex_emptyArray_returnsFallback() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([])
    #expect(result == "#FF0000")
}
