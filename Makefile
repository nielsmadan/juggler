BUNDLE_ID = com.nielsmadan.Juggler
SCHEME = Juggler
BUILD_DIR = ./build
APP_PATH = $(BUILD_DIR)/Build/Products/Debug/Juggler.app

# Release
RELEASE_DIR = ./release
ARCHIVE_PATH = $(RELEASE_DIR)/Juggler.xcarchive
EXPORT_PATH = $(RELEASE_DIR)/export
ZIP_PATH = $(RELEASE_DIR)/Juggler.zip

.PHONY: build build-strict run clean lint lint-fix format setup test test-ui test-all reset-data reset-permissions reset-all release archive export notarize notarize-ci release-clean tag-release tag-release-patch tag-release-minor tag-release-major

FILES ?= .
XCCONFIG_FLAG = $(if $(XCCONFIG),-xcconfig $(XCCONFIG),)

build:
	@xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) $(XCCONFIG_FLAG) build

build-strict:
	@xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) $(XCCONFIG_FLAG) build 2>&1 | tee /dev/stderr | \
		(! grep -E "warning:.*Juggler/" >/dev/null 2>&1)

# Fast unit tests only (no UI, no app launch)
test:
	@xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) \
		$(XCCONFIG_FLAG) -only-testing:JugglerTests test

# UI tests only (launches app, slower)
test-ui:
	@xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) \
		$(XCCONFIG_FLAG) -only-testing:JugglerUITests test

# All tests (unit + UI)
test-all:
	@xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) $(XCCONFIG_FLAG) test

run: build
	@open $(APP_PATH)

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Build directory cleaned."

lint:
	@swiftlint $(FILES)

lint-fix:
	@swiftlint --fix $(FILES)

format:
	@swiftformat $(FILES)

reset-data:
	@echo "Resetting Juggler app data..."
	@defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@rm -rf ~/Library/Caches/$(BUNDLE_ID) 2>/dev/null || true
	@echo "Done. Restart the app for changes to take effect."

reset-permissions:
	@echo "Resetting Juggler permissions..."
	@tccutil reset AppleEvents $(BUNDLE_ID) 2>/dev/null || true
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@echo "Done. You'll be prompted for permissions on next launch."

reset-all: reset-data reset-permissions
	@echo "All resets complete."

setup:
	@lefthook install
	@echo "Git hooks installed."

# --- Release targets ---

release: release-clean archive export
	@echo "Creating ZIP..."
	@cd $(EXPORT_PATH) && zip -r -y ../../$(ZIP_PATH) Juggler.app
	@echo ""
	@echo "=== Release build complete ==="
	@echo "ZIP: $(ZIP_PATH)"
	@echo "SHA256: $$(shasum -a 256 $(ZIP_PATH) | cut -d' ' -f1)"
	@echo ""

archive:
	@echo "Archiving Release build..."
	@mkdir -p $(RELEASE_DIR)
	@xcodebuild -scheme $(SCHEME) -configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		archive

export:
	@echo "Exporting with Developer ID signing..."
	@xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist ExportOptions.plist
	@echo "Verifying code signature..."
	@codesign -dv --verbose=2 $(EXPORT_PATH)/Juggler.app 2>&1 | head -5

notarize:
	@echo "Submitting for notarization..."
	@xcrun notarytool submit $(ZIP_PATH) \
		--keychain-profile "juggler-notarize" \
		--wait
	@echo "Stapling notarization ticket..."
	@cd $(EXPORT_PATH) && xcrun stapler staple Juggler.app
	@echo "Re-creating ZIP with stapled app..."
	@rm -f $(ZIP_PATH)
	@cd $(EXPORT_PATH) && zip -r -y ../../$(ZIP_PATH) Juggler.app
	@echo ""
	@echo "=== Notarization complete ==="
	@echo "ZIP: $(ZIP_PATH)"
	@echo "SHA256: $$(shasum -a 256 $(ZIP_PATH) | cut -d' ' -f1)"
	@echo ""

notarize-ci:
	@echo "Submitting for notarization..."
	@xcrun notarytool submit $(ZIP_PATH) \
		--apple-id "$(NOTARIZATION_APPLE_ID)" \
		--password "$(NOTARIZATION_PASSWORD)" \
		--team-id "$(NOTARIZATION_TEAM_ID)" \
		--wait
	@echo "Stapling notarization ticket..."
	@cd $(EXPORT_PATH) && xcrun stapler staple Juggler.app
	@echo "Re-creating ZIP with stapled app..."
	@rm -f $(ZIP_PATH)
	@cd $(EXPORT_PATH) && zip -r -y ../../$(ZIP_PATH) Juggler.app
	@echo ""
	@echo "=== Notarization complete ==="
	@echo "ZIP: $(ZIP_PATH)"
	@echo "SHA256: $$(shasum -a 256 $(ZIP_PATH) | cut -d' ' -f1)"
	@echo ""

# Usage: make tag-release-patch, make tag-release-minor, make tag-release-major
#   Bumps MARKETING_VERSION in the Xcode project, commits, tags, and pushes.
#   Plain tag-release requires MARKETING_VERSION to already be ahead of the latest tag.
tag-release-patch:
	@$(MAKE) tag-release BUMP=patch

tag-release-minor:
	@$(MAKE) tag-release BUMP=minor

tag-release-major:
	@$(MAKE) tag-release BUMP=major

tag-release:
	@VERSION=$$(xcodebuild -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null \
		| grep MARKETING_VERSION | head -1 | tr -d ' ' | cut -d= -f2); \
	LATEST_TAG=$$(git tag --sort=-v:refname | head -1 | sed 's/^v//'); \
	if [ -n "$(BUMP)" ]; then \
		MAJOR=$$(echo "$$VERSION" | cut -d. -f1); \
		MINOR=$$(echo "$$VERSION" | cut -d. -f2); \
		PATCH=$$(echo "$$VERSION" | cut -d. -f3); \
		case "$(BUMP)" in \
			patch) PATCH=$$((PATCH + 1)) ;; \
			minor) MINOR=$$((MINOR + 1)); PATCH=0 ;; \
			major) MAJOR=$$((MAJOR + 1)); MINOR=0; PATCH=0 ;; \
			*) echo "Error: BUMP must be patch, minor, or major"; exit 1 ;; \
		esac; \
		VERSION="$$MAJOR.$$MINOR.$$PATCH"; \
		echo "Bumping MARKETING_VERSION to $$VERSION..."; \
		sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $$VERSION/" \
			Juggler.xcodeproj/project.pbxproj; \
		git add Juggler.xcodeproj/project.pbxproj; \
		git commit -m "chore: bump version to $$VERSION"; \
	elif [ "$$VERSION" = "$$LATEST_TAG" ] || [ "$$(printf '%s\n' "$$LATEST_TAG" "$$VERSION" | sort -V | tail -1)" = "$$LATEST_TAG" ]; then \
		echo "Error: MARKETING_VERSION ($$VERSION) is not newer than latest tag (v$$LATEST_TAG)."; \
		echo "Run: make tag-release BUMP=patch|minor|major"; \
		exit 1; \
	fi; \
	echo "Tagging v$$VERSION..."; \
	git tag "v$$VERSION" && git push origin main "v$$VERSION"; \
	echo "Tagged and pushed v$$VERSION — release workflow triggered."

release-clean:
	@rm -rf $(RELEASE_DIR)
