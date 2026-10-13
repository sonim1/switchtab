#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "${1:-}" != "--build-only" ) ]]; then
    printf '%s\n' 'Usage: scripts/run-native-window-fixture.sh [--build-only]' >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${NATIVE_WINDOW_QA_BUILD_ROOT:-$REPO_ROOT/.build/native-window-fixture}"
APP_PATH="$BUILD_ROOT/SwitchTabSecurityQA.app"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$REPO_ROOT/SwitchTabQA/WindowFixtureInfo.plist" "$APP_PATH/Contents/Info.plist"
swiftc -parse-as-library "$REPO_ROOT/SwitchTabQA/WindowSwitchingFixture.swift" \
    -o "$APP_PATH/Contents/MacOS/SwitchTabSecurityQA"

if [[ "${1:-}" != "--build-only" ]]; then
    open "$APP_PATH"
fi
printf '%s\n' "$APP_PATH"
