//
//  TerminalActivationTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

@Suite("TerminalActivation")
struct TerminalActivationTests {
    private enum MockActivationError: Error, Sendable {
        case generic
    }

    private actor ActivationMockBridge: TerminalBridge {
        var activateCalls: [String] = []
        var highlightCalls: [(String, HighlightConfig?, HighlightConfig?)] = []
        var activateError: Error?
        var sessionInfoResult: TerminalSessionInfo?
        var sessionInfoError: Error?
        var sessionInfoCallCount = 0

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

        func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? {
            sessionInfoCallCount += 1
            if let sessionInfoError {
                throw sessionInfoError
            }
            return sessionInfoResult
        }

        func setActivateError(_ error: Error?) {
            activateError = error
        }

        func setSessionInfoResult(_ info: TerminalSessionInfo?) {
            sessionInfoResult = info
        }

        func setSessionInfoError(_ error: Error?) {
            sessionInfoError = error
        }

        func recordedSessionInfoCallCount() -> Int {
            sessionInfoCallCount
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

    // MARK: - shouldRunLocalTmuxSelect Tests

    @Test func shouldRunLocalTmuxSelect_localTmux_true() {
        var session = makeSession("s1")
        session.tmuxPane = "%1"
        #expect(TerminalActivation.shouldRunLocalTmuxSelect(for: session))
    }

    @Test func shouldRunLocalTmuxSelect_remoteTmux_false() {
        var session = makeSession("s1")
        session.tmuxPane = "%1"
        session.remoteHost = "user@host"
        #expect(!TerminalActivation.shouldRunLocalTmuxSelect(for: session))
    }

    @Test func shouldRunLocalTmuxSelect_noTmux_false() {
        let session = makeSession("s1")
        #expect(!TerminalActivation.shouldRunLocalTmuxSelect(for: session))
    }

    // MARK: - activate(session:trigger:) Tests

    @Suite(.serialized)
    struct TerminalActivationBehaviorTests {
        private func resetHighlightDefaults() {
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
            resetHighlightDefaults()
            let registry = TerminalBridgeRegistry()
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
                try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)
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
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.highlightOnHotkey)

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            let activateCalls = await bridge.recordedActivateCalls()
            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(activateCalls == ["s1"])
            #expect(highlightCalls.isEmpty)
        }

        @Test @MainActor func activate_remoteTmux_addressesLiveHostPane() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnHotkey)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)

            var session = Session(
                claudeSessionID: "c1", terminalSessionID: "w4t1p0:STALE",
                tmuxPane: "%11", terminalType: .iterm2, agent: "claude-code",
                projectPath: "/test", state: .idle, startedAt: Date()
            )
            session.remoteHost = "user@host"
            session.liveHostPaneID = "LIVE-UUID"

            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            // Both activate and highlight target the learned live pane, not the stale
            // remote-captured terminalSessionID.
            let activateCalls = await bridge.recordedActivateCalls()
            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(activateCalls == ["LIVE-UUID"])
            #expect(highlightCalls.map(\.0) == ["LIVE-UUID"])
        }

        @Test @MainActor func activate_emptyLiveHostPaneID_fallsBackToTerminalSessionID() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.highlightOnHotkey)

            var session = Session(
                claudeSessionID: "c1", terminalSessionID: "w1t0p0:REAL",
                terminalType: .iterm2, agent: "claude-code",
                projectPath: "/test", state: .idle, startedAt: Date()
            )
            // An empty binding must not mask the real id or trip the empty-id removal guard.
            session.liveHostPaneID = ""

            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            let activateCalls = await bridge.recordedActivateCalls()
            #expect(activateCalls == ["w1t0p0:REAL"])
        }

        @Test @MainActor func activate_highlightEnabled_passesBuiltConfigsToBridge() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

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
            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.count == 1)
            let (_, tabConfig, paneConfig) = try #require(highlightCalls.first)
            #expect(tabConfig?.color == [10, 20, 30])
            #expect(tabConfig?.duration == 4.5)
            #expect(paneConfig?.color == [40, 50, 60])
            #expect(paneConfig?.duration == 1.5)
        }

        @Test @MainActor func activate_sessionNotFound_removesSessionAndRemapsError() async {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            await bridge.setActivateError(TerminalBridgeError.commandFailed("Session not found in terminal"))
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            let manager = SessionManager()
            let session = makeSession("s1")
            manager.testSetSessions([session])

            do {
                try await TerminalActivation.activate(
                    session: session,
                    trigger: .hotkey,
                    sessionManager: manager,
                    registry: registry
                )
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

            #expect(manager.sessions.isEmpty)
            let infoCalls = await bridge.recordedSessionInfoCallCount()
            #expect(infoCalls == 0)
        }

        @Test @MainActor func activate_otherErrors_propagateWithoutRemovingSession() async {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            await bridge.setActivateError(MockActivationError.generic)
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            let manager = SessionManager()
            let session = makeSession("s1")
            manager.testSetSessions([session])

            do {
                try await TerminalActivation.activate(
                    session: session,
                    trigger: .hotkey,
                    sessionManager: manager,
                    registry: registry
                )
                Issue.record("Expected generic error to be thrown")
            } catch let error as MockActivationError {
                #expect(error == .generic)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            #expect(manager.sessions.map(\.id) == ["s1"])
        }

        @Test @MainActor func activate_emptyTerminalSessionID_removesSessionWithoutCallingBridge() async {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            // A phantom session with no terminal session ID — historically minted
            // when a hook arrived without ITERM_SESSION_ID/KITTY_WINDOW_ID. It must
            // be removed before reaching the bridge (an empty id makes the iTerm2
            // daemon assert and leaves the row stuck).
            let manager = SessionManager()
            let session = makeSession("")
            manager.testSetSessions([session])

            do {
                try await TerminalActivation.activate(
                    session: session,
                    trigger: .hotkey,
                    sessionManager: manager,
                    registry: registry
                )
                Issue.record("Expected sessionNotFound to be thrown")
            } catch let error as TerminalBridgeError {
                switch error {
                case let .sessionNotFound(sessionID):
                    #expect(sessionID == "")
                default:
                    Issue.record("Unexpected TerminalBridgeError: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            #expect(manager.sessions.isEmpty)
            let activateCalls = await bridge.recordedActivateCalls()
            #expect(activateCalls.isEmpty)
            let infoCalls = await bridge.recordedSessionInfoCallCount()
            #expect(infoCalls == 0)
        }

        @Test @MainActor func activate_opaqueCommandFailed_sessionGone_removesSession() async {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            await bridge.setActivateError(TerminalBridgeError.commandFailed(""))
            await bridge.setSessionInfoResult(nil)
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            let manager = SessionManager()
            let session = makeSession("s1")
            manager.testSetSessions([session])

            do {
                try await TerminalActivation.activate(
                    session: session,
                    trigger: .hotkey,
                    sessionManager: manager,
                    registry: registry
                )
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

            #expect(manager.sessions.isEmpty)
            let infoCalls = await bridge.recordedSessionInfoCallCount()
            #expect(infoCalls == 1)
        }

        @Test @MainActor func activate_opaqueCommandFailed_sessionStillExists_propagatesWithoutRemoving() async {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            await bridge.setActivateError(TerminalBridgeError.commandFailed(""))
            await bridge.setSessionInfoResult(
                TerminalSessionInfo(
                    id: "s1", tabName: "Tab", windowName: "Window",
                    tabIndex: 0, paneIndex: 0, paneCount: 1, isActive: false
                )
            )
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            let manager = SessionManager()
            let session = makeSession("s1")
            manager.testSetSessions([session])

            do {
                try await TerminalActivation.activate(
                    session: session,
                    trigger: .hotkey,
                    sessionManager: manager,
                    registry: registry
                )
                Issue.record("Expected commandFailed to propagate")
            } catch let error as TerminalBridgeError {
                if case .commandFailed = error {} else {
                    Issue.record("Unexpected TerminalBridgeError: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            #expect(manager.sessions.map(\.id) == ["s1"])
            let infoCalls = await bridge.recordedSessionInfoCallCount()
            #expect(infoCalls == 1)
        }

        @Test @MainActor func activate_opaqueCommandFailed_sessionInfoThrows_propagatesWithoutRemoving() async {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            await bridge.setActivateError(TerminalBridgeError.commandFailed(""))
            await bridge.setSessionInfoError(TerminalBridgeError.connectionFailed)
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            let manager = SessionManager()
            let session = makeSession("s1")
            manager.testSetSessions([session])

            do {
                try await TerminalActivation.activate(
                    session: session,
                    trigger: .hotkey,
                    sessionManager: manager,
                    registry: registry
                )
                Issue.record("Expected commandFailed to propagate")
            } catch let error as TerminalBridgeError {
                if case .commandFailed = error {} else {
                    Issue.record("Unexpected TerminalBridgeError: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            #expect(manager.sessions.map(\.id) == ["s1"])
        }

        // MARK: - Highlight Trigger Matrix

        @Test @MainActor func activate_hotkey_tabEnabled_paneDisabled_sendsTabConfigOnly() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnHotkey)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnHotkey)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.count == 1)
            let (_, tabConfig, paneConfig) = try #require(highlightCalls.first)
            #expect(tabConfig != nil)
            #expect(paneConfig == nil)
        }

        @Test @MainActor func activate_hotkey_paneEnabled_tabDisabled_sendsPaneConfigOnly() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnHotkey)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnHotkey)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.count == 1)
            let (_, tabConfig, paneConfig) = try #require(highlightCalls.first)
            #expect(tabConfig == nil)
            #expect(paneConfig != nil)
        }

        @Test @MainActor func activate_hotkey_triggerDisabled_skipsHighlight() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(false, forKey: AppStorageKeys.highlightOnHotkey)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnHotkey)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.isEmpty)
        }

        @Test @MainActor func activate_guiSelect_bothEnabled_sendsBothConfigs() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnGuiSelect)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnGuiSelect)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .guiSelect, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.count == 1)
            let (_, tabConfig, paneConfig) = try #require(highlightCalls.first)
            #expect(tabConfig != nil)
            #expect(paneConfig != nil)
        }

        @Test @MainActor func activate_guiSelect_triggerDisabled_skipsHighlight() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(false, forKey: AppStorageKeys.highlightOnGuiSelect)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnGuiSelect)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .guiSelect, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.isEmpty)
        }

        @Test @MainActor func activate_notification_tabOnly_sendsTabConfigOnly() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnNotification)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnNotification)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .notification, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.count == 1)
            let (_, tabConfig, paneConfig) = try #require(highlightCalls.first)
            #expect(tabConfig != nil)
            #expect(paneConfig == nil)
        }

        @Test @MainActor func activate_notification_triggerDisabled_skipsHighlight() async throws {
            resetHighlightDefaults()
            let bridge = ActivationMockBridge()
            let registry = TerminalBridgeRegistry()
            await registry.register(bridge, for: .iterm2)

            UserDefaults.standard.set(false, forKey: AppStorageKeys.highlightOnNotification)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paneHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnNotification)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.paneHighlightEnabled)
            }

            let session = makeSession("s1")
            try await TerminalActivation.activate(session: session, trigger: .notification, registry: registry)

            let highlightCalls = await bridge.recordedHighlightCalls()
            #expect(highlightCalls.isEmpty)
        }

        @Test @MainActor func activate_highlightBridgeThrows_propagates() async {
            actor ThrowingHighlightBridge: TerminalBridge {
                func start() async throws {}
                func stop() async {}
                func activate(sessionID _: String) async throws {}
                func highlight(
                    sessionID _: String,
                    tabConfig _: HighlightConfig?,
                    paneConfig _: HighlightConfig?
                ) async throws {
                    throw MockActivationError.generic
                }

                func getSessionInfo(sessionID _: String) async throws -> TerminalSessionInfo? { nil }
            }

            resetHighlightDefaults()
            let registry = TerminalBridgeRegistry()
            await registry.register(ThrowingHighlightBridge(), for: .iterm2)

            UserDefaults.standard.set(true, forKey: AppStorageKeys.highlightOnHotkey)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.tabHighlightEnabled)
            defer {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.highlightOnHotkey)
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.tabHighlightEnabled)
            }

            let session = makeSession("s1")
            do {
                try await TerminalActivation.activate(session: session, trigger: .hotkey, registry: registry)
                Issue.record("Expected highlight error to propagate")
            } catch let error as MockActivationError {
                #expect(error == .generic)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
