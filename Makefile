SHELL := /bin/bash
.DEFAULT_GOAL := help

PRODUCT := Coinscal
CONFIGURATION ?= Debug
BUILD_ROOT := $(CURDIR)/Build
# UI languages; the first one is the source language. Keep in sync with docs/LOCALIZATION.md
LANGS := en,zh-Hans,zh-Hant
# Three localization guards (scripts/i18n-guard.py): raise --min-files as the project grows so a broken path can't pass silently
I18N_GUARD := python3 scripts/i18n-guard.py --langs "$(LANGS)" --min-files 20

# Built-in coin catalog (docs/COIN_CATALOG.md); make test-mac validates it offline, make catalog regenerates it online
CATALOG_FILE := Apple/Mac/Resources/coins.json

# Local developer config (not committed; template in local.mk.example)
-include local.mk

BUILD_TARGETS :=
TEST_TARGETS :=

# --- Apple ---
APPLE_PROJECT := Apple/$(PRODUCT).xcodeproj
ifneq ($(strip $(DEVELOPMENT_TEAM)),)
SIGNING_FLAGS := -allowProvisioningUpdates DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"
else
SIGNING_FLAGS :=
endif
# Builds use -quiet by default to cut noise. Tests don't, because -quiet swallows the ** TEST SUCCEEDED / FAILED ** result line (the result line is the source of truth).
# For full build output: make mac XCODEBUILD_FLAGS=
XCODEBUILD_FLAGS ?= -quiet
XCODEBUILD_TEST_FLAGS ?=
MAC_SCHEME := $(PRODUCT)Mac
MAC_BUILD_ROOT := $(BUILD_ROOT)/macOS
MAC_APP := $(MAC_BUILD_ROOT)/$(CONFIGURATION)/$(PRODUCT).app
MAC_DIST := $(MAC_BUILD_ROOT)/Dist
MAC_RELEASE_APP := $(MAC_BUILD_ROOT)/Release/$(PRODUCT).app
# Release signing (docs/DEVELOPMENT.md, "Release"): manual Developer ID signing, no development certificate or provisioning profile.
# Notarization credentials go in local.mk: NOTARY_PROFILE, or ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
DEVELOPER_ID ?= Developer ID Application
RELEASE_SIGNING_FLAGS := DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp
RELEASE_ENV := DEVELOPER_ID="$(DEVELOPER_ID)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" \
    NOTARY_PROFILE="$(NOTARY_PROFILE)" ASC_KEY_ID="$(ASC_KEY_ID)" ASC_ISSUER_ID="$(ASC_ISSUER_ID)" ASC_KEY_PATH="$(ASC_KEY_PATH)"
# Apple/project.yml is the single source of the version number
VERSION := $(shell sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' Apple/project.yml | head -1)
BUILD_TARGETS += mac
TEST_TARGETS += test-mac

# --- Site ---
# Static website in Site/, deployed to Cloudflare Workers Static Assets (Site/wrangler.jsonc). Wrangler runs via npx at
# a pinned version; it isn't installed in the repo. It needs Node 22+: the newest nvm-installed Node 22+ is used when
# there is one, without changing the default Node.
WRANGLER_NODE_BIN := $(lastword $(sort $(wildcard $(HOME)/.nvm/versions/node/v2[2-9].*/bin)))
WRANGLER := $(if $(WRANGLER_NODE_BIN),PATH="$(WRANGLER_NODE_BIN):$$PATH" )npx --yes wrangler@4.137.0
SITE_PORT ?= 8787
TEST_TARGETS += test-site

.PHONY: help build test clean project site-run site-login site-whoami site-deploy mac-run mac-release mac-release-notarized mac-release-app mac-check-sources catalog $(BUILD_TARGETS) $(TEST_TARGETS)

help:
	@echo "$(PRODUCT) build commands"
	@echo "  make build                 Build all components: $(BUILD_TARGETS)"
	@echo "  make test                  Run all tests: $(TEST_TARGETS)"
	@echo "  make clean                 Delete Build/ and fallback artifacts in the source tree"
	@echo "  make project               Generate the Xcode project from Apple/project.yml"
	@echo "  make mac                   Build Build/macOS/$(CONFIGURATION)/$(PRODUCT).app"
	@echo "  make mac-run               Build, verify, and open the Mac app"
	@echo "  make mac-release           Release: Developer ID-signed zip and DMG in Build/macOS/Dist/ (no notarization or upload; needs a GUI session)"
	@echo "  make mac-release-notarized Release and notarize: as above, then notarize the app and DMG, staple the ticket, and pass Gatekeeper checks"
	@echo "  make test-mac              Localization guards + Mac unit tests"
	@echo "  make mac-check-sources     Manual: check all price and exchange rate data sources over the real network (not part of make test)"
	@echo "  make catalog               Regenerate the built-in coin catalog Apple/Mac/Resources/coins.json online (run before a release)"
	@echo "  make test-site             Website: localization guards + offline checks (Node 20+)"
	@echo "  make site-run              Website: local preview at http://localhost:$(SITE_PORT)/ with Site/_headers applied"
	@echo "  make site-login            Website: sign in to Cloudflare for deploys (opens a browser; needs Node 22+)"
	@echo "  make site-deploy CONFIRM=yes  Website: test, then deploy Site/ to Cloudflare (needs wrangler login or CLOUDFLARE_API_TOKEN)"

build: $(BUILD_TARGETS)

test: $(TEST_TARGETS)

project:
	@command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen"; exit 1; }
	cd Apple && xcodegen generate --quiet

mac: project
	xcodebuild $(XCODEBUILD_FLAGS) -project "$(APPLE_PROJECT)" -scheme "$(MAC_SCHEME)" \
	    -configuration "$(CONFIGURATION)" -destination 'platform=macOS,arch=arm64' \
	    -derivedDataPath "$(MAC_BUILD_ROOT)/DerivedData" \
	    CONFIGURATION_BUILD_DIR="$(MAC_BUILD_ROOT)/$(CONFIGURATION)" $(SIGNING_FLAGS) build

mac-run: mac
	@test -x "$(MAC_APP)/Contents/MacOS/$(PRODUCT)" || { echo "Build product missing: $(MAC_APP)"; exit 1; }
	codesign --verify --deep --strict "$(MAC_APP)"
	open "$(MAC_APP)"

# Release build, manually signed with Developer ID (Hardened Runtime is enabled in project.yml)
mac-release-app: project
	@test -n "$(DEVELOPMENT_TEAM)" || { echo "Releasing requires DEVELOPMENT_TEAM in local.mk"; exit 1; }
	@security find-identity -v -p codesigning | grep -q "$(DEVELOPER_ID).*($(DEVELOPMENT_TEAM))" || \
	    { echo "No $(DEVELOPER_ID) ($(DEVELOPMENT_TEAM)) certificate in the keychain"; exit 1; }
	xcodebuild $(XCODEBUILD_FLAGS) -project "$(APPLE_PROJECT)" -scheme "$(MAC_SCHEME)" \
	    -configuration Release -destination 'platform=macOS,arch=arm64' \
	    -derivedDataPath "$(MAC_BUILD_ROOT)/DerivedData" \
	    CONFIGURATION_BUILD_DIR="$(MAC_BUILD_ROOT)/Release" $(RELEASE_SIGNING_FLAGS) build

# The DMG's Finder layout is written with AppleScript, so both release commands must run in a logged-in GUI session (not in CI)
mac-release: mac-release-app
	$(RELEASE_ENV) scripts/release/release.sh "$(MAC_RELEASE_APP)" "$(MAC_DIST)" "$(MAC_BUILD_ROOT)/Release-work" "$(VERSION)"

# Check notarization credentials before building, so a missing one doesn't waste a Release build
mac-release-notarized:
	@test -n "$(NOTARY_PROFILE)" || { test -n "$(ASC_KEY_ID)" && test -n "$(ASC_ISSUER_ID)" && test -n "$(ASC_KEY_PATH)"; } || \
	    { echo "Notarization credentials missing: set NOTARY_PROFILE, or ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH, in local.mk (see docs/DEVELOPMENT.md, \"Release\")"; exit 1; }
	$(MAKE) mac-release-app
	$(RELEASE_ENV) scripts/release/release.sh "$(MAC_RELEASE_APP)" "$(MAC_DIST)" "$(MAC_BUILD_ROOT)/Release-work" "$(VERSION)" --notarize

test-mac: project
	$(I18N_GUARD) --platform apple --root Apple/Mac --extra Apple/MacWidget
	python3 scripts/catalog/generate_catalog.py validate $(CATALOG_FILE)
	xcodebuild $(XCODEBUILD_TEST_FLAGS) -project "$(APPLE_PROJECT)" -scheme "$(MAC_SCHEME)" \
	    -configuration "$(CONFIGURATION)" -destination 'platform=macOS,arch=arm64' \
	    -derivedDataPath "$(MAC_BUILD_ROOT)/Tests/DerivedData" \
	    CONFIGURATION_BUILD_DIR="$(MAC_BUILD_ROOT)/Tests/$(CONFIGURATION)" test

test-site:
	python3 scripts/i18n-guard.py --langs "$(LANGS)" --min-files 7 --platform web --root Site
	cd Site && npm run check

site-run:
	python3 scripts/site/serve.py --port $(SITE_PORT)

# Deploying publishes the site: it needs an explicit CONFIRM=yes
# Cloudflare sign-in for deploys (opens a browser); the credentials stay in Wrangler's user config, outside the repo
site-login:
	$(WRANGLER) login

site-whoami:
	$(WRANGLER) whoami

site-deploy: test-site
	@test "$(CONFIRM)" = "yes" || { echo "Deploying publishes https://coinscal.app/. Run: make site-deploy CONFIRM=yes"; exit 1; }
	cd Site && $(WRANGLER) deploy

# Built-in coin catalog: generated online; --previous keeps every id from the old catalog (existing users' watchlists stay intact)
catalog:
	python3 scripts/catalog/generate_catalog.py generate --previous $(CATALOG_FILE) \
	    --migrations scripts/catalog/migrations.json --out $(CATALOG_FILE)

# Hits the real network; results vary with market data and data source status, so it's not part of make test
mac-check-sources:
	Apple/Mac/scripts/manual/check-data-sources.sh

clean:
	@test "$(BUILD_ROOT)" = "$(CURDIR)/Build" || { echo "Refusing to clean an unexpected directory: $(BUILD_ROOT)"; exit 1; }
	rm -rf "$(BUILD_ROOT)"
	rm -rf Apple/Build Apple/*/.build Apple/*/Build build dist Site/.wrangler
