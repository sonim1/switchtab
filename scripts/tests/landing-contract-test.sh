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
grep -q 'class="demo-reel"' "$page"
grep -q 'id="demo-motion-toggle"' "$page"
grep -q 'for="demo-motion-toggle"' "$page"
grep -q '<span class="demo-motion-control__name">Pause demo animation</span>' "$page"
test "$(grep -oE 'demo-motion-control__(pause|play)" aria-hidden="true"' "$page" | wc -l | tr -d ' ')" = 2
if grep -qE 'demo-motion-toggle[^>]*aria-label' "$page"; then
  echo 'demo motion checkbox must get its stable state label from the visible control' >&2
  exit 1
fi
test "$(grep -o 'class="demo-scene"' "$page" | wc -l | tr -d ' ')" = 1
test "$(grep -oE 'src="demo/layer-[^"]+\.webp"' "$page" | sort -u | wc -l | tr -d ' ')" = 6
test "$(grep -o 'class="demo-layer' "$page" | wc -l | tr -d ' ')" = 7
test "$(grep -o '<small>Hold</small>' "$page" | wc -l | tr -d ' ')" = 1
grep -q '<kbd class="demo-key demo-key--window">`</kbd>' "$page"
if grep -q '′' "$page"; then
  echo 'landing page must show the real backtick window shortcut' >&2
  exit 1
fi
if grep -qE 'Everyday|Developer|Creative|demo-scene__label|demo-scene--' "$page"; then
  echo 'persona scenes remain on landing page' >&2
  exit 1
fi
if grep -qE 'switcher-window|app-strip|app-tile|app-icon--' "$page"; then
  echo 'obsolete CSS switcher markup remains on landing page' >&2
  exit 1
fi
if grep -qE 'layer-finder\.webp|layer-preview-secondary\.webp|layer-app-switcher\.webp|layer-window-switcher\.webp|shortcut-map' "$page"; then
  echo 'unsafe or ambiguous landing demo asset remains referenced' >&2
  exit 1
fi
grep -q 'brew install --cask sonim1/tap/switchtab' "$page"
if grep -qiE '<script[[:space:]>]|<video[[:space:]>]|<canvas[[:space:]>]|tracker|analytics|http://' "$page" "$style"; then
  echo 'landing page must stay free of scripts, video, canvas, trackers, and insecure URLs' >&2
  exit 1
fi
if grep -qiE 'src="https?://' "$page"; then
  echo 'landing page images must be served locally' >&2
  exit 1
fi
if grep -qE 'href="[^"]*\.md' "$page"; then
  echo 'landing page must not link directly to raw Markdown files' >&2
  exit 1
fi
if grep -q 'class="footer-nav"' "$page"; then
  echo 'developer documentation navigation remains in the public footer' >&2
  exit 1
fi

demo_dir='docs/demo'
demo_assets=(
  layer-finder-staged.webp
  layer-notes.webp
  layer-preview-primary.webp
  layer-preview-artwork.webp
  layer-app-switcher-curated.webp
  layer-window-switcher-curated.webp
)

test "${#demo_assets[@]}" = 6
total_bytes=0
for asset in "${demo_assets[@]}"; do
  asset_path="$demo_dir/$asset"
  test -s "$asset_path" || {
    echo "missing landing demo asset: $asset_path" >&2
    exit 1
  }
  asset_bytes="$(wc -c < "$asset_path" | tr -d ' ')"
  total_bytes=$((total_bytes + asset_bytes))
done

test "$(find "$demo_dir" -maxdepth 1 -type f -name '*.webp' | wc -l | tr -d ' ')" = 6
poster_bytes="$(wc -c < "$demo_dir/layer-finder-staged.webp" | tr -d ' ')"
test "$poster_bytes" -le 256000 || {
  echo "landing demo poster exceeds 250 KiB: $poster_bytes bytes" >&2
  exit 1
}
test "$total_bytes" -le 4194304 || {
  echo "landing demo assets exceed 4 MiB: $total_bytes bytes" >&2
  exit 1
}

grep -q -- '--demo-cycle: 9s' "$style"
grep -q '.hero .eyebrow { justify-content: center; }' "$style"
if grep -qE '^\.eyebrow \{[^}]*justify-content: center' "$style"; then
  echo 'hero eyebrow centering must not affect section labels' >&2
  exit 1
fi
grep -q '.demo-motion-toggle:checked ~ .demo-window' "$style"
grep -q 'animation-play-state: paused' "$style"
grep -q '.demo-scene { position: absolute; inset: 0; }' "$style"
grep -q '.demo-desktop { position: absolute; inset: 0; z-index: 0;' "$style"
grep -q '.demo-layer { position: absolute; display: block; height: auto; max-width: none;' "$style"
grep -q '.demo-hud { position: absolute; left: 50%; right: auto; bottom: 24px; z-index: 8;' "$style"
grep -q '.demo-layer--app-switcher { top: 50%; left: 50%; z-index: 6; width: 64%; opacity: 0; transform: translate(-50%, -50%); animation: demo-app-overlay var(--demo-cycle) steps(1, end) infinite; }' "$style"
grep -q '.demo-layer--window-switcher { top: 50%; left: 50%; z-index: 6; width: 48%; opacity: 0; transform: translate(-50%, -50%); animation: demo-window-overlay var(--demo-cycle) steps(1, end) infinite; }' "$style"
grep -q '.demo-layer--preview-final { top: 8%; left: 27%; z-index: 5; width: 62%; opacity: 0; animation: demo-preview-final var(--demo-cycle) steps(1, end) infinite; }' "$style"
grep -q '.demo-hud--apps { animation: demo-hud-apps var(--demo-cycle) steps(1, end) infinite; }' "$style"
grep -q '.demo-hud--windows { animation: demo-hud-windows var(--demo-cycle) steps(1, end) infinite; }' "$style"
grep -q '.demo-hud--release { animation: demo-hud-release var(--demo-cycle) steps(1, end) infinite; }' "$style"
if grep -qE '@keyframes demo-scene-cycle|@keyframes demo-frame-cycle' "$style"; then
  echo 'obsolete full-screen frame cycle remains on landing page' >&2
  exit 1
fi
grep -q '@keyframes demo-app-overlay' "$style"
grep -q '@keyframes demo-window-overlay' "$style"
grep -q '@keyframes demo-preview-final' "$style"
test "$(grep -o 'steps(1, end)' "$style" | wc -l | tr -d ' ')" = 6
grep -q '@keyframes demo-hud-apps' "$style"
grep -q '@keyframes demo-hud-windows' "$style"
grep -q '@keyframes demo-hud-release' "$style"
grep -q '@keyframes demo-key-tab' "$style"
grep -q '@keyframes demo-key-window' "$style"
grep -q '@keyframes demo-key-release' "$style"
grep -q '16.667%, 49.999% { opacity: 1; }' "$style"
grep -q '50%, 83.332% { opacity: 1; }' "$style"
grep -q '83.333%, 99.999% { opacity: 1; }' "$style"
grep -q '18.889%, 100%' "$style"
grep -q '52.222%, 100%' "$style"
grep -q '85.555%, 100%' "$style"
test "$(grep -o 'border-color: rgba(255, 255, 255, 0.28); background: rgba(255, 255, 255, 0.11); box-shadow: none; transform: none;' "$style" | wc -l | tr -d ' ')" = 5
grep -q 'box-shadow: 0 10px 28px rgba(0, 0, 0, 0.34)' "$style"
grep -q 'left: 50%; right: auto; bottom: 24px' "$style"
grep -q 'min-width: 220px' "$style"
grep -q 'font-size: 18px' "$style"
grep -q '.demo-layer--window-switcher { width: 68%; }' "$style"
grep -q '83.333%, 100% { opacity: 1; }' "$style"
grep -q '83.333%, 100% { opacity: 0; }' "$style"
grep -q 'prefers-reduced-motion: reduce' "$style"
grep -q 'demo-frame--poster' "$style"
if grep -qE '\.switcher-window|\.app-strip|\.app-tile|\.app-icon--' "$style"; then
  echo 'obsolete CSS switcher styles remain on landing page' >&2
  exit 1
fi

grep -q 'X-Content-Type-Options: nosniff' "$headers"
grep -q 'X-Frame-Options: DENY' "$headers"
grep -q 'Content-Security-Policy:' "$headers"
echo 'landing contract passed'
