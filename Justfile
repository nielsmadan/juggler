bundle_id := "com.nielsmadan.Juggler"
scheme := "Juggler"
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

build xcconfig="":
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} build

build-strict xcconfig="":
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} build 2>&1 | tee /dev/stderr | \
        (! grep -E "warning:.*Juggler/" >/dev/null 2>&1)

# Fast unit tests only (no UI, no app launch)
test xcconfig="":
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} -enableCodeCoverage YES \
        -only-testing:JugglerTests test

# UI tests only (launches app, slower)
test-ui xcconfig="":
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} -enableCodeCoverage YES \
        -only-testing:JugglerUITests test

# All tests (unit + UI)
test-all xcconfig="":
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} -enableCodeCoverage YES test

coverage xcconfig="":
    @rm -rf {{xcresult}}
    @xcodebuild -scheme {{scheme}} -configuration Debug -derivedDataPath {{build_dir}} \
        {{ if xcconfig != "" { "-xcconfig " + xcconfig } else { "" } }} -enableCodeCoverage YES \
        -resultBundlePath {{xcresult}} -only-testing:JugglerTests test
    @xcrun xccov view --report --only-targets {{xcresult}} | grep -E "^--|Juggler\.app"

run: build
    @{{app_path}}/Contents/MacOS/Juggler

clean:
    @rm -rf {{build_dir}}
    @echo "Build directory cleaned."

lint files=".":
    @swiftlint {{files}}

lint-fix files=".":
    @swiftlint --fix {{files}}

format files=".":
    @swiftformat {{files}}

unused-check:
    @periphery scan

reset-data:
    @echo "Resetting Juggler app data..."
    @defaults delete {{bundle_id}} 2>/dev/null || true
    @rm -rf ~/Library/Caches/{{bundle_id}} 2>/dev/null || true
    @echo "Done. Restart the app for changes to take effect."

reset-permissions:
    @echo "Resetting Juggler permissions..."
    @tccutil reset AppleEvents {{bundle_id}} 2>/dev/null || true
    @tccutil reset Accessibility {{bundle_id}} 2>/dev/null || true
    @echo "Done. You'll be prompted for permissions on next launch."

reset-integration:
    @echo "Resetting Juggler integrations..."
    @rm -rf ~/.claude/hooks/juggler
    @printf 'import json,os\np=os.path.expanduser("~/.claude/settings.json")\ntry:\n f=open(p);s=json.load(f);f.close()\nexcept:exit(0)\nh=s.get("hooks",{})\nfor k in list(h):\n h[k]=[e for e in h[k] if "juggler/notify.sh" not in str(e)]\n if not h[k]:del h[k]\nf=open(p,"w");json.dump(s,f,indent=2);f.close()\n' | python3 2>/dev/null || true
    @rm -f ~/.config/kitty/juggler_watcher.py
    @sed -i '' '/juggler_watcher\.py/d; /^allow_remote_control/d; /^listen_on/d' ~/.config/kitty/kitty.conf 2>/dev/null || true
    @sed -i '' '/update-environment.*ITERM_SESSION_ID/d' ~/.tmux.conf 2>/dev/null || true
    @rm -f ~/.config/opencode/plugins/juggler-opencode.ts
    @echo "Done. Integration configs removed."

reset-all: reset-data reset-permissions reset-integration
    @echo "All resets complete."

setup:
    @lefthook install
    @echo "Git hooks installed."

# --- Release targets ---

release: release-clean archive export
    #!/usr/bin/env bash
    echo "Creating ZIP..."
    cd {{export_path}} && zip -r -y ../../{{zip_path}} Juggler.app
    echo ""
    echo "=== Release build complete ==="
    echo "ZIP: {{zip_path}}"
    echo "SHA256: $(shasum -a 256 {{zip_path}} | cut -d' ' -f1)"
    echo ""

archive:
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
    @codesign -dv --verbose=2 {{export_path}}/Juggler.app 2>&1 | head -5

notarize:
    #!/usr/bin/env bash
    echo "Submitting for notarization..."
    xcrun notarytool submit {{zip_path}} \
        --keychain-profile "juggler-notarize" \
        --wait
    echo "Stapling notarization ticket..."
    cd {{export_path}} && xcrun stapler staple Juggler.app
    echo "Re-creating ZIP with stapled app..."
    rm -f {{zip_path}}
    cd {{export_path}} && zip -r -y ../../{{zip_path}} Juggler.app
    echo ""
    echo "=== Notarization complete ==="
    echo "ZIP: {{zip_path}}"
    echo "SHA256: $(shasum -a 256 {{zip_path}} | cut -d' ' -f1)"
    echo ""

notarize-ci:
    #!/usr/bin/env bash
    echo "Submitting for notarization..."
    xcrun notarytool submit {{zip_path}} \
        --apple-id "$NOTARIZATION_APPLE_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --team-id "$NOTARIZATION_TEAM_ID" \
        --wait
    echo "Stapling notarization ticket..."
    cd {{export_path}} && xcrun stapler staple Juggler.app
    echo "Re-creating ZIP with stapled app..."
    rm -f {{zip_path}}
    cd {{export_path}} && zip -r -y ../../{{zip_path}} Juggler.app
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

# Usage: just tag-release-patch, just tag-release-minor, just tag-release-major
#   Bumps MARKETING_VERSION in the Xcode project, commits, tags, and pushes.
#   Plain tag-release requires MARKETING_VERSION to already be ahead of the latest tag.
tag-release-patch:
    @just tag-release patch

tag-release-minor:
    @just tag-release minor

tag-release-major:
    @just tag-release major

tag-release bump="":
    #!/usr/bin/env bash
    set -euo pipefail
    LATEST_TAG=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
    if [ -z "$LATEST_TAG" ]; then
        echo "Error: no existing tags found."; exit 1
    fi
    if [ -n "{{bump}}" ]; then
        MAJOR=$(echo "$LATEST_TAG" | cut -d. -f1)
        MINOR=$(echo "$LATEST_TAG" | cut -d. -f2)
        PATCH=$(echo "$LATEST_TAG" | cut -d. -f3)
        case "{{bump}}" in
            patch) PATCH=$((PATCH + 1)) ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            *) echo "Error: bump must be patch, minor, or major"; exit 1 ;;
        esac
        VERSION="$MAJOR.$MINOR.$PATCH"
        echo "Bumping version: v$LATEST_TAG -> v$VERSION"
        sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" \
            Juggler.xcodeproj/project.pbxproj
        git add Juggler.xcodeproj/project.pbxproj
        git commit -m "chore: bump version to $VERSION"
    else
        VERSION=$(xcodebuild -scheme {{scheme}} -configuration Release -showBuildSettings 2>/dev/null \
            | grep MARKETING_VERSION | head -1 | tr -d ' ' | cut -d= -f2)
        if [ "$VERSION" = "$LATEST_TAG" ] || [ "$(printf '%s\n' "$LATEST_TAG" "$VERSION" | sort -V | tail -1)" = "$LATEST_TAG" ]; then
            echo "Error: MARKETING_VERSION ($VERSION) is not newer than latest tag (v$LATEST_TAG)."
            echo "Run: just tag-release-patch, tag-release-minor, or tag-release-major"
            exit 1
        fi
    fi
    echo "Tagging v$VERSION..."
    git tag "v$VERSION" && git push origin main "v$VERSION" && \
    echo "Tagged and pushed v$VERSION — release workflow triggered."

release-clean:
    @rm -rf {{release_dir}}
