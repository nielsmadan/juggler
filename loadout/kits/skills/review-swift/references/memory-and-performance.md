# Memory, ARC & performance review reference

Detail behind checklist §5 and §6. Includes an **anti-items** section — things reviewers commonly flag that are wrong or unsupported.

## 1. Retain cycles — ownership, not syntax

The mechanical question ("is there a `[weak self]`?") is the wrong one. The cycle exists only when **the callee retains the closure**.

- **A closure stored as a property of the object it captures** is the cycle. The same closure passed to `DispatchQueue.asyncAfter` is fine strong — and marking it `weak` there is silently broken, because nothing else holds the object. Judgment: who retains whom, and for how long.
- **A method reference used as a closure** (`self.handler = doThing`) creates a cycle — "this creates a strong reference cycle, because the method implicitly uses self" (WWDC24 "Analyze heap memory", <https://developer.apple.com/videos/play/wwdc2024/10173/>). SE-0269 calls this a compiler **false negative**: `execute(inc)` compiles where `execute { inc() }` errors. Nothing flags it.
- **Delegates: ask who owns the object, not "is it `weak`."** `weak` is *wrong* for a helper the object itself created — it deallocates immediately. SwiftLint's `weak_delegate` is a name matcher, not an ownership analyzer (maintainer's own words, <https://github.com/realm/SwiftLint/issues/2786>).
- **Capture lists snapshot value types at creation time.** `[someStruct]` captures the value as it was, which is a silent staleness bug if it's expected to track later mutations. Fine for constants and reference types.
- **`Task { [weak self] in guard let self else { return } }` is a no-op** — `Task.init` is `@_implicitSelfCapture`, and re-binding strongly defeats the weak capture.

**`unowned` is contested and not a performance win.** John McCall: unowned references are "inherently slower than strong references"; Joe Groff notes that for Objective-C-heritage classes `unowned` is implemented much like `weak` (<https://forums.swift.org/t/unowned-references-have-more-overhead-than-strong-references/72765>). Apple (WWDC24) still defends it where the lifetime guarantee genuinely holds; several named authors and the LinkedIn style guide say avoid. Decide on **lifetime semantics**, never on performance — and never claim `unowned` is faster.

**Over-use of `weak` is itself a defect.** Joe Groff: "It is actively harmful to use weak references in places where they aren't needed" (<https://forums.swift.org/t/long-term-solution-for-accidental-retain-cycles-from-strong-references-in-closures/77201>). This cuts against the community default of reflexive `[weak self]`.

**Tooling can't cover this.** Apple splits the heap into useful / **abandoned** / leaked memory and notes Instruments' Leaks reports only the third — an abandoned graph held by a cycle you can still reach won't show. Closure context has no variable names, so captures appear only as `capture`.

## 2. Value semantics and copying

- **Value semantics leak through a class field.** A struct holding a reference type has value semantics only at the top level — copies share the inner object. swift.org: "In general, prefer to use structs over classes" (<https://www.swift.org/documentation/articles/value-and-reference-types.html>), but this caveat is what makes "just use a struct" wrong sometimes.
- **A struct with several reference-type fields costs N retain/release per copy; a class costs 1.** WWDC24 "Explore Swift performance" (<https://developer.apple.com/videos/play/wwdc2024/10217/>) declines twice to give a size threshold — so the review question is "is this copied a lot?", never "structs under N bytes."
- **Accidental CoW copies.** `var a = a; a.append(x); return a` copies, because parameters arrive at +1. Use `inout`. Same for reading `object.array` repeatedly in a loop, which can force defensive copies. (<https://github.com/swiftlang/swift/blob/main/docs/OptimizationTips.rst>)
- **`lazy var` is not thread-safe** (stated in TSPL); static and global properties *are* initialized-once by guarantee. In a struct, `lazy` forces `mutating get`.
- **`.lazy` collection chains don't cache** — iterating twice recomputes everything.
- **Foundation resilient types are dynamically sized.** A global `URL` heap-allocates, and structs containing one inherit that. (WWDC24-10217)
- **`DateFormatter`: the cost is first-use setup (~42–60 ms) and *reconfiguration* (changing `calendar` ≈ 101 ms), not allocation (~1.37 ms).** A cached formatter that gets reconfigured per call is just as bad as an uncached one. (<https://sarunw.com/posts/how-expensive-is-dateformatter/>)

## 3. Dispatch and existentials

- **A protocol method declared in the protocol body gets dynamic dispatch; one added only in an extension gets static dispatch.** This is a correctness trap, not just a performance one — a conformer "overriding" an extension-only method silently doesn't take effect through the protocol type.
- **Existentials (`any P`) use a 3-word inline buffer, then heap-allocate.** The magnitude is **contested**: Jordan Rose says "95% of the time it won't matter"; David Smith has cited cases at 60% of runtime (<https://forums.swift.org/t/relative-performance-of-existential-any/77299>). Use McCall's framing rather than a rule: "It's a cost, and sometimes costs are worth paying." Recommend `some P` / generics where type information is genuinely useful, not reflexively.

## 4. Codable

- **Decoding an array is all-or-nothing** — one malformed element fails the whole response. Whether that's right is a judgment call; Sundell: "Silently ignoring invalid elements is definitely not always the right approach" (<https://www.swiftbysundell.com/articles/ignoring-invalid-json-elements-codable>).
- **Raw-value enums fail to decode on unknown values** — a server adding a case breaks old clients. Needs an `unknown`/`@unknown`-style fallback if the schema can evolve.
- **A partial `CodingKeys` enum silently drops fields** — declaring it at all opts out of synthesis for the rest.
- **`try?` around decoding erases the reason** — `DecodingError` is specific and useful; discarding it makes field-level schema drift undebuggable.
- **Does `init(from:)` validate or merely parse?** Decoding is a trust boundary; type-correct is not the same as valid.
- DTO-vs-domain-model separation is **contested** — don't present it as consensus.

## 5. Assertions

Ladder (Airbnb, <https://swift.airbnb.tech/skill>): `assert` + logging when the situation is recoverable; `precondition`/`fatalError` when it isn't. Prefer `fatalError` **only when the message is dynamic**, since `precondition` won't surface a dynamic message in the crash log. Note `assert` compiles out in release builds — an `assert` guarding an invariant that matters in production is a finding.

## 6. Other

- **`static var` is global mutable state.** "Stored `static var` properties are global mutable state" — prefer `static let` or a computed property. (Airbnb; and in Swift 6 this is also a compiler error unless isolated.)
- **Enumerate enum cases rather than `default`** in a `switch` you control, so adding a case forces every site to be reconsidered.
- **`@retroactive` conformances** — conforming someone else's type to someone else's protocol. Jordan Rose (ex-Swift compiler team): "it should not be allowed… the biggest concrete regret on the list" (<https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/>). Two modules doing it conflict at runtime.
- **Documentation as a design signal** — the API Design Guidelines' first Fundamental: "If you struggle to describe an API simply, you may have designed the wrong API." Also: document computed properties that aren't O(1).

## 7. Anti-items — do NOT flag these

Reviewers raise these routinely and they are wrong or unsupported:

- **`final` for speed** — whole-module optimization already infers it for `internal` declarations. Legitimate reasons for `final` are enforcement and API semantics (removing `final` from a `public` class is source-breaking), not performance. (<https://forums.swift.org/t/final-optimization-recommendations/18835>)
- **`ContiguousArray` everywhere** — the stdlib documents identical efficiency for struct/enum element types. Only relevant for class/`@objc` elements.
- **Avoiding `@objc`/`NSObject` for dispatch cost** — `@objc` alone doesn't force `objc_msgSend`, and Joe Groff notes the cost "isn't that high."
- **`@inlinable` for speed** — SwiftPM has had conservative cross-module optimization by default since 5.8, and `@inlinable` is an **ABI commitment** (SE-0193). Don't recommend it casually.
- **Blanket `reserveCapacity`** — called inside a loop it makes `append` O(n²). Invert the advice. (<https://www.hackingwithswift.com/articles/128/>)
- **"String `+=` is quadratic"** — unverified folklore.
- **`@inline(always)` on a non-`final` method** — since Swift 6.3 this is a real optimization control that errors when inlining is impossible for a *direct* call, but it does **not** error for dynamically-dispatched calls, so on a non-`final` method it's likely a no-op.
- **Demanding `-strict-memory-safety`** — swift.org: "It's opt-in because the majority of projects don't need this level of enforcement — strict memory safety is best left for projects with the strongest security requirements."
- **Demanding migration off XCTest** — XCTest is **not deprecated** and is still being extended. UI automation, performance testing (`measure`, `XCTMetric`), and Objective-C exception handling have no swift-testing equivalent.
