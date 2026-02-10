BUNDLE_ID = com.nielsmadan.Juggler
SCHEME = Juggler
BUILD_DIR = ./build
APP_PATH = $(BUILD_DIR)/Build/Products/Debug/Juggler.app

# Release
RELEASE_DIR = ./release
ARCHIVE_PATH = $(RELEASE_DIR)/Juggler.xcarchive
EXPORT_PATH = $(RELEASE_DIR)/export
ZIP_PATH = $(RELEASE_DIR)/Juggler.zip

.PHONY: build build-strict run clean lint lint-fix format setup test test-ui test-all reset-data reset-permissions reset-all release archive export notarize notarize-ci release-clean

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

release-clean:
	@rm -rf $(RELEASE_DIR)
