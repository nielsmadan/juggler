# Releasing Juggler

Run `just release` from a clean, current `main` checkout. It proposes a version from commits since
the latest published tag, runs `just check`, and prompts for confirmation. Enter `y` to publish,
enter a version or `patch`/`minor`/`major` to revise the proposal, or press Enter to cancel.

```sh
just release
just release minor
just release 1.9.0
just release --dry-run
just release patch --yes
```

`feat` proposes a minor bump, `fix`/`perf` a patch, and `!` or a `BREAKING CHANGE:` footer a major
bump (minor during `0.x`). Maintenance-only changes require an explicit bump. `--dry-run` reads
local and origin state and previews without running checks or publishing. `--yes` explicitly
confirms unattended use; other nonterminal invocations fail.

Requirements: Python 3.9+, Git with repository push access, Just, and the tools used by `just check`.
History must be complete, the latest local and origin version tags must agree, and the checkout must
include origin's current `main`. The preview counts existing local commits that will be pushed.
The check includes Xcode tests and can launch the test host app.

After confirmation, preparation commits the new Xcode marketing version, then commits both
installer revision pins pointing to that version commit. This gives the installer an immutable
source revision containing the new version. The command atomically pushes `main` and its annotated
tag, then prints workflow and release links and finishes. Publication runs asynchronously; local
success confirms the Git push. GitHub builds, signs, notarizes, publishes the ZIP/DMG, updates the
Homebrew cask, and updates the Sparkle appcast. CI uses `gh` to create the GitHub release record and
upload artifacts, which Git cannot do. Check the linked workflow for publication success or failure.
The appcast update adds a remote commit; incorporate it before the next release.

`scripts/release.json` declares the checks and two preparation stages. A failed preparation or push
leaves local changes/commits/tags for inspection. A failed GitHub workflow leaves the published tag
in place; inspect its URL and resume or rerun the failed workflow after fixing the cause. Never
replace a public tag.
