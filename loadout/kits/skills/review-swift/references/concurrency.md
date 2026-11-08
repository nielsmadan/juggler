# Concurrency review reference

Detail behind checklist §3. Read when the scoped files touch actors, `Sendable`, `@MainActor`, or `Task`.

Authority tags: **[OFFICIAL]** swift.org docs / swift-evolution / TSPL · **[APPLE-FORUM]** identified Swift-team member on forums.swift.org · **[COMMUNITY]** named credible author.

## 0. You cannot review isolation without the module's build settings

Since Swift 6.2, the *same source text* means different things depending on per-module flags. Establish these before reviewing, and say so in the Baseline line if you can't:

| Setting | Spelling | Effect |
|---|---|---|
| Default actor isolation (SE-0466) | `-default-isolation MainActor`, or SwiftPM `SwiftSetting.defaultIsolation(MainActor.self)` (needs `// swift-tools-version: 6.2`) | Unannotated declarations become `@MainActor`. Default when absent is `nonisolated`. |
| Nonisolated-nonsending default (SE-0461) | upcoming feature `NonisolatedNonsendingByDefault` | `nonisolated async` funcs run **on the caller's actor** instead of hopping off. |
| Isolated conformances (SE-0470) | upcoming feature `InferIsolatedConformances` | `class C: @MainActor Equatable` — removes the old `nonisolated` + `assumeIsolated` boilerplate. |
| Language mode | `swiftLanguageMode(.v6)` / `SWIFT_VERSION` | Turns data-race diagnostics from warnings into errors. |
| Strict concurrency (Swift 5 mode) | `-strict-concurrency=complete` / `SWIFT_STRICT_CONCURRENCY` | Complete checking without language mode 6. |

Massicotte's framing of why this matters: given `var global = 42`, "Does this compile with Swift 6.2 in the 6 language mode? **This question is unanswerable.**" **[COMMUNITY]** — <https://www.massicotte.org/default-isolation-swift-6_2>

SE-0466 gives the official steer on *where* main-actor-by-default belongs: it was deliberately not made a language default because "`MainActor` isolation is the wrong default for many kinds of modules, including libraries that offer APIs that can be used from any isolation domain, and highly-concurrent server applications." **[OFFICIAL]** So: reasonable for an app/executable target, a finding for a library or server target.

Xcode surfaces this as an "Approachable Concurrency" build setting. The identifier `SWIFT_APPROACHABLE_CONCURRENCY` is corroborated by credible blogs but **not** by an Apple primary source; the Default Actor Isolation setting's identifier is unverified. Don't cite either string as fact — check the project.

## 1. Do NOT over-flag `@MainActor`

The common review instinct ("this is over-annotated, it'll hurt performance") runs against official guidance. The Migration Guide **[OFFICIAL]**:

> "Lack of `MainActor` isolation like this is, by far, the most common form of latent isolation. It is also very common for developers to hesitate to use this as a solution. **It is completely normal for programs with a user interface to have a large set of `MainActor`-isolated state.** Concerns around long-running *synchronous* work can often be addressed with just a handful of targeted `nonisolated` functions."

No official source warns against broadly applying `@MainActor`. The real defect is **blocking** the main actor with long synchronous work — a different finding. John McCall corrects the related myth **[APPLE-FORUM]**: "Swift concurrency does not schedule other work onto the main thread just because it's currently available. If you have a long-running operation that's blocking the main thread, it's because you ran it there."

David Smith's escalation ladder, worth applying before recommending any offloading **[APPLE-FORUM]**: "Have you verified that there's actually a problem? 'Just do it synchronously' works remarkably often, and 'async but on the main actor' covers a surprisingly large chunk of the rest… **Fast is almost always superior to slow-but-async**… Having verified that you really do need to be async: do you need to be *parallel*?"

Also: `nonisolated` alone is **not** an unsafe keyword and shouldn't be reviewed as one. Only `@unchecked` and `nonisolated(unsafe)` suppress checking.

## 2. Actor reentrancy — the highest-value compiler blind spot

SE-0306 **[OFFICIAL]**: "actor-isolated state can change across an `await` when an interleaved task mutates that state, meaning that **developers must be sure not to break invariants across an await**." Reentrant actors "are *thread-safe* but are not automatically protecting from the 'high level' kinds of races."

The official prescription: "the easiest way to avoid breaking invariants across an `await` is to **encapsulate state updates in synchronous actor functions**. Effectively, **synchronous code in an actor provides a critical section, whereas an `await` interrupts a critical section**." The Migration Guide restates it under "Atomicity": "**Critical sections should always be structured to run synchronously.**"

Explicitly out of scope for the compiler — the Language Steering Group's approachable-concurrency vision lists "task ordering and actor re-entrancy" under "What's not in this vision." **[OFFICIAL]**

**Review technique:** at every `await` inside actor-isolated or `@MainActor` code, ask what state was read *before* it and reused *after*. Three shapes: check-then-act, read-modify-write, and set-a-flag-after-awaiting.

Canonical example — Donny Wals **[COMMUNITY]** (<https://www.donnywals.com/actor-reentrancy-in-swift-explained>): an actor cache whose `read` checks a dict, `await`s a fetch, then writes back. Five concurrent reads → five network requests. Fix: store the in-flight `Task` itself so later callers await the same one.

## 3. Task lifetime, isolation, cancellation

**Isolation inheritance** — TSPL **[OFFICIAL]**: `Task.init` "defaults to running with the same actor isolation, priority, and task-local state as the current task"; `Task.detached` "defaults to running without any actor isolation and doesn't inherit the current task's priority or task-local state."

**The 6.2 trap** — SE-0461 **[OFFICIAL]**: "**Unstructured tasks created in nonisolated functions never run on an actor unless explicitly specified.**" So under `NonisolatedNonsendingByDefault`, a `nonisolated async` function runs on the caller's actor, but a `Task {}` it creates does **not** inherit that actor. New in 6.2 and easy to miss.

**Cancellation is not inherited and is cooperative.** John McCall **[APPLE-FORUM]**: "structured sub-tasks are automatically cancelled when the parent task is cancelled, so if you want this automatic cancellation behavior with unstructured tasks, **you'll have to do it yourself**." SE-0304 **[OFFICIAL]**: "cancellation has no effect at all unless something checks for cancellation." An unstructured task retains everything it captured until it completes.

`Task { [weak self] in guard let self else { return } }` is a **no-op** — `Task.init` is `@_implicitSelfCapture`, and re-binding strongly at the top defeats the weak capture. **[COMMUNITY]** <https://www.donnywals.com/how-to-use-weak-self-in-swift-concurrency-tasks/>

`try? await Task.sleep(...)` swallows `CancellationError` — a common way cancellation silently stops propagating.

In `deinit`, capturing `self` in a `Task` is "critical" to avoid — use an explicit capture list. **[OFFICIAL]**

**`@concurrent` (6.2) is the modern idiom for offloading**, replacing `Task.detached`. It implies `nonisolated`; combining it with `@MainActor`, an `isolated` parameter, or applying it to a synchronous function is an error. SE-0461 predicts it "will likely be used sparingly because it has far stricter data-race safety requirements."

## 4. `@unchecked Sendable` and `nonisolated(unsafe)`

Migration Guide **[OFFICIAL]**: "**most types are not inherently thread-safe. As a general rule, if a type isn't already thread-safe, attempting to make it `Sendable` should not be your first approach.**" And for `nonisolated(unsafe)`: "Only use `nonisolated(unsafe)` when you are carefully guarding all access to the variable with an external synchronization mechanism such as a lock or dispatch queue."

**Legitimate:** the type already does correct manual synchronization (lock, serial queue, `Mutex`) that the compiler can't see.
**Smell:** reached for because a warning appeared, on a type with no synchronization.

**Prefer scoping the escape hatch to the property, not the type** — this is the officially-shown composition and a strong review recommendation, since `@unchecked` on the type disables checking for *everything* in it:

```swift
final class Style: Sendable {
    private nonisolated(unsafe) var background: ColorComponents  // guarded by queue
    private let queue: DispatchQueue
    @MainActor private var foreground: ColorComponents
}
```

A class gets a *checked* `Sendable` conformance if it is `final`, inherits from nothing but `NSObject`, and has no non-isolated mutable properties — so `@unchecked` on a class that could just be `final` + all-`let` is pure noise.

Retroactive `@unchecked Sendable` on someone else's type warrants "extreme caution" **[OFFICIAL]**; prefer `@preconcurrency import` while waiting for the library. **[COMMUNITY]**

Massicotte **[COMMUNITY]**: "Needing lots of stuff to be `Sendable` is usually a sign you have too many isolation boundaries."

## 5. Design smells (Massicotte, <https://www.massicotte.org/problematic-patterns>) **[COMMUNITY]**

Best-maintained concurrency checklist that exists; updated 2026.

- **Stateless actors** — "the purpose of an actor is to protect mutable state… I regularly run into actors that have no instance properties." If the goal is just getting work off the main thread, use a nonisolated async function or `@concurrent`.
- **Split isolation** — a type with some nonisolated and some `@MainActor` properties. "the vast majority of the time, a global actor should be applied to the type as a whole, not to individual properties."
- **`MainActor.run`** — "rarely the right solution… why do `await MainActor.run { doMainActorStuff() }` when `await doMainActorStuff()` will usually work?" The Migration Guide agrees **[OFFICIAL]**: it "should not be used as a substitute for expressing the isolation requirements of your system statically."
- **`MainActor.assumeIsolated`** — **[OFFICIAL]** "use this approach only as a temporary solution, and only when you have exhausted other options." In 6.2+ code, `assumeIsolated` inside a protocol conformance is a finding — isolated conformances (SE-0470) replace it.
- **Actors conforming to protocols with synchronous requirements** — usually a sign the actor is the wrong tool.
- **Blocking for async work** — `DispatchSemaphore`/`DispatchGroup` waiting on async work: "you are eventually going to deadlock."
- **Explicit priorities** — "always include a comment explaining why the default won't work."
- **Unstructured where structured would work** — structured "allows some automatic cancellation support, and encourages you to define your isolation requirements statically."
- Rob Napier's mental model for `Task {}` ordering: pretend every `Task {}` begins with a random multi-second sleep.

## 6. What the compiler already catches — do not report these

In Swift 6 language mode / `-strict-concurrency=complete` **[OFFICIAL]**: non-`Sendable` values crossing isolation boundaries (SE-0302/0414/0430); non-isolated global and static mutable state (SE-0412); actor-isolated state accessed from another domain (SE-0306); isolated method satisfying a `nonisolated` protocol requirement; actor-isolated calls in `deinit`; actor-isolated default values in non-isolated contexts; non-`Sendable` captures in `@Sendable` closures; non-`Sendable` stored properties in `Sendable` types; global-actor conflicts (SE-0461).

Region-based isolation is **flow-sensitive** — the compiler can prove a specific instance safe to send, then reject the same code once a later use is added. "This compiled yesterday" usually means a new downstream use, not a compiler bug.

SwiftLint additionally covers `async_without_await`, `incompatible_concurrency_annotation`, `redundant_sendable`, `unhandled_throwing_task` — so redundant `Sendable` conformances and ignored throwing tasks are lint findings, not review findings.

**What nothing catches** (i.e. your job): actor reentrancy and high-level races; task ordering between unstructured tasks; whether a `Task` is ever cancelled or leaks captures; the correctness of `@unchecked Sendable` / `nonisolated(unsafe)`; the semantic correctness of `assumeIsolated` (a runtime precondition, not a proof); blocking the main actor with sync work; deadlock and priority inversion; incorrectly-annotated ObjC/C imports (the compiler trusts the annotation — the Migration Guide shows code that "will compile without issue but crash at runtime"); a missing `@Sendable` on a third-party escaping closure causing wrong `@MainActor` inference.

## Version notes

Swift 6.2 (Sep 2025) carries everything above. Swift 6.3 (Mar 2026) added `weak let` (SE-0481) — an explicit `weak` capture is now immutable, which removes a common reason for `@unchecked Sendable`. Swift 6.4 is **in development, not released** as of July 2026; treat `~Sendable` (SE-0518), `withTaskCancellationShield` (SE-0504), the `Continuation` type (SE-0528), and async `defer` (SE-0493) as forward-looking, not as things to require.
