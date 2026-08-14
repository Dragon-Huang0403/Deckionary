#!/usr/bin/env bash
set -euo pipefail

# Build the macOS app locally.
#
# Usage: ./scripts/build_macos.sh [options]
#
#   --debug      Build debug instead of release
#   --signed     Sign with the project's Apple Development identity + team.
#                Requires a certificate in your keychain. Default is ad-hoc,
#                which needs no Apple Developer account.
#   --open       Launch the app when the build finishes
#   --zip        Also produce app/Deckionary-macOS.zip (same as the release workflow)
#   --install    Copy the app to /Applications
#
# Default (ad-hoc) builds with signing disabled via app/macos/Unsigned.xcconfig, then
# signs with `codesign --sign -`. See that file for why signing is skipped during the
# build rather than overridden. macOS will not launch an unsigned bundle, so the
# codesign step is not optional.
#
# Prerequisites: Xcode (not just Command Line Tools), CocoaPods, app/assets/oald10.db,
# app/lib/firebase_options.dart. See the Development section of README.md.

DEBUG=false
SIGNED=false
OPEN_APP=false
MAKE_ZIP=false
INSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) DEBUG=true; shift ;;
        --signed) SIGNED=true; shift ;;
        --open) OPEN_APP=true; shift ;;
        --zip) MAKE_ZIP=true; shift ;;
        --install) INSTALL=true; shift ;;
        -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; echo "Try: $0 --help" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
cd "$APP_DIR"

# Use the SDK pinned in app/.fvmrc when fvm is available, matching CI.
FLUTTER="flutter"
if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then
    FLUTTER="fvm flutter"
fi

if [ ! -f assets/oald10.db ]; then
    echo "error: app/assets/oald10.db is missing. Download it with:" >&2
    echo "  curl -fSL -o app/assets/oald10.db https://r2.deckionary.com/db/oald10.db" >&2
    exit 1
fi

if [ ! -f lib/firebase_options.dart ]; then
    echo "error: app/lib/firebase_options.dart is missing. Generate it with:" >&2
    echo "  cd app && fvm exec flutterfire configure --project=deckionary" >&2
    exit 1
fi

if $DEBUG; then
    MODE=debug
    CONFIG=Debug
else
    MODE=release
    CONFIG=Release
fi

BUILD_ARGS=("--$MODE")
if [ -f env.json ]; then
    BUILD_ARGS+=("--dart-define-from-file=env.json")
    echo "==> Using env.json (sync enabled)"
else
    echo "==> No app/env.json; building local-only (no sync). See README.md."
fi

APP_PATH="build/macos/Build/Products/$CONFIG/Deckionary.app"

echo "==> Building macOS $MODE ($( $SIGNED && echo "project signing" || echo "unsigned, ad-hoc signed after" ))"
if $SIGNED; then
    $FLUTTER build macos "${BUILD_ARGS[@]}"
else
    XCODE_XCCONFIG_FILE="$APP_DIR/macos/Unsigned.xcconfig" \
        $FLUTTER build macos "${BUILD_ARGS[@]}"

    echo "==> Ad-hoc signing"
    codesign --force --deep --sign - "$APP_PATH"
    codesign --verify --deep --strict "$APP_PATH"
fi

echo "==> Built $APP_PATH"

if $MAKE_ZIP; then
    ZIP="$APP_DIR/Deckionary-macOS.zip"
    rm -f "$ZIP"
    ( cd "$(dirname "$APP_PATH")" && ditto -c -k --sequesterRsrc --keepParent Deckionary.app "$ZIP" )
    echo "==> Wrote $ZIP"
fi

if $INSTALL; then
    echo "==> Installing to /Applications"
    rm -rf /Applications/Deckionary.app
    cp -R "$APP_PATH" /Applications/Deckionary.app
    echo "==> Installed /Applications/Deckionary.app"
fi

if $OPEN_APP; then
    if $INSTALL; then
        open /Applications/Deckionary.app
    else
        open "$APP_PATH"
    fi
fi
