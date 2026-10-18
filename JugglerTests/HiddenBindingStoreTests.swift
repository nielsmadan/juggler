import Foundation
@testable import Juggler
import Testing

@Suite("HiddenBindingStore")
struct HiddenBindingStoreTests {
    private let hiddenAt = TestFixtures.date("2026-09-04T12:00:30Z")
    private let before = TestFixtures.date("2026-09-04T12:00:00Z")
    private let after = TestFixtures.date("2026-09-04T12:01:00Z")

    @Test func aHiddenBindingHidesRecordsObservedUpToItsHiding() {
        let store = HiddenBindingStore(defaults: TestDefaults.fresh())
        store.hide(["b1"], at: hiddenAt)

        #expect(store.hides("b1", observedAt: before))
        #expect(store.hides("b1", observedAt: hiddenAt))
    }

    @Test func aRecordObservedAfterTheHidingIsShown() {
        let store = HiddenBindingStore(defaults: TestDefaults.fresh())
        store.hide(["b1"], at: hiddenAt)

        #expect(store.hides("b1", observedAt: after) == false)
    }

    @Test func anUnhiddenBindingIsShown() {
        let store = HiddenBindingStore(defaults: TestDefaults.fresh())
        store.hide(["b1"], at: hiddenAt)

        #expect(store.hides("b2", observedAt: before) == false)
    }

    @Test func aRecordWithoutAReadableTimeStaysHidden() {
        let store = HiddenBindingStore(defaults: TestDefaults.fresh())
        store.hide(["b1"], at: hiddenAt)

        #expect(store.hides("b1", observedAt: nil))
    }

    @Test func revealShowsOnlyThatBinding() {
        let store = HiddenBindingStore(defaults: TestDefaults.fresh())
        store.hide(["b1", "b2"], at: hiddenAt)

        store.reveal("b1")

        #expect(store.hides("b1", observedAt: before) == false)
        #expect(store.hides("b2", observedAt: before))
    }

    @Test func hiddenBindingsPersistAcrossStoreInstances() {
        let defaults = TestDefaults.fresh()
        HiddenBindingStore(defaults: defaults).hide(["b1"], at: hiddenAt)

        let reloaded = HiddenBindingStore(defaults: defaults)

        #expect(reloaded.hides("b1", observedAt: before))
    }

    @Test func pruneKeepsOnlyTheListedBindings() {
        let defaults = TestDefaults.fresh()
        let store = HiddenBindingStore(defaults: defaults)
        store.hide(["b1", "b2"], at: hiddenAt)

        store.prune(keeping: ["b2", "b3"])

        let reloaded = HiddenBindingStore(defaults: defaults)
        #expect(reloaded.hides("b1", observedAt: before) == false)
        #expect(reloaded.hides("b2", observedAt: before))
    }

    @Test func revealAllShowsEveryBinding() {
        let defaults = TestDefaults.fresh()
        let store = HiddenBindingStore(defaults: defaults)
        store.hide(["b1", "b2"], at: hiddenAt)

        store.revealAll()

        let reloaded = HiddenBindingStore(defaults: defaults)
        #expect(reloaded.hides("b1", observedAt: before) == false)
        #expect(reloaded.hides("b2", observedAt: before) == false)
    }
}
