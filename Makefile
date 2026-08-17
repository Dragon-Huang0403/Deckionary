# Deckionary developer commands. Run `make` for the list.
#
# Flutter/Dart commands are prefixed with fvm when it is installed, so they use the
# version pinned in app/.fvmrc — the same one CI uses. See CLAUDE.md.

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

APP_DIR := app
DB_URL := https://r2.deckionary.com/db/oald10.db

ifeq ($(shell command -v fvm 2>/dev/null),)
  FLUTTER := flutter
  DART := dart
else
  FLUTTER := fvm flutter
  DART := fvm dart
endif

# Sync is enabled only when app/env.json exists; without it the app runs local-only.
ifneq ($(wildcard $(APP_DIR)/env.json),)
  DEFINES := --dart-define-from-file=env.json
else
  DEFINES :=
endif

# Everything except the sync tests, which need a running local Supabase.
OFFLINE_TESTS = $$(find test -name '*_test.dart' -not -path 'test/core/sync/*' | sort)

.PHONY: help setup db deps run run-android build build-macos build-apk install \
        test test-offline test-sync analyze format format-check lint gen doctor \
        supabase-up supabase-down clean

help: ## Show this help
	@echo "Deckionary — make targets:"
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Using: $(FLUTTER)$(if $(DEFINES), (env.json found, sync enabled), (no env.json, local-only))"

setup: db deps ## First-time setup: SDK, dictionary DB, dependencies
	cd $(APP_DIR) && fvm install
	@echo "Next: generate app/lib/firebase_options.dart and app/env.json — see README.md"

db: ## Download the dictionary database if missing (~210 MB)
	@if [ -f $(APP_DIR)/assets/oald10.db ]; then \
		echo "app/assets/oald10.db already present"; \
	else \
		curl -fSL --retry 3 -o $(APP_DIR)/assets/oald10.db "$(DB_URL)"; \
	fi

deps: ## Install Dart dependencies exactly as CI does
	cd $(APP_DIR) && $(FLUTTER) pub get --enforce-lockfile

run: ## Run the app on macOS
	cd $(APP_DIR) && $(FLUTTER) run -d macos $(DEFINES)

run-android: ## Run the app on a connected Android device or emulator
	cd $(APP_DIR) && $(FLUTTER) run -d android $(DEFINES)

build: build-macos ## Alias for build-macos

build-macos: ## Build a release macOS app (ad-hoc signed; no Apple account needed)
	./scripts/build_macos.sh

build-apk: ## Build a release Android APK
	cd $(APP_DIR) && $(FLUTTER) build apk --release $(DEFINES)

install: ## Build the macOS app and install it to /Applications
	./scripts/build_macos.sh --install --open

test: ## Run all tests (sync tests need `make supabase-up` first)
	cd $(APP_DIR) && $(FLUTTER) test

test-offline: ## Run every test that does not need Supabase
	cd $(APP_DIR) && $(FLUTTER) test $(OFFLINE_TESTS)

test-sync: ## Run only the Supabase sync tests (needs `make supabase-up`)
	cd $(APP_DIR) && $(FLUTTER) test test/core/sync

analyze: ## Lint, exactly as CI enforces it
	cd $(APP_DIR) && $(FLUTTER) analyze --fatal-warnings

format: ## Format lib and test in place
	cd $(APP_DIR) && $(DART) format lib test

format-check: ## Fail if anything is unformatted
	cd $(APP_DIR) && $(DART) format --output=none --set-exit-if-changed lib test

lint: analyze format-check ## analyze + format-check

gen: ## Regenerate Drift code after a schema change
	cd $(APP_DIR) && $(DART) run build_runner build --delete-conflicting-outputs

doctor: ## Show the Flutter toolchain state
	cd $(APP_DIR) && $(FLUTTER) doctor -v

supabase-up: ## Start local Supabase (needs Docker + the Supabase CLI)
	supabase start

supabase-down: ## Stop local Supabase
	supabase stop

clean: ## Remove build output
	cd $(APP_DIR) && $(FLUTTER) clean
