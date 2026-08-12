#!/usr/bin/env bash
set -euo pipefail

page='docs/index.html'
style='docs/landing.css'
headers='docs/_headers'
icon='docs/AppIcon-256.png'

for path in "$page" "$style" "$headers" "$icon"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

test "$(grep -oE '<h1[[:space:]>]' "$page" | wc -l | tr -d ' ')" = 1
grep -qE '<main[[:space:]>]' "$page"
grep -qE '<footer[[:space:]>]' "$page"
grep -q 'id="how-it-works"' "$page"
grep -q 'brew install --cask sonim1/tap/switchtab' "$page"
if grep -qiE '<script[[:space:]>]|tracker|analytics|http://' "$page" "$style"; then
  echo 'landing page must stay free of scripts, trackers, and insecure URLs' >&2
  exit 1
fi
grep -q 'X-Content-Type-Options: nosniff' "$headers"
grep -q 'X-Frame-Options: DENY' "$headers"
grep -q 'Content-Security-Policy:' "$headers"
echo 'landing contract passed'
