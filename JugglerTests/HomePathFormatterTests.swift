import Foundation
@testable import Juggler
import Testing

@Suite("HomePathFormatter")
struct HomePathFormatterTests {
    @Test func abbreviate_replacesHomeDirectory() {
        let home = NSHomeDirectory()
        #expect(HomePathFormatter.abbreviate(home) == "~")
        #expect(HomePathFormatter.abbreviate(home + "/") == "~")
    }

    @Test func abbreviate_replacesHomePrefix() {
        let home = NSHomeDirectory()
        #expect(HomePathFormatter.abbreviate(home + "/Projects/app") == "~/Projects/app")
    }

    @Test func abbreviate_leavesNearMatchUntouched() {
        let home = NSHomeDirectory()
        #expect(HomePathFormatter.abbreviate(home + "x/proj") == home + "x/proj")
    }

    @Test func abbreviate_leavesOtherPathsUntouched() {
        #expect(HomePathFormatter.abbreviate("/tmp/somewhere/proj") == "/tmp/somewhere/proj")
    }
}
