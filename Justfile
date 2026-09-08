bundle_id := "com.nielsmadan.Juggler"
scheme := "Juggler"
stats_key := "dailyBusyStats"
build_dir := "./build"
app_path := build_dir / "Build/Products/Debug/Juggler.app"

# Release
release_dir := "./release"
archive_path := release_dir / "Juggler.xcarchive"
export_path := release_dir / "export"
zip_path := release_dir / "Juggler.zip"
dmg_path := release_dir / "Juggler.dmg"

xcresult := build_dir / "Logs/Test/coverage.xcresult"

[private]
default:
    @just --list

# Prepare this checkout for work: dependencies, hooks, then verify.
setup:
    @just resolve-deps
    @lefthook install
    @just doctor

# Verify the tools and checkout state this repo needs.
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    fail=0
    need() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  ok       %s\n' "$1"
        else
            printf '  MISSING  %-12s install: %s\n' "$1" "$2"; fail=1
        fi
    }
    need swiftformat "brew install swiftformat"
    need swiftlint "brew install swiftlint"
    need python3 "brew install python"
    need xcodebuild "install Xcode from the App Store"
    need periphery "brew install --cask peripheryapp/periphery/periphery"
    need lefthook "brew install lefthook"
    if [ -f "$(git rev-parse --git-path hooks/pre-commit)" ]; then
        printf '  ok       git hooks\n'
    else
        printf '  MISSING  %-12s run: just setup\n' 'git hooks'; fail=1
    fi
    [ "$fail" -eq 0 ] && printf 'Everything in place.\n'
    exit $fail

build xcconfig="": stage-hooklinesinker
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} build

stage-hooklinesinker:
    @python3 scripts/hooklinesinker.py stage

verify-hooklinesinker:
    @python3 scripts/hooklinesinker.py verify {{app_path}}

resolve-deps:
    @xcodebuild -resolvePackageDependencies -scheme {{scheme}} -derivedDataPath {{build_dir}}

build-strict xcconfig="": stage-hooklinesinker
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} build 2>&1 | tee /tmp/build-output.log
    ! grep -qE "warning:.*Juggler/" /tmp/build-output.log

# Format check, lint, strict build and tests. The pre-push gate.
check xcconfig="":
    @python3 -B -m unittest discover -s scripts -p 'test_release*.py'
    @swiftformat --lint .
    @swiftlint --strict .
    @python3 -B -m unittest discover -s scripts/tests
    @just build-strict {{xcconfig}}
    @just test {{xcconfig}}
    @just check-unused {{xcconfig}}

# Unit tests run in a Juggler host process.
test xcconfig="": stage-hooklinesinker
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} -enableCodeCoverage YES \
        -parallel-testing-enabled NO -only-testing:JugglerTests test

test-packaging:
    @python3 -m unittest discover -s scripts/tests -v
    @brew ruby scripts/tests/homebrew_lifecycle.rb

coverage xcconfig="": stage-hooklinesinker
    @rm -rf {{xcresult}}
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} -enableCodeCoverage YES \
        -parallel-testing-enabled NO -resultBundlePath {{xcresult}} -only-testing:JugglerTests test
    @xcrun xccov view --report --only-targets {{xcresult}} | grep -E "^--|Juggler\.app"

# Performance / resource-hygiene guards (idle-CPU & leak regressions). Deterministic
# but timing-sensitive, so kept out of the fast loop — intended for a weekly schedule.
# Marked with the `.performance` tag; run the suites that carry those guards.
test-perf xcconfig="": stage-hooklinesinker
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} \
        -parallel-testing-enabled NO -only-testing:JugglerTests/ITerm2StderrDrainTests test

# Layer 2 idle-CPU guard: launch a populated, rendering instance and assert it
# stays quiet. `--with-bridges` exercises the real iTerm2 daemon (local only).
test-idle-cpu *args:
    @just build "${PERF_XCCONFIG:-}"
    @bash scripts/perf/idle-cpu.sh "{{app_path}}/Contents/MacOS/Juggler" {{args}}

run: build clean-registrations
    @{{app_path}}/Contents/MacOS/Juggler

# Unregister stale copies of Juggler from LaunchServices so macOS doesn't
# launch the wrong one when e.g. clicking a notification.
clean-registrations:
    #!/usr/bin/env bash
    lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
    current="$(cd "{{app_path}}" && pwd -P)"
    "$lsregister" -dump \
        | awk -v current="$current" '/^-{10}/{path=""} /^path:/{path=$2} /identifier:.*{{bundle_id}}/{if(path!="" && path!=current) print path}' \
        | while IFS= read -r p; do
            "$lsregister" -u "$p" 2>/dev/null && echo "Unregistered: $p"
        done
    "$lsregister" -f -R -trusted "$current"

clean:
    @rm -rf {{build_dir}}
    @echo "Build directory cleaned."

lint *files:
    @swiftlint --strict {{ if files == "" { "." } else { files } }}

lint-fix *files:
    @swiftlint --fix {{ if files == "" { "." } else { files } }}

format *files:
    @swiftformat {{ if files == "" { "." } else { files } }}

# Indexes JugglerTests too; without it Periphery reports every test-only hook as unused.
build-for-testing xcconfig="": stage-hooklinesinker
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} build-for-testing

check-unused xcconfig="": (build-for-testing xcconfig)
    @periphery scan --skip-build --index-store-path {{build_dir}}/Index.noindex/DataStore \
        --strict --retain-equatable-properties

reset-data:
    @echo "Resetting Juggler app data..."
    @defaults delete {{bundle_id}} 2>/dev/null || true
    @rm -rf ~/Library/Caches/{{bundle_id}} 2>/dev/null || true
    @echo "Done. Restart the app for changes to take effect."

reset-onboarding:
    @echo "Resetting Juggler onboarding flag..."
    @defaults delete {{bundle_id}} hasCompletedOnboarding 2>/dev/null || true
    @echo "Done. Restart the app to see the onboarding wizard."

reset-permissions:
    @echo "Resetting Juggler permissions..."
    @tccutil reset AppleEvents {{bundle_id}} 2>/dev/null || true
    @echo "Done."

reset-integration:
    @echo "Resetting Juggler integrations..."
    @bash juggler/Resources/hooks/uninstall.sh
    @echo "Done. Integration configs removed."

reset-all: reset-data reset-permissions reset-integration
    @echo "All resets complete."

# Reset everything (like reset-all) but preserve the daily busy statistics
reset-keep-stats:
    #!/usr/bin/env bash
    set -euo pipefail
    # Snapshot the stats blob (a Data value) as hex before wiping the domain.
    hex=""
    backup="$(mktemp)"
    if defaults export {{bundle_id}} "$backup" 2>/dev/null; then
        b64="$(plutil -extract {{stats_key}} raw -o - "$backup" 2>/dev/null || true)"
        if [ -n "$b64" ]; then
            hex="$(printf '%s' "$b64" | base64 -D | xxd -p | tr -d '\n')"
            echo "Preserving statistics ({{stats_key}})..."
        fi
    fi
    rm -f "$backup"

    just reset-data reset-permissions reset-integration

    if [ -n "$hex" ]; then
        defaults write {{bundle_id}} {{stats_key}} -data "$hex"
        echo "Statistics restored."
    else
        echo "No statistics found to preserve."
    fi
    echo "All resets complete (statistics kept)."

# --- Release targets ---

archive: stage-hooklinesinker
    @echo "Archiving Release build..."
    @mkdir -p {{release_dir}}
    @xcodebuild -scheme {{scheme}} -configuration Release \
        -archivePath {{archive_path}} \
        archive

export:
    @echo "Exporting with Developer ID signing..."
    @xcodebuild -exportArchive \
        -archivePath {{archive_path}} \
        -exportPath {{export_path}} \
        -exportOptionsPlist ExportOptions.plist
    @echo "Verifying code signature..."
    @python3 scripts/hooklinesinker.py verify {{export_path}}/Juggler.app --distribution

notarize:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Submitting for notarization..."
    xcrun notarytool submit {{zip_path}} \
        --keychain-profile "juggler-notarize" \
        --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple {{export_path}}/Juggler.app
    spctl --assess --type execute --verbose=2 {{export_path}}/Juggler.app
    echo "Re-creating ZIP with stapled app..."
    rm -f {{zip_path}}
    (cd {{export_path}} && zip -r -y ../../{{zip_path}} Juggler.app)
    echo ""
    echo "=== Notarization complete ==="
    echo "ZIP: {{zip_path}}"
    echo "SHA256: $(shasum -a 256 {{zip_path}} | cut -d' ' -f1)"
    echo ""

notarize-ci:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Submitting for notarization..."
    xcrun notarytool submit {{zip_path}} \
        --apple-id "$NOTARIZATION_APPLE_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --team-id "$NOTARIZATION_TEAM_ID" \
        --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple {{export_path}}/Juggler.app
    spctl --assess --type execute --verbose=2 {{export_path}}/Juggler.app
    echo "Re-creating ZIP with stapled app..."
    rm -f {{zip_path}}
    (cd {{export_path}} && zip -r -y ../../{{zip_path}} Juggler.app)
    echo ""
    echo "=== Notarization complete ==="
    echo "ZIP: {{zip_path}}"
    echo "SHA256: $(shasum -a 256 {{zip_path}} | cut -d' ' -f1)"
    echo ""

dmg:
    #!/usr/bin/env bash
    echo "Creating DMG..."
    rm -f {{dmg_path}}
    create-dmg \
        --volname "Juggler" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 100 \
        --icon "Juggler.app" 180 190 \
        --hide-extension "Juggler.app" \
        --app-drop-link 480 190 \
        {{dmg_path}} \
        {{export_path}}/
    echo ""
    echo "=== DMG created ==="
    echo "DMG: {{dmg_path}}"
    echo "SHA256: $(shasum -a 256 {{dmg_path}} | cut -d' ' -f1)"
    echo ""

clean-release:
    @rm -rf {{release_dir}}

[positional-arguments]
release *args:
    python3 scripts/release.py "$@"
