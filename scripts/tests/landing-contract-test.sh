#!/usr/bin/env bash
set -euo pipefail

page='docs/index.html'
style='docs/landing.css'
headers='docs/_headers'
icon='SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png'

for path in "$page" "$style" "$headers" "$icon"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

test "$(rg -o '<h1\b' "$page" | wc -l | tr -d ' ')" = 1
rg -q '<main\b' "$page"
rg -q '<footer\b' "$page"
rg -q 'id="how-it-works"' "$page"
! rg -qi '<script\b|tracker|analytics|http://' "$page" "$style"
rg -q 'X-Content-Type-Options: nosniff' "$headers"
rg -q 'X-Frame-Options: DENY' "$headers"
rg -q 'Content-Security-Policy:' "$headers"
echo 'landing contract passed'
