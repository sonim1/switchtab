#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "${1:-}" != "--build-only" ) ]]; then
    printf '%s\n' 'Usage: scripts/run-native-view-fixture.sh [--build-only]' >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${NATIVE_QA_BUILD_ROOT:-$REPO_ROOT/.build/native-view-fixture}"
APP_PATH="$BUILD_ROOT/ViewStateFixture.app"

swift build --package-path "$REPO_ROOT" --scratch-path "$BUILD_ROOT/spm"
BIN_PATH="$(swift build --package-path "$REPO_ROOT" --scratch-path "$BUILD_ROOT/spm" --show-bin-path)"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$REPO_ROOT/SwitchTabQA/Info.plist" "$APP_PATH/Contents/Info.plist"
swiftc -parse-as-library -I "$BIN_PATH/Modules" \
    "$REPO_ROOT/SwitchTabQA/ViewStateFixture.swift" \
    "$BIN_PATH"/SwitchTab.build/*.o \
    -o "$APP_PATH/Contents/MacOS/ViewStateFixture"

if [[ "${1:-}" != "--build-only" ]]; then
    open "$APP_PATH"
fi
printf '%s\n' "$APP_PATH"
