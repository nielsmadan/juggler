//
//  TerminalActivationTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

private enum MockActivationError: Error, Sendable {
    case generic
}

private actor ActivationMockBridge: TerminalBridge {
    var activateCalls: [String] = []
    var highlightCalls: [(String, HighlightConfig?, HighlightConfig?)] = []
    var activateError: Error?

    func start() async throws {}
    func stop() async {}

    func activate(sessionID: String) async throws {
        activateCalls.append(sessionID)
        if let activateError {
            throw activateError
        }
    }

    func highlight(sessionID: String, tabConfig: HighlightConfig?, paneConfig: HighlightConfig?) async throws {
        highlightCalls.append((sessionID, tabConfig, paneConfig))
    }

    func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? { nil }

    func setActivateError(_ error: Error?) {
        activateError = error
    }

    func recordedActivateCalls() -> [String] {
        activateCalls
    }

    func recordedHighlightCalls() -> [(String, HighlightConfig?, HighlightConfig?)] {
        highlightCalls
    }
}

// MARK: - buildTabHighlightConfig Tests

@Test func buildTabHighlight_disabled_returnsNil() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: false, useCycling: true, colorIndex: 0, customColor: [255, 0, 0], duration: 2.0
    )
    #expect(config == nil)
}

@Test func buildTabHighlight_cycling_usePaletteColor() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 2.0
    )
    #expect(config != nil)
    #expect(config?.color == CyclingColors.paletteRGB[0])
    #expect(config?.duration == 2.0)
}

@Test func buildTabHighlight_notCycling_useCustomColor() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [100, 200, 50], duration: 3.0
    )
    #expect(config?.color == [100, 200, 50])
}

@Test func buildTabHighlight_zeroDuration_defaultsToTwo() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [0, 0, 0], duration: 0
    )
    #expect(config?.duration == 2.0)
}

@Test func buildTabHighlight_colorIndex_wraps() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 7, customColor: [0, 0, 0], duration: 1.0
    )
    // 7 % 5 = 2
    #expect(config?.color == CyclingColors.paletteRGB[2])
}

// MARK: - buildPaneHighlightConfig Tests

@Test func buildPaneHighlight_disabled_returnsNil() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: false, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 1.0
    )
    #expect(config == nil)
}

@Test func buildPaneHighlight_cycling_useDarkPalette() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 1.0
    )
    #expect(config?.color == CyclingColors.darkPaletteRGB[0])
}

@Test func buildPaneHighlight_zeroDuration_defaultsToOne() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [50, 50, 50], duration: 0
    )
    #expect(config?.duration == 1.0)
}

// MARK: - activate(session:trigger:) Tests

@Suite(.serialized)
struct TerminalActivationBehaviorTests {
    @MainActor
    private func resetSharedState() async {
        SessionManager.shared.testSetSessions([])
        await TerminalBridgeRegistry.shared.register(ActivationMockBridge(), for: .iterm2)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnHotkey)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnGuiSelect)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnNotification)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.useTerminalCyclingColors)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightColorRed)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightColorGreen)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightColorBlue)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightColorRed)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightColorGreen)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightColorBlue)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightDuration)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightDuration)
    }

    @Test @MainActor func activate_missingBridge_throwsBridgeNotAvailable() async {
        await resetSharedState()
        let session = Session(
            claudeSessionID: "c1",
            terminalSessionID: "ghost-session",
            terminalType: .ghostty,
            agent: "claude-code",
            projectPath: "/tmp/ghost",
            state: .idle,
            startedAt: Date()
        )

        do {
            try await TerminalActivation.activate(session: session, trigger: .hotkey)
            Issue.record("Expected bridgeNotAvailable to be thrown")
        } catch let error as TerminalBridgeError {
            switch error {
            case let .bridgeNotAvailable(type):
                #expect(type == .ghostty)
            default:
                Issue.record("Unexpected TerminalBridgeError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func activate_highlightDisabled_onlyActivatesBridge() async throws {
        await resetSharedState()
        let bridge = ActivationMockBridge()
        await TerminalBridgeRegistry.shared.register(bridge, for: .iterm2)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.highlightOnHotkey)

        let session = makeSession("s1")
        SessionManager.shared.testSetSessions([session])

        try await TerminalActivation.activate(session: session, trigger: .hotkey)

        let activateCalls = await bridge.recordedActivateCalls()
        let highlightCalls = await bridge.recordedHighlightCalls()
        #expect(activateCalls == ["s1"])
        #expect(highlightCalls.isEmpty)
    }

    @Test @MainActor func activate_highlightEnabled_passesBuiltConfigsToBridge() async throws {
        await resetSharedState()
        let bridge = ActivationMockBridge()
        await TerminalBridgeRegistry.shared.register(bridge, for: .iterm2)

        UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnHotkey)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)
        UserDefaults.standard.set(false, forKey: AppStorageKeys.useTerminalCyclingColors)
        UserDefaults.standard.set(10.0, forKey: AppStorageKeys.tabHighlightColorRed)
        UserDefaults.standard.set(20.0, forKey: AppStorageKeys.tabHighlightColorGreen)
        UserDefaults.standard.set(30.0, forKey: AppStorageKeys.tabHighlightColorBlue)
        UserDefaults.standard.set(40.0, forKey: AppStorageKeys.paneHighlightColorRed)
        UserDefaults.standard.set(50.0, forKey: AppStorageKeys.paneHighlightColorGreen)
        UserDefaults.standard.set(60.0, forKey: AppStorageKeys.paneHighlightColorBlue)
        UserDefaults.standard.set(4.5, forKey: AppStorageKeys.tabHighlightDuration)
        UserDefaults.standard.set(1.5, forKey: AppStorageKeys.paneHighlightDuration)

        let session = makeSession("s1")
        SessionManager.shared.testSetSessions([session])

        try await TerminalActivation.activate(session: session, trigger: .hotkey)

        let highlightCalls = await bridge.recordedHighlightCalls()
        #expect(highlightCalls.count == 1)
        let (_, tabConfig, paneConfig) = try #require(highlightCalls.first)
        #expect(tabConfig?.color == [10, 20, 30])
        #expect(tabConfig?.duration == 4.5)
        #expect(paneConfig?.color == [40, 50, 60])
        #expect(paneConfig?.duration == 1.5)
    }

    @Test @MainActor func activate_sessionNotFound_removesSessionAndRemapsError() async {
        await resetSharedState()
        let bridge = ActivationMockBridge()
        await bridge.setActivateError(TerminalBridgeError.commandFailed("Session not found in terminal"))
        await TerminalBridgeRegistry.shared.register(bridge, for: .iterm2)

        let session = makeSession("s1")
        SessionManager.shared.testSetSessions([session])

        do {
            try await TerminalActivation.activate(session: session, trigger: .hotkey)
            Issue.record("Expected sessionNotFound to be thrown")
        } catch let error as TerminalBridgeError {
            switch error {
            case let .sessionNotFound(sessionID):
                #expect(sessionID == "s1")
            default:
                Issue.record("Unexpected TerminalBridgeError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(SessionManager.shared.sessions.isEmpty)
    }

    @Test @MainActor func activate_otherErrors_propagateWithoutRemovingSession() async {
        await resetSharedState()
        let bridge = ActivationMockBridge()
        await bridge.setActivateError(MockActivationError.generic)
        await TerminalBridgeRegistry.shared.register(bridge, for: .iterm2)

        let session = makeSession("s1")
        SessionManager.shared.testSetSessions([session])

        do {
            try await TerminalActivation.activate(session: session, trigger: .hotkey)
            Issue.record("Expected generic error to be thrown")
        } catch let error as MockActivationError {
            #expect(error == .generic)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(SessionManager.shared.sessions.map(\.id) == ["s1"])
    }
}
