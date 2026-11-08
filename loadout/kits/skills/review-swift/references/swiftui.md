# SwiftUI review reference

Detail behind checklist §4. Read when the scoped files contain SwiftUI views.

Apple's own review lens is **Identity · Lifetime · Dependencies** (WWDC21 "Demystify SwiftUI", <https://developer.apple.com/videos/play/wwdc2021/10022>). Most SwiftUI bugs are one of those three being wrong, not a rendering problem.

## 1. Observation pairing rules (`@Observable`, iOS 17+)

All verified against Apple docs — <https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro> and <https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app>.

| Role | With `@Observable` | Legacy equivalent |
|---|---|---|
| View **owns/creates** the object | `@State private var model = Model()` | `@StateObject` |
| Object is **passed in** | plain `var model: Model` / `let model: Model` — **no wrapper** | `@ObservedObject` |
| Need bindings to its properties | `@Bindable var model: Model` | `$` on `@ObservedObject` |
| From the environment | `@Environment(Model.self) private var model`, injected with `.environment(model)` | `@EnvironmentObject` + `.environmentObject` |

Apple's decision tree (WWDC23 10149): view's own state → `@State`; global → `@Environment`; needs bindings → `@Bindable`; otherwise → plain property. "For new development, using Observable is the easiest way to get started."

Notes:
- Wrapping an `@Observable` type in `@ObservedObject`/`@StateObject` is documented as producing a compiler error — the half-migrated smell.
- `@Environment(Model.self)` is **non-optional by default and crashes if absent**. Declare the property as optional when presence isn't guaranteed. This is a sharper failure mode than `@EnvironmentObject` had.
- For an environment object you need bindings to, the pattern is `@Environment(Book.self) private var book` then `@Bindable var book = book` **inside `body`**.
- `ObservableObject` is **legacy, not deprecated** — no deprecation markers on the Combine/SwiftUI symbols. Mixing both systems during migration is explicitly endorsed. Do not raise "migrate to `@Observable`" as a review finding on existing code; raise it only for new code in a project that has already adopted it.
- Minimum: iOS/iPadOS/tvOS 17, macOS 14, watchOS 10, visionOS 1 (Swift 5.9). No back-deployment — a project with a lower floor cannot use it.

**Redraw granularity is a real, documented difference.** With `ObservableObject` a view updates when any `@Published` property changes "even if the view doesn't read the property"; with `@Observable`, updates are driven by the properties `body` actually reads. Apple states the benefit directionally ("can help improve your app's performance") — there is no published benchmark, so don't quantify it. Intermediate views that pass an object through without reading properties form **no** dependency and don't update.

## 2. Ownership mistakes worth flagging

- **`@ObservedObject` on an object the view itself creates** — recreated on every parent re-render. Real bug. (Legacy stack.)
- **`@State` on a passed-in object** — `@State` initializes once, so later values from the parent are silently ignored. Arguably the most common ownership bug post-Observation.
- **`@State` holding a *non-`@Observable`* reference type** — mutations produce no update. Note: `@State` holding an `@Observable` class is the *documented correct* pattern; do not flag reference types in `@State` generally.
- **Duplicating a source of truth into local `@State`** that then drifts from the model.
- **`@StateObject`/`@State` initialized from a value that changes** — the initializer runs once. Fix is `.id(...)` to change view identity.
- **Mismatched environment pair** — `.environmentObject(_:)` with `@Environment(T.self)`, or the reverse, resolves to nothing.
- **Missing `@ObservationIgnored`** on stored properties that shouldn't participate in tracking.
- **Expensive work in a `@State` default value or view `init`** — SwiftUI instantiates the default every time it instantiates the view, and `@State` does *not* memoize the way `@StateObject` did. "At worst, a view model gets recreated on every keypress." (<https://jaredsinclair.com/2025/09/10/observation.html>) Defer to `.task`.
- **`@EnvironmentObject`/`@Environment` used to smuggle a dependency** the view could take explicitly — an implicit dependency plus, now, a crash risk.

## 3. Identity and lifetime

- **`id: \.self` means the value's hash.** Mutating any field changes identity → state resets, lost focus. Hashes are stable within a run but **not across runs**, so they must never be persisted. (<https://www.hackingwithswift.com/books/ios-swiftui/why-does-self-work-for-foreach>)
- **Duplicate IDs don't crash in bare `ForEach`/`List`** — they silently misroute diffing. (Forum reports of a "Duplicate keys" crash exist for `List(selection:)`/`Table`; undocumented, so don't state a crisp rule.)
- **Index/offset as identity is an anti-pattern** — Apple's own `ForEach` documentation names `\.offset` as wrong and prescribes `id: \.element.id`. Note SwiftLee recommends `id: \.offset`; side with Apple. John Sundell's `IdentifiableIndices` exists specifically to avoid this (<https://www.swiftbysundell.com/articles/bindable-swiftui-list-elements>).
- **`AnyView` destroys structural identity** and erases the type information SwiftUI uses to diff. Flag it where a `@ViewBuilder`, generic, or `Group` would do.
- **`.id()` and `ForEach`'s `id:` share one rule**: changing the value destroys and recreates the view, discarding its state. Sometimes that's the intent — check which.
- **Lazy-stack row state is destroyed on scroll.** Apple, WWDC26 session 321: "When views finally are deleted from memory, state variables are deleted alongside… **don't depend on view state for data that needs to be kept alive after scrolling.** Instead, move important state to model objects, or outer views using a binding." There's a grace period ("a number of updates"), which is why this looks non-deterministic in casual testing. Scoped to `LazyVStack`/`LazyHStack` in a `ScrollView`; Apple does not make the same claim about `List`. The inverse also holds — conditional content in a leaf row can make lazy stacks retain views *longer* than expected.
- **`onAppear` has no once-only guarantee.** Apple's contract is deliberately vague: "The exact moment that SwiftUI calls this method depends on the specific view type." It re-fires on NavigationStack push/pop, and `.task` behaves the same way (<https://www.swiftjectivec.com/swiftui-run-code-only-once-versus-onappear-or-task>). With prefetching, `body` can run without `onAppear` firing at all. Flag "runs exactly once" assumptions.

## 4. Performance as judgment

- **Expensive work in `body`** — `body` runs often and unpredictably. Inline `.filter()`/`.sorted()` in a `ForEach` argument re-runs on every update.
- **Over-broad observation** — a view reading a whole model to display one field redraws on unrelated changes. With `@Observable` the fix is usually to read less; with `ObservableObject` it's to split the object.
- **`.equatable()` / `EquatableView`** — SwiftUI does not reliably call your `==` unless you explicitly apply `.equatable()`. This is **reverse-engineered community knowledge**, consistent across three named authors from 2019 to 2025 (swiftui-lab, Donny Wals, Fatbobman) — never present it as documented Apple behavior. Apple's current guidance is to split views by independently-updating data rather than reach for `equatable()`.

## 5. What tooling already catches

Xcode surfaces some of this at runtime rather than compile time — "Accessing StateObject's object without being installed on a View", "Publishing changes from within view updates". Those are runtime purple warnings, not review findings. SwiftLint has no property-wrapper-ownership rules, so everything in §2 is genuinely yours.
