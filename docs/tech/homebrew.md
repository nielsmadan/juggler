# Homebrew Distribution

The canonical tap is `nielsmadan/tap` (`nielsmadan/homebrew-tap` on GitHub). The former `homebrew-juggler` repository redirects there, but Homebrew can retain its old tap name in installed receipts. Use the fully qualified command in [README](../../README.md#installation); it also grants the individual cask's trust on Homebrew 6.

## Cask source and releases

[`homebrew/juggler.rb.in`](../../homebrew/juggler.rb.in) is the cask source. The release workflow renders it with [`scripts/render-homebrew-cask.py`](../../scripts/render-homebrew-cask.py), then copies the complete result to the tap's `Casks/juggler.rb`. Changes to uninstall or dependency rules therefore ship with the matching app release.

The cask declares `auto_updates true` for Sparkle. Homebrew can then compare the installed app's version when its receipt still records an older version, avoiding an unnecessary quit and replacement after a Sparkle update.

Generation runs before publishing and requires:

- The app version to match the release tag and its bundle identifier to match Juggler.
- The exported app's `LSMinimumSystemVersion` to be 15.0, matching the cask's Sequoia minimum.
- The shell entry point and both Python cleanup helpers to exist in the exported bundle.
- An executable, regular `Contents/MacOS/hooklinesinker` helper in the exported bundle.

The checksum is computed from the final notarized DMG. The release workflow needs its existing `HOMEBREW_TAP_TOKEN` with write access to `homebrew-tap`. Follow the repository's `just release` workflow after committing changes to publish a new app and cask together; editing the template alone does not update installed users.

## Removal and migration

Ordinary uninstall quits and removes the app, retaining settings and integrations. Upgrades and ordinary reinstalls use the same nondestructive path. `brew uninstall --cask --zap juggler` additionally runs integration cleanup and removes Juggler's application support, caches, and preferences, including statistics.

The zap script uses `staged_path`, not `/Applications`: Homebrew copies the app back into its staging directory during artifact removal, then runs zap before purging that directory. This also supports a custom `--appdir`. Keep cleanup out of the `uninstall` stanza because Homebrew executes it during upgrade and reinstall too. `brew reinstall --zap` explicitly requests the same destructive cleanup.

The shell entry point runs Python with `-B` so helper imports leave the signed app bundle intact. This matters when cleanup runs from Settings and the app remains installed.

Zap unregisters Juggler from hooklinesinker. Shared hooks and Codex trust remain while another
consumer is registered; the last consumer's removal also clears matching trust entries after
confirming that the shared hooks are gone.

Homebrew saves uninstall rules at installation time. Existing installations need an upgrade or reinstall to receive new rules. The README's fully qualified reinstall command also refreshes the tap identity; only untap the old name afterward. A GitHub repository redirect alone does not rewrite installed receipts.

## Verification

`just test-packaging` runs the real cleanup shell script against temporary files and checks cask generation. It then exercises Homebrew's artifact lifecycle with a fixture app for uninstall, upgrade, reinstall, and zap. Application quitting and preference trashing are intercepted; integration cleanup runs against fixture paths. No Juggler process is launched.

The tests cover mixed hook groups, later Codex settings, commented TOML tables and multiline strings, symlinks, malformed configuration, custom config paths, idempotence, and cleanup from the staged app. A Kitty installer-to-cleanup round trip covers paths containing spaces. A signed fixture verifies that cleanup preserves the resource seal, and Homebrew version checks cover a stale receipt after Sparkle updates. These tests run in CI and before release packaging. The Xcode unit tests separately verify resource bundling.
