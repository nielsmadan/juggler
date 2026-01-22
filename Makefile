BUNDLE_ID = com.nielsmadan.Juggler
SCHEME = Juggler
BUILD_DIR = ./build
APP_PATH = $(BUILD_DIR)/Build/Products/Debug/Juggler.app

.PHONY: build build-strict run clean lint lint-fix format setup test test-ui test-all reset-data reset-permissions reset-all

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
