//
//  ConfigValidatorTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

// MARK: - KittyConfigParser Tests

@Test func kittyConfig_remoteControl_socketOnly() {
    #expect(KittyConfigParser.hasRemoteControl(in: "allow_remote_control socket-only") == true)
}

@Test func kittyConfig_remoteControl_yes() {
    #expect(KittyConfigParser.hasRemoteControl(in: "allow_remote_control yes") == true)
}

@Test func kittyConfig_remoteControl_commented() {
    #expect(KittyConfigParser.hasRemoteControl(in: "# allow_remote_control yes") == false)
}

@Test func kittyConfig_remoteControl_no() {
    #expect(KittyConfigParser.hasRemoteControl(in: "allow_remote_control no") == false)
}

@Test func kittyConfig_remoteControl_absent() {
    #expect(KittyConfigParser.hasRemoteControl(in: "font_size 12\nsome_other_setting yes") == false)
}

@Test func kittyConfig_remoteControl_multiline() {
    let config = """
    font_size 12
    # allow_remote_control yes
    allow_remote_control socket-only
    background #000000
    """
    #expect(KittyConfigParser.hasRemoteControl(in: config) == true)
}

@Test func kittyConfig_listenOn_present() {
    #expect(KittyConfigParser.hasListenOn(in: "listen_on unix:/tmp/kitty-{kitty_pid}") == true)
}

@Test func kittyConfig_listenOn_commented() {
    #expect(KittyConfigParser.hasListenOn(in: "# listen_on unix:/tmp/kitty") == false)
}

@Test func kittyConfig_listenOn_absent() {
    #expect(KittyConfigParser.hasListenOn(in: "font_size 12") == false)
}

@Test func kittyConfig_watcher_present() {
    #expect(KittyConfigParser.hasWatcher(in: "watcher juggler_watcher.py") == true)
}

@Test func kittyConfig_watcher_absent() {
    #expect(KittyConfigParser.hasWatcher(in: "font_size 12") == false)
}

// MARK: - TmuxConfigValidator Tests

@Test func tmuxConfig_configured_withItermVar() {
    let config = "set-option -ga update-environment ' ITERM_SESSION_ID'"
    #expect(TmuxConfigValidator.isConfigured(contents: config) == true)
}

@Test func tmuxConfig_configured_withKittyVar() {
    let config = "set-option -ga update-environment ' KITTY_WINDOW_ID'"
    #expect(TmuxConfigValidator.isConfigured(contents: config) == true)
}

@Test func tmuxConfig_notConfigured_noUpdateEnvironment() {
    #expect(TmuxConfigValidator.isConfigured(contents: "set-option -g default-terminal screen") == false)
}

@Test func tmuxConfig_notConfigured_noTerminalVars() {
    #expect(TmuxConfigValidator.isConfigured(contents: "set-option -ga update-environment ' FOO'") == false)
}

@Test func tmuxConfig_empty() {
    #expect(TmuxConfigValidator.isConfigured(contents: "") == false)
}
