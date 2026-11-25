# Releasing Juggler

Releases use [`curtains`](https://github.com/nielsmadan/curtaincall); install it first with
`brew install nielsmadan/tap/curtaincall`. Run `just release` from a clean, current `main`
checkout. It proposes a version from commits since the latest published tag, runs `just check`,
and prompts for confirmation. Enter `y` to publish, enter a version or `patch`/`minor`/`major` to
revise the proposal, or press Enter to cancel.

```sh
just release
just release minor
just release 1.9.0
just release --dry-run
just release patch --yes
```

`feat` proposes a minor bump, `fix`/`perf` a patch, and `!` or a `BREAKING CHANGE:` footer a major
bump (minor during `0.x`). Maintenance-only changes require an explicit bump. `--dry-run` reads
local and origin state and previews, but skips the tool check and every configured command,
including checks and preparation. `--yes` explicitly confirms unattended use; other nonterminal
invocations fail.

Requirements: curtains, Python 3, Git 2.45+ with repository push access, Just, and the tools used by
`just check`. History must be complete, and every `vMAJOR.MINOR.PATCH` tag must exist both locally
and on origin and point to the same commit. Curtains never fetches: the fetched `origin/main` must
be an ancestor of `HEAD`. The preview counts existing local commits that will be pushed. The check
includes Xcode tests and can launch the test host app.

Before confirmation, checks fetch and verify the published Hooklinesinker artifact, then run
`just check`. A missing or draft Hooklinesinker release stops the command before any version
commit or tag is created. The preview lists a newer published HLS release, which the release
adopts first (see [Updating HLS](#updating-hls)).

After confirmation, preparation commits the new Xcode marketing version together with the SSH
tab's installer revision, which points at the release commit's parent. That commit is immutable
once pushed and carries the same `scripts/install-remote.sh` as the release. Curtains atomically
pushes `main` and its annotated tag, then prints workflow and release links and finishes.
Publication runs asynchronously; local success confirms the Git push. GitHub builds, signs, notarizes, publishes the ZIP/DMG, updates the
Homebrew cask, and updates the Sparkle appcast. The workflow installs curtains through the
`nielsmadan/curtaincall` action: `curtains ci validate-tag` checks that the pushed tag is annotated
and on `main` before the build, `curtains ci previous-tag` picks the tag the release notes compare
against, and `curtains ci publish` creates the GitHub release as a draft, uploads the ZIP/DMG and
publishes it. Check the linked workflow for publication success or failure.
The appcast update adds a remote commit; incorporate it before the next release.

The workflow runs as four jobs. `build` checks that the Xcode marketing version matches the tag,
then signs, notarizes and saves the ZIP, DMG, rendered cask and release notes as the
`juggler-release` artifact. Only `build` holds the signing secrets, and its token is read-only.
`publish` revalidates the tag and publishes that artifact. `homebrew` and `appcast` follow it:
the cask update leaves a newer published cask alone and commits only on change, and
`scripts/update_appcast.py` skips a version the feed already lists. Release notes list the
non-`chore` commits since the previous tag.

`scripts/release.json` declares the checks and two preparation stages. A failed preparation or push
leaves local changes/commits/tags for inspection. A failed GitHub workflow leaves the published tag
in place; inspect its URL and use **Re-run failed jobs** after fixing the cause. A failed `publish`,
`homebrew` or `appcast` job then reuses the signed build, so `curtains ci publish` finds identical
assets. Re-running `build` produces new signatures, which an already-published release refuses.
Never replace a public tag. Curtains does not automatically resume.

## Embedded Hooklinesinker

Juggler releases carry a universal `Contents/MacOS/hooklinesinker` executable. At startup its installer
registers Juggler and creates the shared machine installation if needed. It upgrades an existing
installation only when the bundled version is newer and protocol-compatible; the same or a newer
compatible version is reused. The app does not download executable code during startup or onboarding.

`scripts/pins.json` pins the version, its source revision (the tag's commit) and the sha256 of
`hooklinesinker-macos-universal`; `curtains pins` manages it. The protocol Juggler speaks is
`PROTOCOL` in `scripts/hooklinesinker.py`. Keep the `HOOKLINESINKER_VERSION` default in
`scripts/install-remote.sh` aligned; staging rejects drift, and updating the pin rewrites it.
Publish the pinned Hooklinesinker release, including `hooklinesinker-macos-universal` and
`SHA256SUMS`, before releasing Juggler. A draft release does not satisfy this prerequisite.

### Updating HLS

`just release` updates the pin first when a newer HLS release is published (the policy's `pins`):
it records the new version, commit and digest, rewrites `scripts/install-remote.sh`, stages the
published binary (checksum, pinned digest, both architectures, version and protocol) and commits
`fix: update hooklinesinker to VERSION` before the release commit. `just release --keep-pins` releases
with the current pin. A different protocol requires a Juggler compatibility change first; staging
fails, and the release stops with the update left for review.

To update without releasing:

```sh
just update-hooklinesinker       # latest published stable release
# Or choose a release: just update-hooklinesinker 1.0.1
just build
just verify-hooklinesinker
```

Then review and commit `scripts/pins.json` and `scripts/install-remote.sh`. `just check-hooklinesinker`
checks for an update without changing files. Both use `curtains pins` and the GitHub CLI. The update
only changes build inputs; the installed app continues to use its bundled helper.

### Building and verifying the helper

`just build`, `just run`, `just build-strict` and test builds compile the pinned source revision
for the current Mac using Cargo and its locked dependencies. The first build needs Rust and
network access; the helper is cached under `build/hooklinesinker/development/<revision>/<target>`
and reused until the pin changes or the build directory is removed. Local development does not
require a published Hooklinesinker release or the other Mac architecture's Rust target.

`just archive` uses `just stage-release-hooklinesinker`, which downloads the published universal
release and verifies its checksum, pinned digest, both architectures, version and protocol. All staging paths
apply an ad hoc signature with hardened runtime enabled before Xcode runs. Xcode's
**Embed Helpers** Copy Files phase places it in `Contents/MacOS` with **Code Sign On Copy**,
replacing that signature's identity with the app's. Direct Xcode Debug builds need
`just stage-hooklinesinker` before the first build, after deleting `build/`, and after changing
the pin. Stage the published release with `just stage-release-hooklinesinker` before archiving
directly in Xcode.

Normal local development:

```sh
just build
just verify-hooklinesinker
```

To test a local universal release artifact in a Debug build:

```sh
# In the Hooklinesinker checkout:
rustup target add aarch64-apple-darwin x86_64-apple-darwin
bash scripts/build-release.sh aarch64-apple-darwin x86_64-apple-darwin

# In the Juggler checkout:
HOOKLINESINKER_DIST=/path/to/hooklinesinker/dist just build
just verify-hooklinesinker
```

To try an unreleased hooklinesinker CLI change against a Debug build, run `just refresh-active`
in the hooklinesinker checkout. It rebuilds and overwrites the active shared binary, which Juggler
runs for every CLI call. `HOOKLINESINKER_DIST` alone does not reach it while the version number is
unchanged, because promotion reuses an equal version. Other consumers, such as ringleader, run the
refreshed binary too.

A Juggler change that calls a new hooklinesinker command needs that command in a published
release before Juggler ships: release hooklinesinker, then release Juggler; `just release`
updates the pin first (or run `just update-hooklinesinker <version>` to pin a specific release). Settings → General → Reset Sessions (`sessions reset`) is one such change.

`HOOKLINESINKER_DIST` accepts a directory containing the universal artifact and its manifest;
a thin binary supplied through that override is rejected. CI test jobs build both architectures
from the pinned source revision. Archives, release preparation and the release workflow always fetch the published artifact,
even if a local override is set.

After export, `python3 scripts/hooklinesinker.py verify release/export/Juggler.app --distribution`
verifies the app seal, both helper slices' hardened-runtime signatures, matching Developer ID team
and secure timestamps.
It also installs the helper into temporary XDG roots and verifies the promoted copy. This
check never registers a consumer in the developer's real installation. After notarization and
stapling, Gatekeeper assessment must pass before publication.

The signing setup follows [Apple's external helper recipe](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).
The helper runs independently, so it does not receive the sample's sandbox-inheritance entitlements.

## Release rehearsal

Manually dispatch the **Release** workflow on the candidate revision after the pinned
Hooklinesinker release is published. A manual run archives, exports, verifies, notarizes and
saves the ZIP/DMG as Actions artifacts. Only tag-triggered runs publish a GitHub release or update
the Homebrew tap and Sparkle feed. Inspect the successful rehearsal before the first release
with a changed helper-signing setup.
