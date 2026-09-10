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

Requirements: Python 3.9+, Git, Just, the tools used by `just check`, and authenticated `gh` with
repository, Actions, and release access. History must be complete, the latest local and origin
version tags must agree, and the checkout must include origin's current `main`. The preview counts
existing local commits that will be pushed. The check includes Xcode tests and can launch the test
host app.

Before confirmation, checks fetch and verify the published Hooklinesinker artifact, then run
`just check`. A missing or draft Hooklinesinker release stops the command before any version
commit or tag is created.

After confirmation, preparation commits the new Xcode marketing version, then commits both
installer revision pins pointing to that version commit. This gives the installer an immutable
source revision containing the new version. The command atomically pushes `main` and its annotated
tag, then waits for that tag's release workflow. GitHub builds, signs, notarizes, publishes the
ZIP/DMG, updates the Homebrew cask, and updates the Sparkle appcast. Success includes the release URL.
The appcast update adds a remote commit; incorporate it before the next release.

`scripts/release.json` declares the checks and two preparation stages. A failed preparation or push
leaves local changes/commits/tags for inspection. A failed GitHub workflow leaves the published tag
in place; inspect its URL and resume or rerun the failed workflow after fixing the cause. Never
replace a public tag.

## Embedded Hooklinesinker

Juggler releases carry a universal `Contents/MacOS/hooklinesinker` executable. At startup its installer
registers Juggler and creates the shared machine installation if needed. It upgrades an existing
installation only when the bundled version is newer and protocol-compatible; the same or a newer
compatible version is reused. The app does not download executable code during startup or onboarding.

`scripts/hooklinesinker.json` pins the version, protocol and source revision. Keep the
`HOOKLINESINKER_VERSION` default in `scripts/install-remote.sh` aligned; staging rejects drift.
Publish the pinned Hooklinesinker release, including `hooklinesinker-macos-universal` and
`SHA256SUMS`, before releasing Juggler. A draft release does not satisfy this prerequisite.

`just build`, `just run`, `just build-strict` and test builds compile the pinned source revision
for the current Mac using Cargo and its locked dependencies. The first build needs Rust and
network access; the helper is cached under `build/hooklinesinker/development/<revision>/<target>`
and reused until the pin changes or the build directory is removed. Local development does not
require a published Hooklinesinker release or the other Mac architecture's Rust target.

`just archive` uses `just stage-release-hooklinesinker`, which downloads the published universal
release and verifies its checksum, both architectures, version and protocol. All staging paths
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
