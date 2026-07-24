import Foundation
@testable import Juggler
import Testing

@Suite("TestInstanceConfig")
struct TestInstanceConfigTests {
    private func defaults(_ pairs: [String: Any]) -> UserDefaults {
        let suite = "TestInstanceConfigTests-\(abs(pairs.keys.joined().hashValue))"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in pairs {
            defaults.set(value, forKey: key)
        }
        return defaults
    }

    @Test func hookPortOverride_isNilWhenAbsent() {
        #expect(TestInstanceConfig.hookPortOverride(defaults([:])) == nil)
    }

    @Test func hookPortOverride_returnsValueWhenSet() {
        #expect(TestInstanceConfig.hookPortOverride(defaults(["hookPort": 7484])) == 7484)
    }

    @Test func hookPortOverride_isNilWhenOutOfRange() {
        #expect(TestInstanceConfig.hookPortOverride(defaults(["hookPort": 0])) == nil)
        #expect(TestInstanceConfig.hookPortOverride(defaults(["hookPort": 70000])) == nil)
    }

    @Test func hookPort_defaultsTo7483() {
        #expect(TestInstanceConfig.hookPort(defaults([:])) == 7483)
    }

    @Test func hookPort_usesOverrideWhenSet() {
        #expect(TestInstanceConfig.hookPort(defaults(["hookPort": 7484])) == 7484)
    }

    @Test func daemonSocketFilename_isDefaultWhenNoOverride() {
        #expect(TestInstanceConfig.daemonSocketFilename(defaults([:])) == "iterm2_daemon.sock")
    }

    @Test func daemonSocketFilename_isIsolatedWhenOverride() {
        #expect(TestInstanceConfig.daemonSocketFilename(defaults(["hookPort": 7484])) == "iterm2_daemon_7484.sock")
    }
}
