---
name: review-swift
description: Swift-specific code review focused on JUDGMENT-level design a linter and the compiler can't decide — state modeling with enums and value types (make invalid states unrepresentable), optional and error modeling, concurrency isolation intent, ARC ownership, SwiftUI identity/lifetime/dependencies, and escape hatches (`!`, `as!`, `try!`, `@unchecked Sendable`) that compile but hide a modeling problem. Deliberately does NOT duplicate SwiftLint, swift-format, or Swift 6 strict-concurrency diagnostics. Auto-invoked by `code-review` on Swift projects. Triggers "review swift", "swift review", "swift concurrency review".
argument-hint: '[--staged | --unpushed | --changed | --all | --multi]'
effort: high
---

# Review Swift

Swift review that covers what **the compiler and SwiftLint cannot decide for you** — how state is *modeled*, whether optionals and errors carry the right information, whether isolation and ownership reflect real intent, and whether an escape hatch is papering over a design problem.

Run on `.swift` files. Complements `review-cleancode` (SOLID/DRY/smells) — don't repeat it.

## Review grading

Use only these finding priorities, in descending order:

- **Critical Issues (Must Fix):** a verified path causes data loss, a security failure, a materially
  wrong operation, or makes a core workflow unusable without reasonable recovery.
- **Improvements (Should Fix):** an ordinary supported workflow demonstrably fails or repeatedly
  imposes substantial friction, or a concrete design defect creates meaningful maintenance cost.
- **Suggestions (Nice to Have):** a worthwhile improvement with small practical impact, including
  optional polish, local simplification, and rare recoverable edge cases.

Grade the demonstrated consequence, realistic reachability, and available recovery against project
priorities. A category, missing convention, hypothetical future problem, or confidence that a claim
is true does not set its priority. Do not assign automatic severity floors or ceilings. Keep
unverified claims in validation gaps, outside the graded finding count; distinguish suggestions
from defects. For plans, trace the consequence if implemented and state the assumptions.

Use the short labels **Must Fix**, **Should Fix**, and **Nice to Have** in summaries and ledgers.
Keep effort, verification status, user-facing change size, and tool/vendor diagnostic ratings
separate. When called by `code-review`, return its requested evidence and impact fields; the parent
owns scoring and final triage. Otherwise apply this rubric directly. Omit empty priority sections.

## Relationship to the toolchain (read first)

Three layers already cover the mechanical work. Your job is what's left.

**1. The compiler.** In Swift 6 language mode (or `-strict-concurrency=complete`), data-race safety is *enforced*: non-`Sendable` values crossing isolation boundaries, non-isolated global/static mutable state, actor state accessed from another domain, `deinit` isolation, `@Sendable` closure captures. Never report these as review findings when that mode is on.

**2. SwiftLint — but check what's actually enabled.** Many safety-relevant rules are **opt-in**, so in a default config they do *not* run. Verified against SwiftLint 0.55.1 (`swiftlint rules`):

| Rule | Opt-in? |
|---|---|
| `force_cast`, `force_try` | **on by default** |
| `identifier_name`, `type_name`, `line_length`, `function_body_length`, `type_body_length`, `cyclomatic_complexity` | on by default |
| `redundant_void_return`, `redundant_optional_initialization` | on by default |
| `force_unwrapping`, `implicitly_unwrapped_optional` | **opt-in** |
| `unowned_variable_capture`, `weak_delegate`, `strong_iboutlet` | **opt-in** |
| `first_where`, `last_where`, `contains_over_filter_count`, `empty_count`, `toggle_bool` | opt-in |
| `discouraged_optional_boolean`, `discouraged_optional_collection`, `redundant_type_annotation` | opt-in |
| `unhandled_throwing_task` | opt-in |

Recent SwiftLint versions add `async_without_await`, `incompatible_concurrency_annotation`, `redundant_sendable`, and rename some rules. **Read the project's `.swiftlint.yml` rather than assuming** — suppress a mechanical finding only if that project actually runs the rule. If it doesn't, fold it into the one-time recommendation below instead of reporting it per-occurrence.

SwiftLint has **no** SwiftUI property-wrapper or ownership rules, so all of §4 is yours.

**3. Xcode runtime diagnostics** catch some SwiftUI misuse at runtime (off-main-thread `ObservedObject`/`StateObject` mutation, cross-actor `Binding` access, `StateObject` accessed without being installed on a view). These are runtime issues, not review findings. Note they reportedly have **no `@Observable` equivalent** — so migrating to `@Observable` loses that safety net, which makes §4 review *more* important, not less.

**The baseline read is a silencer, not a finding.** Read the config so you don't report what a rule already covers. *Recommending* a lint or language-mode change is a project-level action — see §P — and belongs in an `--all` audit, not a diff review.

SwiftUI presentation, accessibility, adaptive layout, navigation, localization, and native
window/command interaction belong to `review-swiftui`. Keep state ownership, identity,
lifetime, dependencies, and rendering cost here; do not repeat the UI review.

## What this skill checks

**Swift design decisions are made once; the ways they get violated recur with every change.** So the default review looks only at what the diff introduces — a new struct whose fields are correlated, a new `!` on external data, a new `Task` with no owner, a new `@State` holding a passed-in object. Whole-module properties (is SwiftLint configured, is the target on Swift 6 mode, is the `public` surface coherent) belong to **§P**, which runs at `--all` and nowhere else.

## Usage

```
/review-swift                  # Review context-related code
/review-swift --staged         # Review staged changes
/review-swift --unpushed       # Review files changed across all unpushed commits
/review-swift --changed        # Review unstaged changes
/review-swift --all            # Full codebase audit (parallel agents)
/review-swift --multi          # Also get external advisor opinions
```

## Scope

| Flag | Scope | Method |
|------|-------|--------|
| (none) | Context-related code | Files from the current conversation context. If no context, ask the user to specify files or use `--staged`/`--changed`/`--all`. |
| `--staged` | Staged changes | `git diff --cached --name-only` |
| `--unpushed` | Files changed across unpushed commits | `git diff --name-only $(git rev-list HEAD --not --remotes \| tail -1)^..HEAD` |
| `--changed` | Unstaged changes | `git diff --name-only` |
| `--all` | Full codebase + **§P project-level checks** | Glob `*.swift`, parallel agents |
| `--multi` | Add external opinions | Combines with any scope above; invokes `second-opinion --quick` |

`--unpushed` derives its range from `git rev-list HEAD --not --remotes` (oldest unpushed commit's parent → HEAD). If nothing is unpushed, or there is no remote/upstream (or the range walks back to the root commit) so it can't be determined reliably, stop and ask the user to pick another scope. Restrict the resolved file list to `.swift` before reviewing.

## Workflow

1. **Determine scope** (see table) and filter to Swift files only.
2. **Read CLAUDE.md** in the repo root for project conventions.
3. **Establish the baseline — do this before reading any code.** Since Swift 6.2 the same source text means different things depending on per-module settings, so isolation is *unreviewable* without them. Check:
   - **Language mode / strict concurrency** — `Package.swift` (`swiftLanguageMode(.v6)`, `.enableUpcomingFeature`, `.unsafeFlags`) or Xcode's `SWIFT_VERSION` / `SWIFT_STRICT_CONCURRENCY`.
   - **Default actor isolation** — `-default-isolation MainActor` / `SwiftSetting.defaultIsolation(MainActor.self)` (SE-0466). If on, *unannotated* code is `@MainActor` and your default reading inverts.
   - **`NonisolatedNonsendingByDefault`** (SE-0461) — changes where `nonisolated async` functions run.
   - **`.swiftlint.yml`** — which rules actually run.
   - Mixed-mode workspaces are common (a package on v6, the app target on v5). If genuinely ambiguous, review concurrency as if strict checking is **off** (more findings) and say so in the Baseline line.
4. **Review each file** against the categories below — against what the diff introduces. Add **§P only at `--all`**. Load the matching reference file when the code touches that area.
5. **Parallelize** if scope has >5 files: one sub-agent per category, merge and dedupe.
6. **External opinions** (if `--multi`): invoke `second-opinion --quick` with this prompt:

   ```
   Read-only Swift review. Assume SwiftLint and the Swift compiler already handle mechanical rules — do NOT repeat lint-level or plain compiler-diagnostic findings. Focus on DESIGN judgment: are invalid states representable that should be modeled away with an enum + associated values? Are structs/classes chosen for the right semantics? Do optionals and error types carry the information callers need, or is failure flattened to nil? Does isolation reflect real ownership? Are there state assumptions across an `await` inside an actor? Do any `!`, `as!`, `try!`, `@unchecked Sendable`, or `nonisolated(unsafe)` hide a wrong upstream type or an unchecked invariant? 300 words or less.
   ```

   Wait for all external results before proceeding.
7. **Classify severity** and **report**, grouped by severity.

## Checklist (judgment only)

### 1. State & type modeling

The core value. The compiler checks that types are *consistent*; only a human checks that they're *right*.

- **Invalid states are representable.** `struct LoadState { var isLoading: Bool; var value: T?; var error: Error? }` permits loading-with-value-and-error. Recommend an `enum` with associated values (`case idle, loading, loaded(T), failed(Error)`) so illegal states won't compile. Swift's single highest-leverage modeling move.
- **Bag-of-optionals instead of an enum** — a struct where "if `kind == .circle` then `radius` is set" is enforced by convention, not by the type.
- **Value vs. reference semantics chosen by habit.** A `class` holding inert data with no identity or shared mutation should be a `struct`; a `struct` whose copies silently diverge where callers assume one shared instance is the reverse bug. Watch the leak: a struct holding a class has value semantics only at the top level.
- **Stringly-typed and in-band sentinels.** Raw `String`/`Int` where an enum or wrapper type prevents mix-ups; `-1`/`""`/`0` overloaded to mean "none"; interchangeable `String` IDs swappable at a call site. Recommend wrapper types only where mix-ups are a real risk — note the ergonomic cost.
- **Types wider than callers need** — `[Item]?` where "possibly empty" suffices; `Any`/`[String: Any]` at an internal boundary. Liberal in inputs, strict in outputs.
- **`static var` is global mutable state** — prefer `static let` or a computed property.
- **`switch` with `default` over an enum you own** — enumerating cases forces every site to be reconsidered when a case is added.
- **Access control as design.** `public`/`open` surface that leaks internal types or was public by default rather than by decision; `internal` mutable state that should be `private(set)`.
- **Naming, per the Swift API Design Guidelines** — only where it genuinely misleads, not as a style sweep. Real rules: mutating/non-mutating pairs (`sort()`/`sorted()`, `stripNewlines()`/`strippingNewlines()`, `union`/`formUnion`); non-mutating methods read as **noun phrases** (`x.distance(to: y)`); factory methods begin with `make`; argument labels form a phrase at the call site. **There is no "don't prefix with `get`" rule** — it isn't in the guidelines; don't flag it.
- **Docs as a design signal** — "If you struggle to describe an API simply, you may have designed the wrong API." Also flag undocumented computed properties that aren't O(1).

### 2. Optionals & error modeling

- **Optional as a silent failure channel.** `T?` where the caller needs to know *why* it failed should `throw` or return `Result`.
- **Nested/double optionals and optional-of-collection** — `[Item]??`, or `[Item]?` where empty already means empty.
- **Optionality scattered through the interior** instead of normalized at the perimeter (decoding, network, DB), so interior code deals in non-optional values.
- **Error types that erase information** — a `catch` mapping every failure to one generic case, or an API throwing untyped `Error` where callers must string-match.
- **Typed throws: ask whether it's *justified*, not whether it's missing.** SE-0413 is explicit that "the existing (untyped) `throws` remains the better default error-handling mechanism for most Swift code," and warns: "Resist the temptation to use typed throws because there is only a single kind of error that the implementation can throw." The three sanctioned cases are within-module/package implementation detail, generic code passing errors through, and constrained/embedded environments. Flag *unjustified* `throws(SomeError)` on an evolving API — it constrains future implementations.
- **Swallowed errors** — `try?` discarding a failure that mattered, empty `catch {}`. Distinguish "genuinely don't care" from "lost the diagnostic".
- **Assertion ladder** — `assert` + logging when recoverable; `precondition`/`fatalError` when not; `fatalError` specifically when the message is dynamic (`precondition` won't surface one in the crash log). `assert` compiles out in release, so an `assert` guarding an invariant that matters in production is a finding.
- **Codable design** — all-or-nothing array decoding, raw-value enums that fail on unknown values, partial `CodingKeys` silently dropping fields, `try?` erasing `DecodingError`, and whether `init(from:)` validates or merely parses. See `references/memory-and-performance.md` §4.

### 3. Concurrency & isolation intent

**Load `references/concurrency.md` when reviewing this area** — it carries the version matrix, the official quotes, and the full pattern catalogue.

The essentials:

- **Do not flag broad `@MainActor` application.** Official guidance runs the other way: "It is completely normal for programs with a user interface to have a large set of `MainActor`-isolated state," and under-isolation is called the most common latent problem. The real defect is **blocking** the main actor with long synchronous work. `nonisolated` alone is not an unsafe keyword.
- **State assumptions across an `await`** inside actor-isolated or `@MainActor` code — the highest-value blind spot, explicitly out of scope for the compiler. Check-then-act, read-modify-write, and set-a-flag-after-awaiting are the three shapes.
- **`@unchecked Sendable` / `nonisolated(unsafe)` as silencers** rather than as documented proof obligations over real synchronization. Prefer scoping the hatch to one property over disabling checking for the whole type.
- **Unstructured `Task` with no lifetime owner** — nothing stores or cancels it. Cancellation is neither inherited nor automatic, and is cooperative (nothing happens unless something checks). `Task { [weak self] in guard let self else { return } }` is a no-op.
- **Design smells** — stateless actors, split isolation (some properties `@MainActor`, some not), `MainActor.run` where `await` suffices, `assumeIsolated` in new 6.2+ code, `DispatchSemaphore` blocking on async work.

### 4. SwiftUI — identity, lifetime, dependencies

**Load `references/swiftui.md`** for the full pairing table and identity rules. Apple's own lens is Identity · Lifetime · Dependencies.

- **Ownership is the judgment; the property wrapper is downstream of it.** With `@Observable`: `@State` for the object the view *creates*, a plain property for one *passed in*, `@Bindable` for bindings, `@Environment(T.self)` from the environment. **`@State` holding an `@Observable` class is the documented correct pattern** — flag it only for a *non-`@Observable`* reference type, or for a *passed-in* object (which `@State` will silently pin to its first value).
- **Duplicated source of truth** copied into local `@State` that then drifts.
- **`@ObservedObject` on a view-created object** (legacy stack); `@ObservedObject`/`@StateObject` wrapping an `@Observable` type (half-migrated).
- **Expensive work in `@State` defaults or view `init`** — `@State` does not memoize the way `@StateObject` did.
- **Identity churn** — `AnyView` destroying structural identity, `id: \.self` (a hash — mutating any field resets state), index/offset as identity, unstable `.id()`.
- **Lifetime assumptions** — lazy-stack row `@State` is destroyed on scroll (Apple: "don't depend on view state for data that needs to be kept alive after scrolling"); `onAppear` has no once-only guarantee.
- **Do not raise "migrate to `@Observable`"** on existing code — `ObservableObject` is legacy, not deprecated, and mixing is endorsed.

### 5. ARC & ownership

**Load `references/memory-and-performance.md`** for the full treatment.

- **A cycle exists only when the callee retains the closure.** A closure stored as a property of the object it captures is a cycle; the same closure in `asyncAfter` is fine strong — and marking it `weak` there is silently broken. Ask who retains whom, not "is there a `[weak self]`".
- **Method references used as closures** (`self.handler = doThing`) create cycles the compiler does not diagnose.
- **Delegates** — ask who owns the object. `weak` is wrong for a helper the object created.
- **Over-use of `weak` is itself a defect** — "actively harmful to use weak references in places where they aren't needed."
- **`unowned` is contested and not faster** — decide on lifetime semantics, never performance.
- **Capture lists snapshot value types** at creation, a silent staleness bug when later mutation is expected.

### 6. Escape hatches — the judgment residue

Lint flags the *presence* of `!`, `as!`, `try!` (when enabled). What's left:

- **A force-unwrap that compiles but hides a wrong upstream type.** `URL(string: endpoint)!` because `endpoint` is a `String` that should have been a `URL` three layers up. The fix is upstream. Highest-value finding here.
- **`as!` / `as?` standing in for a modeling gap** — a downcast off `Any` or an untyped dictionary means the container type is wrong. Say what the right type is.
- **A force-unwrap or `try!` at a trust boundary** — decoding, network payloads, `Bundle` resources, `UserDefaults`. Distinguish from a genuinely-safe unwrap of a compile-time-known literal.
- **`fatalError`/`preconditionFailure` on a reachable path** — fine for programmer error, a production crash when the "impossible" case is external input.
- **IUOs surviving past initialization** — used as ordinary storage rather than as a two-phase-init workaround.
- **`@retroactive` conformances** — two modules doing it conflict at runtime.

State your reasoning. "Force-unwrap hides that `configURL` is modeled as `String?` when it's always a valid URL" is a finding; "there's a force-unwrap here" is not.

### Conditional: noncopyable types

`~Copyable`, `borrowing`/`consuming` (Swift 5.9+) are genuinely niche — file handles, locks, once-only operations. One question at most: *does this represent a resource that must not be duplicated?* Treat unexplained `borrowing`/`consuming` on ordinary copyable code as noise; SE-0377 notes adding or removing them "does not have any source-breaking effects," so they're performance annotations, not contracts. No authoritative review guidance exists for macros — don't invent any.

## P. Project-level checks — `--all` only

Whole-module properties. They change rarely, so raising them on a diff review buries the findings that matter. **Never report these outside an `--all` audit.**

- **Toolchain configuration.** No `.swiftlint.yml`; the safety opt-ins missing (`force_unwrapping`, `implicitly_unwrapped_optional`, `unowned_variable_capture`); the target not on Swift 6 language mode or `-strict-concurrency=complete`. One recommendation covers the whole mechanical class better than eyeballing diffs ever will.
- **Public surface coherence.** In a package (`Package.swift`), sweep what is `public` versus what needs to be: `public` surface that leaks internal types, `public` where `internal` was the intent, mutable `public var` that should be `private(set)`, and missing `@frozen`/`@inlinable` decisions on a library that has made an ABI commitment. Adding a case to a `public enum` a client switches over is a source break — worth one whole-module pass, not a per-diff nag.
- **Naming against the API Design Guidelines**, as a sweep rather than a style hunt: mutating/non-mutating pairs (`sort()`/`sorted()`, `union`/`formUnion`), factory methods beginning with `make`, non-mutating methods reading as noun phrases. Flag only where it genuinely misleads — and remember there is **no "don't prefix with `get`" rule**.
- **`@retroactive` conformances across the module** — two modules conforming the same external type conflict at runtime, which only a whole-module view surfaces.
- **Test posture** — whether `sleep`-based synchronization, real clock, network or home-directory access appear across the suite. Do not demand migration off XCTest; it is not deprecated and still has no equivalent for UI automation or performance testing.

## Do NOT flag these

- **Anything in §P, on a diff review.** Lint configuration, language mode, `public` surface and naming sweeps are module properties; this diff did not change them.

Common reviewer instincts that are wrong or unsupported. See `references/memory-and-performance.md` §7 for sources.

- **`final` for speed** — WMO already infers it. Legit reasons are enforcement and API semantics.
- **`ContiguousArray` everywhere** — identical efficiency for struct/enum elements.
- **`@inlinable` for speed** — it's an ABI commitment, and SwiftPM has conservative CMO by default.
- **Blanket `reserveCapacity`** — inside a loop it makes `append` O(n²).
- **"String `+=` is quadratic"** — folklore.
- **Broad `@MainActor`** — see §3.
- **"Don't prefix with `get`"** — not an API Design Guidelines rule.
- **Demanding `-strict-memory-safety`** — officially "best left for projects with the strongest security requirements."
- **Demanding migration off XCTest to swift-testing** — XCTest is not deprecated and still has no equivalent for UI automation, performance testing, or Objective-C exception handling.
- **Anything the project's enabled SwiftLint rules or Swift 6 mode already catch.**


## Output Format

```markdown
## Swift Review: {scope}

### Baseline
{Language mode / default isolation / strict concurrency, and any assumption you had to make — these change how the code *reads*, so state them whenever they were ambiguous. **At `--all` only:** the §P results, including the toolchain recommendation. On a diff review, omit this block if the isolation picture was unambiguous.}

### Critical Issues (Must Fix)
- {file}:{line} — {category}: {description}
  **Why it's not a lint or compiler finding:** {what judgment this needed}
  **Impact:** {what breaks}
  **Fix:** {model change / isolation change / real failure path — with code}

### Improvements (Should Fix)
- {file}:{line} — {category}: {description}
  **Fix:** {solution}

### Suggestions (Nice to Have)
- {file}:{line} — {category}: {description} — {suggested change}

```

If `--multi` was used, append one subsection per advisor that responded (titled with the advisor's name as reported by `second-opinion`), then a **Cross-Model Agreement** subsection.

## Examples

**Invalid state representable:**
> /review-swift --staged

Finds `struct FeedState { var isLoading: Bool; var items: [Item]?; var error: Error? }` — nothing prevents `isLoading == true` with both `items` and `error` set, and the view has three `if` branches guessing. Reports Should Fix when those contradictory branches create incorrect ordinary UI behavior; otherwise a useful modeling improvement is Nice to Have. Proposes an `enum FeedState { case idle, loading, loaded([Item]), failed(Error) }` rewrite. Not a lint finding: the struct is perfectly valid Swift.

**Force-unwrap hiding a mistyped source:**
> /review-swift --changed

Finds `URLRequest(url: URL(string: config.host + path)!)` where `config.host` is a `String` decoded from a plist. Reports Should Fix if a malformed configured host causes a recoverable failure, or Must Fix only for a demonstrated core outage without reasonable recovery — decode `host` as a `URL` or validate once at config load, rather than guarding each call site. `force_unwrapping` is opt-in and may not even be running; even when it is, it only says "there's a `!`".

**State assumption across a suspension:**
> /review-swift

Finds an actor cache whose `value(for:)` checks a dictionary, `await`s a network fetch, then writes back. Concurrent callers each see an empty cache and issue duplicate requests. Reports Should Fix if this causes demonstrated substantial cost or wrong results; otherwise Nice to Have. Fix: store the in-flight `Task` so later callers await the same one. The compiler is silent; this is explicitly outside its scope.

## Troubleshooting

### Findings overlap with SwiftLint or the compiler
**Solution:** Check whether the project actually *runs* that rule — many safety rules are opt-in and off by default. If it does, drop the finding. If it doesn't, fold it into the one-time baseline recommendation rather than reporting each occurrence.

### Can't tell which concurrency dialect the target uses
**Solution:** Check `Package.swift` for `swiftLanguageMode` / `defaultIsolation` / `.enableUpcomingFeature`, and Xcode for `SWIFT_VERSION`, `SWIFT_STRICT_CONCURRENCY`, and the Approachable Concurrency / Default Actor Isolation settings. Mixed-mode workspaces are normal. If ambiguous, review as if strict checking is off and say so in the Baseline line.

### Can't tell if a force-unwrap is safe
**Solution:** Trace the value's origin. Compile-time literal or a value the same function just built → probably fine. Decoded, networked, user-supplied, or resource-loaded → recommend a real failure path.

## Notes

- Model first, isolate second, force-unwrap never. Most escape-hatch findings dissolve once the underlying type is modeled correctly.
- Respect project conventions in CLAUDE.md (a codebase may deliberately use IUOs for two-phase init or standardize on `Result`).
- Don't be dogmatic: wrapper types, typed throws, `some`-over-`any`, and noncopyable types all have costs — recommend them where they prevent real bugs.
- **Test code:** a force-unwrap of *test-supplied fixture data* or a `setUp`-assigned IUO is defensible. A force-unwrap of a value *produced by the system under test* should be `try #require(x)` / `try XCTUnwrap(x)` — a crash loses the diagnostic and, under swift-testing's in-process parallelism, can take down concurrently running tests. Also flag `sleep`-based synchronization and real clock/network access in unit tests.
- Sources: Swift API Design Guidelines, the Swift 6 Concurrency Migration Guide, and swift-evolution proposals (swift.org); Apple SwiftUI documentation and WWDC sessions; Matt Massicotte's problematic-patterns catalogue; the Airbnb Swift style guide's judgment-only subset. SwiftLint and swift-format own the mechanical rules.
