#!/usr/bin/env bash
set -euo pipefail

page='docs/index.html'
style='docs/landing.css'
headers='docs/_headers'
icon='docs/AppIcon-256.png'
social_card='docs/social-card.png'
robots='docs/robots.txt'
sitemap='docs/sitemap.xml'
not_found='docs/404.html'

for path in "$page" "$style" "$headers" "$icon" "$social_card" "$robots" "$sitemap" "$not_found"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

test "$(grep -oE '<h1[[:space:]>]' "$page" | wc -l | tr -d ' ')" = 1
grep -qE '<main[[:space:]>]' "$page"
grep -qE '<footer[[:space:]>]' "$page"
grep -q '<title>SwitchTab — Free macOS App &amp; Window Switcher</title>' "$page"
grep -q '<link rel="canonical" href="https://switchtab.royjen.com/">' "$page"
grep -q '<meta name="robots" content="index, follow, max-image-preview:large">' "$page"
grep -q '<meta property="og:url" content="https://switchtab.royjen.com/">' "$page"
grep -q '<meta property="og:image" content="https://switchtab.royjen.com/social-card.png">' "$page"
grep -q '<meta name="twitter:card" content="summary_large_image">' "$page"
grep -q 'id="quick-answers"' "$page"
grep -q 'What is SwitchTab?' "$page"
grep -q 'How is SwitchTab different from macOS Command-Tab?' "$page"
grep -q 'Does SwitchTab require Screen Recording?' "$page"
grep -q 'Is SwitchTab free?' "$page"
test "$(grep -o '<script type="application/ld+json">' "$page" | wc -l | tr -d ' ')" = 1

python3 - "$page" <<'PY'
from html.parser import HTMLParser
import json
from pathlib import Path
import sys

class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.capture = False
        self.types = []
        self.buffers = []

    def handle_starttag(self, tag, attrs):
        if tag != "script":
            return
        attributes = dict(attrs)
        self.types.append(attributes.get("type"))
        self.capture = True
        self.buffers.append([])

    def handle_data(self, data):
        if self.capture:
            self.buffers[-1].append(data)

    def handle_endtag(self, tag):
        if tag == "script":
            self.capture = False

parser = Scripts()
parser.feed(Path(sys.argv[1]).read_text())
assert parser.types == ["application/ld+json"], parser.types
payload = json.loads("".join(parser.buffers[0]))
assert payload["@context"] == "https://schema.org"
nodes = {node["@type"]: node for node in payload["@graph"]}
assert nodes["WebSite"]["name"] == "SwitchTab"
assert nodes["WebSite"]["url"] == "https://switchtab.royjen.com/"
app = nodes["SoftwareApplication"]
assert app["operatingSystem"] == "macOS 14 or later"
assert app["offers"] == {"@type": "Offer", "price": "0", "priceCurrency": "USD"}
assert "aggregateRating" not in app
assert "review" not in app
PY
grep -q 'id="how-it-works"' "$page"
grep -q 'class="demo-reel"' "$page"
grep -q 'class="demo-menubar"' "$page"
grep -q 'class="demo-menubar__app demo-menubar__app--notes">Notes' "$page"
grep -q 'class="demo-menubar__app demo-menubar__app--preview">Preview' "$page"
if grep -q '' "$page"; then
  echo 'macOS menu bar must not depend on an Apple-only private-use glyph' >&2
  exit 1
fi
if grep -qE 'SwitchTab in motion|demo-window__bar|window-dot' "$page"; then
  echo 'outer demo frame still reads as an application window' >&2
  exit 1
fi
grep -q 'id="demo-motion-toggle"' "$page"
grep -q 'for="demo-motion-toggle"' "$page"
grep -q '<span class="demo-motion-control__name">Pause or play demo animation</span>' "$page"
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
if sed -n '/<figure class="demo-reel"/,/<\/figure>/p' "$page" | grep -qE 'Everyday|Developer|Creative|demo-scene__label|demo-scene--'; then
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
if grep -qiE '<video[[:space:]>]|<canvas[[:space:]>]|tracker|http://' "$page" "$style"; then
  echo 'landing page must stay free of video, canvas, trackers, and insecure URLs' >&2
  exit 1
fi
test "$(grep -oE '<script([[:space:]][^>]*)?>' "$page" | wc -l | tr -d ' ')" = 1 || {
  echo 'landing page must contain only its JSON-LD script' >&2
  exit 1
}
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
macos_user_root='/'"Users/"
if grep -R -qE "${macos_user_root}|file:///" docs; then
  echo 'public documentation contains a local filesystem identifier' >&2
  exit 1
fi

grep -qx 'User-agent: \*' "$robots"
grep -qx 'User-agent: OAI-SearchBot' "$robots"
grep -qx 'Sitemap: https://switchtab.royjen.com/sitemap.xml' "$robots"
grep -q '<loc>https://switchtab.royjen.com/</loc>' "$sitemap"
grep -q '<title>Page not found — SwitchTab</title>' "$not_found"
grep -q 'href="/"' "$not_found"
if grep -qE 'rel="canonical"|application/ld\+json' "$not_found"; then
  echo '404 page must not publish home-page search signals' >&2
  exit 1
fi
if grep -q 'href="index.html"' "$page"; then
  echo 'home links must use the canonical root path' >&2
  exit 1
fi

python3 - "$sitemap" "$social_card" <<'PY'
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET

sitemap, card = map(Path, sys.argv[1:])
root = ET.parse(sitemap).getroot()
namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
locations = [node.text for node in root.findall("s:url/s:loc", namespace)]
assert locations == [
    "https://switchtab.royjen.com/",
    "https://switchtab.royjen.com/guides/switch-windows-on-mac/",
], locations
data = card.read_bytes()[:24]
assert data[:8] == b"\x89PNG\r\n\x1a\n"
width, height = struct.unpack(">II", data[16:24])
assert (width, height) == (1200, 630), (width, height)
PY

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
grep -q '.demo-motion-control::after { position: absolute; top: 50%; left: 50%; width: max(100%, 44px); height: 44px; content: ""; transform: translate(-50%, -50%); }' "$style"
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
grep -q '.demo-layer--app-switcher { top: 50%; left: 50%; z-index: 6; width: 48%; opacity: 0; transform: translate(-50%, -50%); animation: demo-app-overlay var(--demo-cycle) var(--demo-ease) infinite; }' "$style"
grep -q '.demo-layer--window-switcher { top: 50%; left: 50%; z-index: 6; width: 48%; opacity: 0; transform: translate(-50%, -50%); animation: demo-window-overlay var(--demo-cycle) var(--demo-ease) infinite; }' "$style"
grep -q '.demo-layer--preview-final { top: 8%; left: 27%; z-index: 5; width: 62%; opacity: 0; animation: demo-preview-final var(--demo-cycle) var(--demo-ease) infinite; }' "$style"
grep -q '.demo-hud--apps { animation: demo-hud-apps var(--demo-cycle) var(--demo-ease) infinite; }' "$style"
grep -q '.demo-hud--windows { animation: demo-hud-windows var(--demo-cycle) var(--demo-ease) infinite; }' "$style"
grep -q '.demo-hud--release { animation: demo-hud-release var(--demo-cycle) var(--demo-ease) infinite; }' "$style"
if grep -qE '@keyframes demo-scene-cycle|@keyframes demo-frame-cycle' "$style"; then
  echo 'obsolete full-screen frame cycle remains on landing page' >&2
  exit 1
fi
grep -q '@keyframes demo-app-overlay' "$style"
grep -q '@keyframes demo-window-overlay' "$style"
grep -q '@keyframes demo-preview-final' "$style"
grep -q '@keyframes demo-menubar-notes' "$style"
grep -q '@keyframes demo-menubar-preview' "$style"
if grep -q 'steps(1, end)' "$style"; then
  echo 'demo transitions must interpolate rather than jump between frames' >&2
  exit 1
fi
grep -q '@keyframes demo-hud-apps' "$style"
grep -q '@keyframes demo-hud-windows' "$style"
grep -q '@keyframes demo-hud-release' "$style"
grep -q '@keyframes demo-key-tab' "$style"
grep -q '@keyframes demo-key-window' "$style"
grep -q '@keyframes demo-key-release' "$style"
grep -q '.demo-motion-toggle:checked ~ .demo-window .demo-key::before' "$style"
grep -q '.demo-key--held::before { opacity: 1; }' "$style"
test "$(grep -o 'class="demo-key demo-key--held"' "$page" | wc -l | tr -d ' ')" = 2
grep -q 'box-shadow: 0 10px 28px rgba(0, 0, 0, 0.34)' "$style"
grep -q 'left: 50%; right: auto; bottom: 24px' "$style"
grep -q 'min-width: 220px' "$style"
grep -q 'font-size: 18px' "$style"
grep -q '.demo-layer--window-switcher { width: 68%; }' "$style"
grep -q '.demo-layer--app-switcher { width: 48%; }' "$style"
grep -q 'prefers-reduced-motion: reduce' "$style"
grep -q 'demo-frame--poster' "$style"
if grep -qE '\.switcher-window|\.app-strip|\.app-tile|\.app-icon--' "$style"; then
  echo 'obsolete CSS switcher styles remain on landing page' >&2
  exit 1
fi

python3 - "$page" "$style" <<'PY'
from pathlib import Path
import re
import sys

page, style = map(Path, sys.argv[1:])
html = page.read_text()
css = style.read_text()
desktop_css = css.split('@media', 1)[0]

def declarations(selector):
    match = re.search(rf'{re.escape(selector)}\s*(?:,[^{{}}]+)?\{{([^}}]*)\}}', css, re.DOTALL)
    assert match, selector
    return {
        name.strip(): value.strip()
        for name, value in re.findall(r'([\w-]+)\s*:\s*([^;]+);', match.group(1))
    }

def declarations_for_class(class_name):
    found = {}
    for selector, body in re.findall(r'([^{}]+)\{([^{}]*)\}', desktop_css, re.DOTALL):
        if class_name in selector:
            found.update({
                name.strip(): value.strip()
                for name, value in re.findall(r'([\w-]+)\s*:\s*([^;]+);', body)
            })
    assert found, class_name
    return found

def animation_frames(name):
    match = re.search(rf'@keyframes {re.escape(name)}\s*\{{((?:[^{{}}]|\{{[^{{}}]*\}})*)\}}', css)
    assert match, name
    frames = {}
    for offsets, body in re.findall(r'([^{}]+)\{([^{}]*)\}', match.group(1)):
        values = dict(re.findall(r'([\w-]+)\s*:\s*([^;]+);', body))
        assert set(values) <= {'opacity', 'transform'}, (name, values)
        for offset in re.findall(r'(\d+(?:\.\d+)?)%', offsets):
            frames[float(offset)] = values
    return frames

for name, enter_start, enter_end, exit_start, exit_end in (
    ('demo-app-overlay', 16, 18, 49, 51),
    ('demo-window-overlay', 50, 52, 76, 78),
    ('demo-preview-final', 76, 79, 95, 98),
    ('demo-menubar-preview', 76, 79, 95, 98),
    ('demo-hud-apps', 12, 14, 44, 46),
    ('demo-hud-windows', 46, 48, 73, 75),
    ('demo-hud-release', 73, 75, 94, 96),
):
    frames = animation_frames(name)
    assert frames[enter_start]['opacity'] == frames[exit_end]['opacity'] == '0'
    assert frames[enter_end]['opacity'] == frames[exit_start]['opacity'] == '1'
    assert frames[0] == frames[100], name

for key, press_start, press_end in (('tab', 14, 15), ('window', 48, 49)):
    frames = animation_frames(f'demo-key-{key}')
    assert frames[press_start]['transform'] == 'translateY(0) scale(1)'
    assert frames[press_end]['transform'] == 'translateY(var(--demo-key-travel)) scale(var(--demo-key-scale))'
    assert frames[0] == frames[100]
    highlight = animation_frames(f'demo-key-{key}-highlight')
    assert highlight[press_start]['opacity'] == '0' and highlight[press_end]['opacity'] == '1'
release = animation_frames('demo-key-release')
assert release[76]['transform'] == 'translateY(var(--demo-key-travel)) scale(var(--demo-key-scale))'
assert release[78]['transform'] == 'translateY(0) scale(1)'
highlight = animation_frames('demo-key-release-highlight')
assert highlight[76]['opacity'] == '1' and highlight[78]['opacity'] == '0'
notes = animation_frames('demo-menubar-notes')
assert notes[76]['opacity'] == notes[98]['opacity'] == '1'
assert notes[79]['opacity'] == notes[95]['opacity'] == '0'
assert (95 - 79) * 9 / 100 >= 1.4
assert '.demo-key::before' in css.split('@media (prefers-reduced-motion: reduce)', 1)[1]

tokens = declarations(':root')
for token, size in (
    ('body', '1rem'), ('lede', '1.125rem'), ('control', '.9375rem'),
    ('secondary', '.875rem'), ('meta', '.8125rem'), ('eyebrow', '.75rem'),
):
    assert tokens[f'--type-{token}'] == size, token
assert tokens['--text-faint'] == '#a2a8b8'
for selector, token in (
    ('body', 'body'), ('.hero-lede', 'lede'), ('.button', 'control'),
    ('.button--small', 'control'), ('.nav-link', 'secondary'),
    ('.text-link', 'secondary'), ('.install-option__label', 'secondary'),
    ('.source-cta .install-note', 'secondary'),
    ('.source-command code', 'secondary'), ('.guide-link', 'body'),
    ('.answer-card p', 'body'), ('.source-cta p', 'body'),
    ('.section-intro', 'body'), ('.trust-row', 'meta'),
    ('.demo-motion-control', 'meta'), ('.demo-reel figcaption', 'meta'),
    ('.brand--footer', 'meta'), ('.footer-note', 'meta'),
    ('.eyebrow', 'eyebrow'), ('.demo-hud small', 'meta'),
):
    assert declarations(selector)['font-size'] == f'var(--type-{token})', selector
command = declarations('.source-command code')
assert command['min-width'] == '0' and command['white-space'] == 'normal'
assert command['overflow-wrap'] == 'anywhere' and 'overflow' not in command
assert declarations('.source-command')['padding'].split()[0] == '12px'
assert declarations('.source-command a')['flex-shrink'] == '0'
mobile_css = css.split('@media (max-width: 640px)', 1)[1].split('@container', 1)[0]
assert '.hero-lede { font-size: var(--type-body); }' in mobile_css
for selector in ('.demo-motion-control', '.demo-hud small'):
    match = re.search(rf'{re.escape(selector)}\s*\{{([^}}]*)\}}', mobile_css)
    assert not match or 'font-size:' not in match.group(1), selector
assert declarations('.demo-reel')['--demo-menu-type'] == '9px'
disclosure = declarations('.agent-install')
assert disclosure['margin-top'] == '16px' and disclosure['padding'] == '24px'
assert declarations('.agent-install summary')['min-height'] == '44px'
assert declarations('.agent-install summary')['font-size'] == 'var(--type-control)'
textarea = declarations('.agent-install textarea')
assert textarea['font-size'] == 'var(--type-body)' and textarea['line-height'] == '1.65'
assert textarea['width'] == '100%' and textarea['min-height'] == '16rem'
assert textarea['resize'] == 'vertical' and textarea['overflow-wrap'] == 'anywhere'
assert textarea['white-space'] == 'pre-wrap'
assert 'monospace' in textarea['font-family']
assert declarations('.agent-install summary:focus-visible')['outline']
assert declarations('.agent-install textarea:focus-visible')['outline']

assert 'class="trust-row trust-row--band" aria-label="Product highlights"' in html
hero = declarations('.hero')
assert hero['display'] == 'grid'
tracks = re.findall(r'minmax\(\s*([^,]+),\s*([^)]+)\)', hero['grid-template-columns'])
assert len(tracks) == 2 and [minimum.strip() for minimum, _ in tracks] == ['0', '0']
assert '--radius-lg: 24px;' in css
assert '--radius-md: 16px;' in css
assert not re.search(r'^\s*--(?:purple|green|amber)\s*:', css, re.MULTILINE)
assert declarations('.demo-window')['transform'].startswith('perspective(')
step = declarations('.step-card')
assert 'border-top' in step and 'background' not in step and 'border-radius' not in step
assert 'padding' in step
assert declarations('.feature-grid')['grid-template-columns'].startswith('repeat(12,')
for class_name, span in (('.feature-card--blue', 'span 7'), ('.feature-card--purple', 'span 5'), ('.feature-card--amber', 'span 7'), ('.feature-card--green', 'span 5')):
    card = declarations_for_class(class_name)
    assert card['grid-column'] == span and card['color'] == 'var(--blue)'
assert declarations('.trust-row--band')['grid-template-columns'] == 'repeat(4, 1fr)'
assert declarations('.hero .eyebrow')['justify-content'] == 'center'
mobile = re.search(r'@media\s*\(max-width:\s*930px\)\s*\{.*?\.hero\s*\{([^}]*)\}', css, re.DOTALL)
assert mobile and 'grid-template-columns: 1fr' in mobile.group(1)
mobile_band = re.search(r'@media\s*\(max-width:\s*640px\)\s*\{.*?\.trust-row--band\s*\{([^}]*)\}', css, re.DOTALL)
assert mobile_band and 'grid-template-columns: repeat(2, 1fr)' in mobile_band.group(1)
PY

grep -q 'X-Content-Type-Options: nosniff' "$headers"
grep -q 'X-Frame-Options: DENY' "$headers"
grep -q 'Content-Security-Policy:' "$headers"
echo 'landing contract passed'
