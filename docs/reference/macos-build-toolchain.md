# macOS Build Toolchain

Behavior of the external tools and platform APIs this project builds on — `xcodebuild`, Swift
Testing, SwiftLint/SwiftFormat, Periphery, Sparkle, and the AppKit APIs that turned out not to work
the way their documentation implies.

Only the non-obvious parts are here. Routine settings live in the build files themselves, and the
commands to run are in [`AGENTS.md`](../../AGENTS.md).

- [xcodebuild and Xcode](#xcodebuild-and-xcode)
- [Swift Testing](#swift-testing)
- [SwiftLint and SwiftFormat](#swiftlint-and-swiftformat)
- [Periphery](#periphery)
- [Sparkle](#sparkle)
- [macOS platform APIs](#macos-platform-apis)
- [Upstream](#upstream)

## xcodebuild and Xcode

**Verified — `-parallel-testing-enabled NO` is mandatory, and Swift Testing cannot substitute for
it.** `xcodebuild` runs tests in multiple **processes**. Swift Testing's `.serialized` trait only
orders tests within one process, so it cannot prevent interference on anything process-global —
`UserDefaults.standard`, and the shared `SessionManager` / `TerminalBridgeRegistry` singletons. Both
mechanisms are needed: the flag for cross-process isolation, `.serialized` for in-process ordering.
Established while fixing flaky CI runs.

**Documented — `PBXFileSystemSynchronizedRootGroup` auto-discovers files.** Xcode 16+ syncs group
membership from disk, so adding a source file under `juggler/` needs no `project.pbxproj` edit. The
synchronized membership carries an explicit exception list; `Info.plist` is excluded because it is
referenced directly via `INFOPLIST_FILE` rather than synced.

**Documented — there is no "warnings as errors" flag in use.** Strictness is a grep over the build
log for `warning:.*Juggler/`, scoped that way deliberately so warnings from SPM dependencies
(Sparkle among them) cannot fail the build. A compiler-level flag would not make that distinction.

**Documented — two unrelated things are both called "sandbox".** `ENABLE_APP_SANDBOX = NO` is the
app's *runtime* sandbox, off because the app drives terminals over Apple Events, Unix sockets, and
subprocesses. `ENABLE_USER_SCRIPT_SANDBOXING = YES` restricts *build-time* run-script phases and is
independent of it.

**Documented — `SWIFT_VERSION = 5.0` is a language mode, not a toolchain version.** It coexists
with `SWIFT_STRICT_CONCURRENCY = complete`, which is why the codebase carries Swift 6 concurrency
annotations while nominally building in Swift 5 mode.

**Verified — the deployment target is a silent product decision, and Xcode picks it for you.**
`MACOSX_DEPLOYMENT_TARGET` sat at `26.2` in all four configurations from the project's first commit
— Xcode's creation-time default, never deliberately chosen — while every human-written claim said
macOS 14. A binary built that way cannot launch for anyone below 26.2, regardless of what the
Homebrew cask permits. Nothing in the build warns about the gap.

The compiler is the authority on the real floor: building at 14.0 fails on exactly two uses of
`defaultLaunchBehavior` (macOS 15+) in `juggler/JugglerApp.swift`, and 15.0 builds clean. Resolved
2026-08-22 by setting the target to 15.0 and correcting the advertised minimum to Sequoia
everywhere. **A deployment target no one set is not a supported-OS claim** — re-derive it from a
build whenever the advertised minimum changes.

## Swift Testing

**Documented — Swift Testing only.** `@Test` / `#expect`, no `XCTest`. A UI-test target existed
historically and is gone; end-to-end coverage is the separate idle-CPU harness instead.

**Verified — `withThrowingTaskGroup` deadlocks inside an actor-isolated method when the child
closure captures `self`.** The parent task holds the actor while awaiting the child, the child needs
the actor to start, and neither can proceed. It hangs **silently**, with no error and no timeout.
Use a transport-level timeout or a cancellable `Task.sleep` instead, and log at method entry before
the first `await` so a silent hang is at least visible. Full post-mortem:
[`docs/log/2026-01-27-actor-deadlock-withTimeout.md`](../log/2026-01-27-actor-deadlock-withTimeout.md)
(2026-01-27); also discussed on the
[Swift forums](https://forums.swift.org/t/hang-when-awaiting-call-to-actor/54026).

**Documented — `Decodable` payload structs need an explicit `nonisolated init(from:)`** to avoid
actor-isolation warnings under complete strict concurrency.

## SwiftLint and SwiftFormat

**Verified — the two tools actively fight over the same code.** SwiftFormat rewrites what SwiftLint
then flags, producing a commit loop that cannot converge. Resolved by disabling the overlapping
SwiftLint rules (`trailing_whitespace`, `line_length` — SwiftFormat's `--trimwhitespace` and
`--maxwidth` already cover them) and by pinning the two settings they disagreed on most,
`--commas inline` and `--disable wrapMultilineStatementBraces`. Any new rule enabled on one side
should be checked against the other.

**Documented — order matters in the pre-commit hook.** SwiftFormat runs first, then SwiftLint
`--fix`, then a non-fixing SwiftLint `--strict` check. The first two re-stage their own changes, so
the final check sees the fully formatted tree. Running the check before the fixers inverts the
result.

**Gotcha — `--swiftversion` and `SWIFT_VERSION` are separate knobs.** SwiftFormat is pinned at 5.9
and the Xcode project at 5.0; they measure different things and can drift apart unnoticed.

## Periphery

**Verified — `.periphery.yml` needs an explicit `targets:` key.** Without it, scans warn on CI even
though they pass locally.

**Verified — install Periphery as a cask, not a tap formula.** `brew tap peripheryapp/periphery &&
brew install periphery` does not work on CI runners; `brew install --cask
peripheryapp/periphery/periphery` does.

**Documented — deliberately-unused symbols get an inline annotation.** `// periphery:ignore -
<reason>` rather than deletion, used for reserved test tags that nothing references yet.

## Sparkle

**Documented — the update feed is configured entirely in `Info.plist`.** `SUFeedURL` points at the
raw `appcast.xml` on the default branch; `SUPublicEDKey` embeds the public EdDSA key in the shipped
app. The matching private key exists only as a CI secret.

**Gotcha — the appcast is assembled by string splicing, not by Sparkle's tooling.** The release
workflow pulls the Sparkle release tarball solely to obtain `sign_update`, then inserts a new
`<item>` into `appcast.xml` by locating `</channel>` in the raw text. No XML parser and no
`generate_appcast` are involved, so any change to the file's formatting can break the splice
silently. Sparkle's own [publishing guide](https://sparkle-project.org/documentation/publishing/)
describes the supported path.

**Gotcha — signature verification at release time is informational.** `codesign -dv` output is
printed for a human to read; it does not gate the build.

**Gotcha — the ZIP and the DMG are notarized separately.** They are distinct artifacts (Sparkle
consumes the ZIP, Homebrew the DMG) and each needs its own `notarytool submit --wait` and
`stapler staple`.

**Gotcha — CI cannot use a keychain profile.** `notarytool --keychain-profile` works locally but not
on a headless runner, so CI passes Apple ID credentials as environment variables and imports the
signing certificate into a throwaway keychain per run. That keychain needs
`set-key-partition-list` or `codesign` blocks waiting on a UI prompt that will never appear.

## macOS platform APIs

**Verified — a notification banner click always foregrounds the posting app, with no opt-out.**
Confirmed against Apple's documentation, a survey of open-source apps, and
[FB13131879](https://github.com/feedback-assistant/reports/issues/418). The activation is
two-phase: once before `didReceive`, once after `completionHandler()`. Custom
`UNNotificationAction` buttons declared without `.foreground` can run in the background, but the
default banner click cannot be intercepted. Anything that wants focus to land elsewhere must let the
activation complete and then hand focus back, which costs a visible flash.

**Verified — `NSScreen.main` is not the primary display.** It is the screen holding keyboard focus.
CoreGraphics' global coordinate space is anchored to the *primary* display, so converting a CG
(top-left origin) frame to AppKit (bottom-left origin) coordinates must flip using
`NSScreen.screens.first`. Using `NSScreen.main` mispositions windows on multi-monitor setups. Both
are correct in different places: the flip needs the primary screen, positioning needs the screen the
window will appear on.

**Verified — LaunchServices keeps stale registrations and will launch the wrong build.** Old copies
of the app remain registered by bundle identifier, so a notification click can route to a previous
build. `lsregister -dump` lists them; unregistering the stale paths and force-re-registering the
current one is the only reliable fix, and it has to run before each launch during development.

**Verified — `FileHandle.readabilityHandler` re-fires forever at EOF.** Once the write end of a pipe
closes, the kernel reports the descriptor readable-at-EOF indefinitely and GCD re-invokes the
handler in a tight loop, pinning a CPU core per dead child process. The handler must remove itself
on an empty read. This is regression-tested and guarded by the idle-CPU harness
([`docs/perf/idle-cpu.md`](../perf/idle-cpu.md)).

**Verified — SwiftUI creates and shows a window as a side effect of activation.** During
notification handling this happens *before* the app's own handling flag is set, because
`windowDidBecomeKey` fires ahead of `didReceive`. Suppressing the flash requires hiding that window
explicitly rather than relying on ordering.

**Gotcha — a second instance flashes a menu-bar icon before it can exit.** The duplicate check has
to run in `applicationDidFinishLaunching` *before* `setActivationPolicy` and `NSApp.activate()`, or
the icon appears momentarily even though the process immediately terminates.

## Upstream

| Tool | Link |
|---|---|
| Swift Testing | [swiftlang/swift-testing](https://github.com/swiftlang/swift-testing) |
| SwiftLint | [realm/SwiftLint](https://github.com/realm/SwiftLint) |
| SwiftFormat | [nicklockwood/SwiftFormat](https://github.com/nicklockwood/SwiftFormat) |
| Periphery | [peripheryapp/periphery](https://github.com/peripheryapp/periphery) |
| Sparkle | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) · [publishing](https://sparkle-project.org/documentation/publishing/) |
| lefthook | [evilmartians/lefthook](https://github.com/evilmartians/lefthook) |
| create-dmg | [create-dmg/create-dmg](https://github.com/create-dmg/create-dmg) |
| ShortcutKit | [nielsmadan/ShortcutKit](https://github.com/nielsmadan/ShortcutKit) |

---

[← Reference index](overview.md)
