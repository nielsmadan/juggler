//
//  WezTermConfigValidatorTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

@Suite("WezTermConfigValidator")
struct WezTermConfigValidatorTests {
    @Test func hasRequireLine_present() {
        #expect(WezTermConfigValidator.hasRequireLine(in: "require 'juggler_wezterm'") == true)
    }

    @Test func hasRequireLine_doubleQuotes() {
        #expect(WezTermConfigValidator.hasRequireLine(in: "require \"juggler_wezterm\"") == true)
    }

    @Test func hasRequireLine_commented() {
        #expect(WezTermConfigValidator.hasRequireLine(in: "-- require 'juggler_wezterm'") == false)
    }

    @Test func hasRequireLine_absent() {
        let config = """
        local wezterm = require 'wezterm'
        return {
            font_size = 12,
        }
        """
        #expect(WezTermConfigValidator.hasRequireLine(in: config) == false)
    }

    @Test func hasRequireLine_multiline() {
        let config = """
        local wezterm = require 'wezterm'
        require 'juggler_wezterm'
        return {}
        """
        #expect(WezTermConfigValidator.hasRequireLine(in: config) == true)
    }
}
