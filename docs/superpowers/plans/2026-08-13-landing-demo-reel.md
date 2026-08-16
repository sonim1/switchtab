# SwitchTab Landing Demo Reel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the landing hero's CSS-drawn switcher with a wide, continuously looping 18-frame reel built from real SwitchTab and macOS screenshots.

**Architecture:** Capture three real six-frame workflows into an ignored working directory, optimize them into local WebP assets, and render them as three CSS-timed scene stacks inside one semantic figure. The page remains static and script-free: HTML owns structure and accessibility, CSS owns the 18-second loop, and the shell contract enforces asset count, size, and security boundaries.

**Tech Stack:** HTML5, CSS animations, WebP, `screencapture`, `cwebp`, Bash contract tests, static Cloudflare Pages hosting.

---

## File structure

- Create `docs/demo/*.webp`: 18 optimized, privacy-safe screenshots grouped into Everyday, Developer, and Creative scenarios.
- Modify `docs/index.html:27-76`: center the hero and replace the CSS illustration with the semantic demo figure and 18 local image layers.
- Modify `docs/landing.css:108-165,215-235`: remove obsolete fake-switcher styles and add the wide frame, timed scenes, key HUD, responsive crop, and reduced-motion poster.
- Modify `scripts/tests/landing-contract-test.sh`: enforce the exact asset manifest, 4 MiB complete-set limit, 250 KiB poster limit, reel markup, CSS timing hooks, and continued script-free behavior.
- Use `.build/landing-demo-captures/` for lossless PNG capture originals. It is already ignored and must not be committed.

## Asset manifest

The names are part of the page contract and must remain stable:

```text
docs/demo/everyday-01-notes-working.webp
docs/demo/everyday-02-app-shortcut.webp
docs/demo/everyday-03-app-overlay.webp
docs/demo/everyday-04-safari-selected.webp
docs/demo/everyday-05-window-overlay.webp
docs/demo/everyday-06-github-focused.webp
docs/demo/developer-01-ghostty-working.webp
docs/demo/developer-02-app-shortcut.webp
docs/demo/developer-03-app-overlay.webp
docs/demo/developer-04-xcode-selected.webp
docs/demo/developer-05-window-overlay.webp
docs/demo/developer-06-code-focused.webp
docs/demo/creative-01-browser-working.webp
docs/demo/creative-02-app-shortcut.webp
docs/demo/creative-03-app-overlay.webp
docs/demo/creative-04-preview-selected.webp
docs/demo/creative-05-window-overlay.webp
docs/demo/creative-06-design-focused.webp
```

### Task 1: Lock the screenshot asset contract

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Add the failing asset manifest test**

First expand the existing forbidden-content condition so it also rejects video and canvas elements:

```bash
if grep -qiE '<script[[:space:]>]|<video[[:space:]>]|<canvas[[:space:]>]|tracker|analytics|http://' "$page" "$style"; then
  echo 'landing page must stay free of scripts, video, canvas, trackers, and insecure URLs' >&2
  exit 1
fi
if grep -qiE 'src="https?://' "$page"; then
  echo 'landing page images must be served locally' >&2
  exit 1
fi
```

Then append this block before the existing header checks:

```bash
demo_dir='docs/demo'
demo_assets=(
  everyday-01-notes-working.webp
  everyday-02-app-shortcut.webp
  everyday-03-app-overlay.webp
  everyday-04-safari-selected.webp
  everyday-05-window-overlay.webp
  everyday-06-github-focused.webp
  developer-01-ghostty-working.webp
  developer-02-app-shortcut.webp
  developer-03-app-overlay.webp
  developer-04-xcode-selected.webp
  developer-05-window-overlay.webp
  developer-06-code-focused.webp
  creative-01-browser-working.webp
  creative-02-app-shortcut.webp
  creative-03-app-overlay.webp
  creative-04-preview-selected.webp
  creative-05-window-overlay.webp
  creative-06-design-focused.webp
)

test "${#demo_assets[@]}" = 18
for asset in "${demo_assets[@]}"; do
  test -s "$demo_dir/$asset" || {
    echo "missing landing demo asset: $demo_dir/$asset" >&2
    exit 1
  }
done

test "$(find "$demo_dir" -type f -name '*.webp' | wc -l | tr -d ' ')" = 18
poster_bytes="$(stat -f '%z' "$demo_dir/everyday-01-notes-working.webp")"
total_bytes="$(find "$demo_dir" -type f -name '*.webp' -exec stat -f '%z' {} \; | awk '{ total += $1 } END { print total + 0 }')"
test "$poster_bytes" -le 256000 || {
  echo "landing demo poster exceeds 250 KiB: $poster_bytes bytes" >&2
  exit 1
}
test "$total_bytes" -le 4194304 || {
  echo "landing demo assets exceed 4 MiB: $total_bytes bytes" >&2
  exit 1
}
```

- [ ] **Step 2: Run the contract and verify the expected failure**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL at `missing landing demo asset: docs/demo/everyday-01-notes-working.webp`.

- [ ] **Step 3: Check the test-only diff**

Run:

```bash
rtk git diff --check
rtk git diff -- scripts/tests/landing-contract-test.sh
```

Expected: clean whitespace check and only the asset contract block added. Do not commit the knowingly failing state.

### Task 2: Capture and optimize the 18 real product frames

**Files:**
- Create: `docs/demo/everyday-*.webp`
- Create: `docs/demo/developer-*.webp`
- Create: `docs/demo/creative-*.webp`
- Local only: `.build/landing-demo-captures/*.png`

**Required sub-skill:** Use `computer-use` for desktop setup and real application interaction. Do not synthesize or redraw app windows, icons, thumbnails, or SwitchTab UI.

- [ ] **Step 1: Prepare a clean capture workspace**

Run:

```bash
rtk proxy mkdir -p .build/landing-demo-captures docs/demo
rtk proxy open -a Notes
rtk proxy open -a Safari
rtk proxy open -a Ghostty
rtk proxy open -a Xcode
rtk proxy open -a 'Brave Browser'
rtk proxy open -a Preview
rtk proxy open -a SwitchTab
```

Expected: all seven apps launch. If an app name fails, resolve the installed application name with `rtk ls /Applications` before continuing; do not substitute a different scenario silently.

- [ ] **Step 2: Create privacy-safe sample content**

Prepare these visible states using local, non-account content:

```text
Everyday
- Notes note titled “Launch checklist” with generic checklist copy.
- Safari window 1: public SwitchTab GitHub repository.
- Safari window 2: a neutral local or public documentation page.

Developer
- Ghostty: repository root with a harmless `rtk git status --short` result.
- Xcode window 1: SwitchTab project with AppDelegate.swift open.
- Xcode window 2: SwitchTab project with SwitcherSession.swift open.

Creative
- Brave Browser: the local SwitchTab landing page.
- Preview window 1: a generic “Switch faster” artboard.
- Preview window 2: a generic shortcut or layout artboard.
```

Before capture, enable Do Not Disturb, hide unrelated apps, close private tabs/documents, use a neutral desktop wallpaper, and verify the menu bar contains no account name, VPN identity, private calendar text, or notification badge.

- [ ] **Step 3: Capture the Everyday sequence**

Use a consistent 16:10 capture region and `screencapture -x -R x,y,width,height <path>`. Resolve the region once, then reuse the exact coordinates for all 18 captures. Capture these states:

```text
everyday-01-notes-working.png     Notes frontmost, no overlay
everyday-02-app-shortcut.png      Same workspace immediately before overlay; web HUD will show ⌘Tab
everyday-03-app-overlay.png       Real SwitchTab application overlay open
everyday-04-safari-selected.png   Safari selected in real application overlay
everyday-05-window-overlay.png    Real Safari window list after held-modifier mode handoff
everyday-06-github-focused.png    Target GitHub Safari window focused, overlay dismissed
```

For held-modifier frames, schedule the capture with a short delay, then trigger the real SwitchTab shortcut before the delay expires:

```bash
rtk proxy screencapture -x -T 5 -R x,y,width,height .build/landing-demo-captures/everyday-03-app-overlay.png
```

Replace `x,y,width,height` with the measured region. Repeat for each state with its manifest filename.

- [ ] **Step 4: Capture the Developer sequence**

Capture the same six states with Ghostty as the starting app and Xcode as the selected app:

```text
developer-01-ghostty-working.png
developer-02-app-shortcut.png
developer-03-app-overlay.png
developer-04-xcode-selected.png
developer-05-window-overlay.png
developer-06-code-focused.png
```

The fifth frame must show real Xcode window thumbnails; the sixth must focus the intended Xcode source window.

- [ ] **Step 5: Capture the Creative sequence**

Capture the same six states with Brave Browser as the starting app and Preview as the selected app:

```text
creative-01-browser-working.png
creative-02-app-shortcut.png
creative-03-app-overlay.png
creative-04-preview-selected.png
creative-05-window-overlay.png
creative-06-design-focused.png
```

The fifth frame must show real Preview window thumbnails; the sixth must focus the intended design document window.

- [ ] **Step 6: Verify capture dimensions and privacy before conversion**

Run:

```bash
rtk proxy find .build/landing-demo-captures -type f -name '*.png' -print0 | rtk proxy xargs -0 -n1 rtk proxy sips -g pixelWidth -g pixelHeight
rtk proxy find .build/landing-demo-captures -type f -name '*.png' | rtk proxy wc -l
```

Expected: exactly 18 PNG files, all with identical dimensions. Visually inspect every PNG at full size. Reject and recapture any frame containing personal data, notification banners, cursor obstruction, mismatched crop, fake UI, or a SwitchTab state that does not match current product behavior.

- [ ] **Step 7: Convert captures to bounded WebP assets**

Run this from the repository root:

```bash
for source in .build/landing-demo-captures/*.png; do
  target="docs/demo/$(basename "${source%.png}").webp"
  rtk proxy cwebp -quiet -q 76 -m 6 -resize 1440 900 "$source" -o "$target"
done
```

Then check count and size:

```bash
rtk proxy find docs/demo -type f -name '*.webp' | rtk proxy wc -l
rtk proxy du -ck docs/demo/*.webp
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: 18 WebP files; poster at or below 256000 bytes; complete set at or below 4194304 bytes. The contract should now reach the existing checks and print `landing contract passed`. If size exceeds the limit, reconvert all files at `-q 72`; do not vary quality per scenario.

- [ ] **Step 8: Commit only optimized assets and the passing asset contract**

Run:

```bash
rtk git status --short
rtk git add docs/demo scripts/tests/landing-contract-test.sh
rtk git commit -m "test: add landing demo asset contract"
```

Expected: `.build/landing-demo-captures/` does not appear in the commit.

### Task 3: Replace the fake hero illustration with semantic reel markup

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh`
- Modify: `docs/index.html:27-76`

- [ ] **Step 1: Add failing reel-structure checks**

Append this block after the existing `#how-it-works` check:

```bash
grep -q 'class="demo-reel"' "$page"
grep -q 'class="demo-scene demo-scene--everyday"' "$page"
grep -q 'class="demo-scene demo-scene--developer"' "$page"
grep -q 'class="demo-scene demo-scene--creative"' "$page"
scenario_order="$(grep -oE 'demo-scene--(everyday|developer|creative)' "$page" | tr '\n' ' ')"
test "$scenario_order" = 'demo-scene--everyday demo-scene--developer demo-scene--creative '
test "$(grep -oE 'src="demo/[^"]+\.webp"' "$page" | wc -l | tr -d ' ')" = 18
test "$(grep -o 'class="demo-frame' "$page" | wc -l | tr -d ' ')" = 18
if grep -qE 'switcher-window|app-strip|app-tile|app-icon--' "$page"; then
  echo 'obsolete CSS switcher markup remains on landing page' >&2
  exit 1
fi
```

- [ ] **Step 2: Run the contract and verify the expected failure**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL because `class="demo-reel"` is absent.

- [ ] **Step 3: Replace the current hero block**

Replace `docs/index.html:27-76` with this structure. Keep all sections after the hero unchanged.

```html
      <section class="hero shell" aria-labelledby="hero-title">
        <div class="hero-copy">
          <p class="eyebrow"><span class="eyebrow-dot" aria-hidden="true"></span> No swiping. No Mission Control. Just the window.</p>
          <h1 id="hero-title">Your apps,<br><em>one keystroke away.</em></h1>
          <p class="hero-lede">SwitchTab gives your apps and windows a calm, focused shortcut. Use <kbd>⌘</kbd><kbd>Tab</kbd> for apps and <kbd>⌘</kbd><kbd>`</kbd> for windows in the app you are using.</p>
          <div class="hero-actions">
            <a class="button button--primary" href="#install">Install SwitchTab <span aria-hidden="true">→</span></a>
            <a class="text-link" href="#how-it-works">See how it works <span aria-hidden="true">↓</span></a>
          </div>
          <ul class="trust-row" aria-label="Product highlights">
            <li><span class="trust-icon" aria-hidden="true">⌘</span>macOS 14+</li>
            <li><span class="trust-icon trust-icon--spark" aria-hidden="true">✦</span>Native Swift</li>
            <li><span class="trust-icon" aria-hidden="true">∞</span>Free forever</li>
            <li><span class="trust-icon" aria-hidden="true">✓</span>Signed &amp; notarized by Apple</li>
          </ul>
        </div>

        <figure class="demo-reel" aria-labelledby="demo-caption">
          <div class="demo-window" aria-hidden="true">
            <div class="demo-window__bar">
              <span class="window-dot window-dot--red"></span>
              <span class="window-dot window-dot--yellow"></span>
              <span class="window-dot window-dot--green"></span>
              <span class="demo-window__title">SwitchTab in motion</span>
            </div>
            <div class="demo-stage">
              <div class="demo-scene demo-scene--everyday">
                <span class="demo-scene__label">Everyday</span>
                <img class="demo-frame demo-frame--poster" src="demo/everyday-01-notes-working.webp" alt="" width="1440" height="900" decoding="async" fetchpriority="high">
                <img class="demo-frame" src="demo/everyday-02-app-shortcut.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/everyday-03-app-overlay.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/everyday-04-safari-selected.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/everyday-05-window-overlay.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/everyday-06-github-focused.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <span class="demo-hud demo-hud--apps"><kbd>⌘</kbd><kbd>Tab</kbd></span>
                <span class="demo-hud demo-hud--windows"><small>keep holding</small><kbd>⌘</kbd><kbd>`</kbd></span>
                <span class="demo-hud demo-hud--release"><small>release</small><kbd>⌘</kbd></span>
              </div>
              <div class="demo-scene demo-scene--developer">
                <span class="demo-scene__label">Developer</span>
                <img class="demo-frame" src="demo/developer-01-ghostty-working.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/developer-02-app-shortcut.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/developer-03-app-overlay.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/developer-04-xcode-selected.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/developer-05-window-overlay.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/developer-06-code-focused.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <span class="demo-hud demo-hud--apps"><kbd>⌘</kbd><kbd>Tab</kbd></span>
                <span class="demo-hud demo-hud--windows"><small>keep holding</small><kbd>⌘</kbd><kbd>`</kbd></span>
                <span class="demo-hud demo-hud--release"><small>release</small><kbd>⌘</kbd></span>
              </div>
              <div class="demo-scene demo-scene--creative">
                <span class="demo-scene__label">Creative</span>
                <img class="demo-frame" src="demo/creative-01-browser-working.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/creative-02-app-shortcut.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/creative-03-app-overlay.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/creative-04-preview-selected.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/creative-05-window-overlay.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <img class="demo-frame" src="demo/creative-06-design-focused.webp" alt="" width="1440" height="900" loading="lazy" decoding="async">
                <span class="demo-hud demo-hud--apps"><kbd>⌘</kbd><kbd>Tab</kbd></span>
                <span class="demo-hud demo-hud--windows"><small>keep holding</small><kbd>⌘</kbd><kbd>`</kbd></span>
                <span class="demo-hud demo-hud--release"><small>release</small><kbd>⌘</kbd></span>
              </div>
            </div>
          </div>
          <figcaption id="demo-caption">Jump from an app to the exact window you want without releasing Command.</figcaption>
        </figure>
      </section>
```

- [ ] **Step 4: Run the structure contract**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk git diff --check
```

Expected: `landing contract passed`; whitespace check exits 0. The page may be visually unstyled until Task 4.

- [ ] **Step 5: Commit the semantic reel structure**

Run:

```bash
rtk git add docs/index.html scripts/tests/landing-contract-test.sh
rtk git commit -m "feat: add landing demo reel structure"
```

### Task 4: Implement the CSS-only 18-second animation

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh`
- Modify: `docs/landing.css:108-165,215-235`

- [ ] **Step 1: Add failing animation contract checks**

Append these checks after the asset-size block:

```bash
grep -q -- '--demo-cycle: 18s' "$style"
grep -q '@keyframes demo-scene-cycle' "$style"
grep -q '@keyframes demo-frame-cycle' "$style"
grep -q '0%, 33.332% { opacity: 1; }' "$style"
grep -q '33.333%, 100% { opacity: 0; }' "$style"
grep -q '0%, 16.666% { opacity: 1; }' "$style"
grep -q '16.667%, 100% { opacity: 0; }' "$style"
test "$(grep -o 'steps(1, end)' "$style" | wc -l | tr -d ' ')" = 2
grep -q '@keyframes demo-hud-apps' "$style"
grep -q 'prefers-reduced-motion: reduce' "$style"
grep -q 'demo-frame--poster' "$style"
if grep -qE '\.switcher-window|\.app-strip|\.app-tile|\.app-icon--' "$style"; then
  echo 'obsolete CSS switcher styles remain on landing page' >&2
  exit 1
fi
```

The narrow percentage boundaries make desktop frames and scenarios cut directly without a visible brightness dip. Only the keyboard HUD fades.

- [ ] **Step 2: Run the contract and verify the expected failure**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL because `--demo-cycle: 18s` is absent.

- [ ] **Step 3: Replace hero and fake-switcher CSS**

Replace the current `.hero` through `.switcher-window figcaption` block with the following CSS:

```css
.hero {
  position: relative;
  z-index: 1;
  display: flex;
  min-height: auto;
  flex-direction: column;
  align-items: center;
  gap: 54px;
  padding-top: 88px;
  padding-bottom: 96px;
  text-align: center;
}

.hero-copy { position: relative; z-index: 1; max-width: 790px; }
.eyebrow { display: flex; align-items: center; justify-content: center; gap: 9px; margin: 0 0 18px; color: var(--blue); font-size: 11px; font-weight: 700; letter-spacing: 0.13em; line-height: 1.2; text-transform: uppercase; }
.eyebrow-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--blue); box-shadow: 0 0 0 5px rgba(109, 168, 255, 0.12); }
h1, h2, h3, p { margin-top: 0; }
h1, h2, h3 { letter-spacing: -0.055em; }
h1 { max-width: 780px; margin: 0 auto 26px; font-size: clamp(52px, 6.2vw, 85px); font-weight: 620; line-height: 0.98; }
h1 em, h2 em { color: var(--text-soft); font-style: normal; }
.hero-lede { max-width: 600px; margin: 0 auto 30px; color: var(--text-soft); font-size: 16px; line-height: 1.7; }
kbd { display: inline-flex; align-items: center; justify-content: center; min-width: 23px; height: 23px; margin: 0 2px; padding: 0 5px; border: 1px solid var(--line); border-radius: 6px; background: var(--surface-soft); color: var(--text); font-family: inherit; font-size: 12px; font-weight: 600; vertical-align: 1px; }
.hero-actions { display: flex; align-items: center; justify-content: center; gap: 23px; }
.text-link { color: var(--text-soft); font-size: 13px; font-weight: 600; transition: color 180ms ease; }
.text-link:hover { color: var(--text); }
.trust-row { display: flex; flex-wrap: wrap; justify-content: center; gap: 18px 26px; margin: 42px 0 0; padding: 0; list-style: none; color: var(--text-faint); font-size: 11px; }
.trust-row li { display: inline-flex; align-items: center; gap: 7px; }
.trust-icon { display: inline-flex; align-items: center; justify-content: center; width: 18px; height: 18px; border: 1px solid var(--line); border-radius: 5px; color: var(--text-soft); font-size: 11px; }
.trust-icon--spark { color: var(--blue); }

.demo-reel {
  --demo-cycle: 18s;
  position: relative;
  width: min(100%, 1080px);
  margin: 0;
}

.demo-reel::before {
  position: absolute;
  inset: -12% 8% 4%;
  border-radius: 50%;
  background: rgba(58, 107, 196, 0.2);
  content: "";
  filter: blur(95px);
  pointer-events: none;
}

.demo-window { position: relative; overflow: hidden; border: 1px solid rgba(255, 255, 255, 0.17); border-radius: var(--radius-lg); background: rgba(18, 21, 30, 0.92); box-shadow: var(--shadow); }
.demo-window__bar { position: relative; z-index: 2; display: flex; align-items: center; gap: 7px; height: 43px; padding: 0 17px; border-bottom: 1px solid var(--line-soft); background: rgba(255, 255, 255, 0.04); }
.window-dot { width: 9px; height: 9px; border-radius: 50%; opacity: 0.8; }
.window-dot--red { background: #ff625c; }.window-dot--yellow { background: #ffbd44; }.window-dot--green { background: #28c840; }
.demo-window__title { position: absolute; left: 50%; transform: translateX(-50%); color: var(--text-faint); font-size: 10px; letter-spacing: 0.04em; }
.demo-stage { position: relative; aspect-ratio: 16 / 10; overflow: hidden; background: #10141c; }
.demo-scene { position: absolute; inset: 0; opacity: 0; animation: demo-scene-cycle var(--demo-cycle) steps(1, end) infinite; }
.demo-scene--everyday { animation-delay: 0s; }
.demo-scene--developer { animation-delay: -12s; }
.demo-scene--creative { animation-delay: -6s; }
.demo-frame { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0; animation: demo-frame-cycle 6s steps(1, end) infinite; }
.demo-frame:nth-of-type(1) { animation-delay: 0s; }
.demo-frame:nth-of-type(2) { animation-delay: -5s; }
.demo-frame:nth-of-type(3) { animation-delay: -4s; }
.demo-frame:nth-of-type(4) { animation-delay: -3s; }
.demo-frame:nth-of-type(5) { animation-delay: -2s; }
.demo-frame:nth-of-type(6) { animation-delay: -1s; }
.demo-scene__label { position: absolute; top: 18px; left: 18px; z-index: 3; padding: 6px 10px; border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 999px; background: rgba(7, 9, 13, 0.64); color: rgba(255, 255, 255, 0.8); font-size: 10px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; backdrop-filter: blur(12px); }
.demo-hud { position: absolute; right: 18px; bottom: 18px; z-index: 3; display: flex; align-items: center; gap: 4px; padding: 7px 9px; border: 1px solid rgba(255, 255, 255, 0.18); border-radius: 10px; background: rgba(7, 9, 13, 0.68); opacity: 0; backdrop-filter: blur(12px); }
.demo-hud small { margin-right: 2px; color: var(--text-soft); font-size: 9px; }
.demo-hud kbd { margin: 0; background: rgba(255, 255, 255, 0.08); }
.demo-hud--apps { animation: demo-hud-apps 6s linear infinite; }
.demo-hud--windows { animation: demo-hud-windows 6s linear infinite; }
.demo-hud--release { animation: demo-hud-release 6s linear infinite; }
.demo-reel figcaption { padding-top: 14px; color: var(--text-faint); font-size: 11px; text-align: center; }

@keyframes demo-scene-cycle {
  0%, 33.332% { opacity: 1; }
  33.333%, 100% { opacity: 0; }
}

@keyframes demo-frame-cycle {
  0%, 16.666% { opacity: 1; }
  16.667%, 100% { opacity: 0; }
}

@keyframes demo-hud-apps { 0%, 6% { opacity: 0; } 10%, 42% { opacity: 1; } 47%, 100% { opacity: 0; } }
@keyframes demo-hud-windows { 0%, 45% { opacity: 0; } 50%, 76% { opacity: 1; } 81%, 100% { opacity: 0; } }
@keyframes demo-hud-release { 0%, 79% { opacity: 0; } 84%, 94% { opacity: 1; } 100% { opacity: 0; } }
```

- [ ] **Step 4: Replace obsolete responsive and fallback rules**

Change the hero-related rules inside existing media queries to:

```css
@media (max-width: 930px) {
  .hero { gap: 42px; padding-top: 76px; }
  .hero-copy { max-width: 700px; }
  .feature-grid { grid-template-columns: 1fr; }
  .feature-card { min-height: auto; }
  .feature-card h3 { max-width: 360px; }
  .source-cta__inner { align-items: flex-start; flex-direction: column; }
}

@media (max-width: 640px) {
  .shell { width: min(calc(100% - 32px), var(--max-width)); }
  .site-header { padding-top: 18px; }
  .header-nav { gap: 12px; }
  .nav-link { display: none; }
  .hero { gap: 38px; padding-top: 65px; padding-bottom: 67px; }
  .hero-lede { font-size: 14px; }
  .hero-actions { flex-direction: column; gap: 19px; }
  .trust-row { gap: 13px 18px; margin-top: 35px; }
  .demo-window__bar { height: 36px; padding-inline: 12px; }
  .demo-window__title { font-size: 9px; }
  .demo-stage { aspect-ratio: 4 / 3; }
  .demo-frame { left: 50%; width: auto; max-width: none; transform: translateX(-50%); }
  .demo-scene__label { top: 10px; left: 10px; }
  .demo-hud { right: 10px; bottom: 10px; }
  .how-it-works, .features { padding-top: 62px; padding-bottom: 74px; }
  .steps { grid-template-columns: 1fr; gap: 10px; }
  .step-connector { transform: rotate(90deg); }
  .step-card { min-height: auto; padding: 20px; }
  .section-heading--split { align-items: flex-start; flex-direction: column; gap: 17px; }
  .section-intro { max-width: 320px; }
  .source-cta { padding-bottom: 0; }
  .source-cta__inner { gap: 29px; padding: 30px 23px; }
  .source-command { width: 100%; }
  .site-footer { align-items: flex-start; flex-direction: column; gap: 19px; }
  .footer-nav { flex-wrap: wrap; gap: 8px 16px; }
  .footer-note { order: 3; }
}

@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after { transition-duration: 0.01ms !important; }
  .demo-scene, .demo-frame, .demo-hud { animation: none !important; opacity: 0; }
  .demo-scene--everyday { opacity: 1; }
  .demo-frame--poster { opacity: 1; }
}

@supports not (backdrop-filter: blur(1px)) {
  .demo-window { background: var(--surface-strong); }
  .demo-scene__label, .demo-hud { background: rgba(7, 9, 13, 0.9); }
}
```

- [ ] **Step 5: Run animation and security contracts**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk git diff --check
rtk grep -n -E 'switcher-window|app-strip|app-tile|app-icon--|<script|<video|<canvas' docs/index.html docs/landing.css
```

Expected: contract prints `landing contract passed`; whitespace check exits 0; final search prints no matches.

- [ ] **Step 6: Commit the reel animation**

Run:

```bash
rtk git add docs/landing.css scripts/tests/landing-contract-test.sh
rtk git commit -m "feat: animate landing demo reel"
```

### Task 5: Run visual, responsive, accessibility, and regression QA

**Files:**
- Verify: `docs/index.html`
- Verify: `docs/landing.css`
- Verify: `docs/demo/*.webp`
- Verify: `scripts/tests/landing-contract-test.sh`
- Modify only if QA identifies a scoped defect.

**Required sub-skills:** Use `browse` or `agent-browser` for page QA and `before-and-after` for the final desktop comparison. Use `verification-before-completion` before any completion claim.

- [ ] **Step 1: Start a local static server**

Run:

```bash
rtk proxy python3 -m http.server 4173 --directory docs
```

Expected: server remains available at `http://127.0.0.1:4173/`. Run it in a persistent session so browser checks can continue.

- [ ] **Step 2: Verify the desktop presentation and full timeline**

At 1440×1000, verify:

```text
- Hero copy and actions are centered.
- Wide demo begins immediately below the trust row.
- No CSS-drawn application icons or fake SwitchTab tiles remain.
- Everyday appears first, Developer near 6s, Creative near 12s, and Everyday returns near 18s.
- Every scene shows all six frames in order.
- Frame and scenario cuts contain no white/blank flash or brightness dip.
- Full desktop never slides laterally.
- Keyboard HUD changes from ⌘Tab to held-Command window handoff to release.
- Caption remains stable and does not move the page.
```

Capture one desktop screenshot for before/after comparison and inspect browser console and network requests. Expected: no console error, missing image, or unexpected remote asset request.

- [ ] **Step 3: Verify mobile crop at 390×844 and 320px width**

Confirm at both widths:

```text
- No horizontal page overflow.
- Demo uses a 4:3 crop rather than shrinking all 16:10 details.
- Real SwitchTab overlay and target window remain legible.
- Scenario label and HUD do not overlap the active overlay.
- Existing install and how-it-works anchors remain reachable.
```

- [ ] **Step 4: Verify keyboard and reduced-motion behavior**

Tab through all links and confirm visible focus. Emulate `prefers-reduced-motion: reduce` and wait at least 20 seconds.

Expected: `everyday-01-notes-working.webp` remains the only visible frame; scene labels/HUD do not animate; layout stays stable; all product meaning remains available in `#demo-caption`.

- [ ] **Step 5: Run fresh automated verification**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk test swift test
rtk git diff --check
rtk git status --short
```

Expected: landing contract passes; Swift tests report zero failures; diff check exits 0; status contains only intentional landing QA changes, if any.

- [ ] **Step 6: Commit scoped QA fixes only when needed**

If browser QA found a concrete defect, make the smallest HTML/CSS/test adjustment, repeat the affected browser check and all Step 5 commands, then run:

```bash
rtk git add docs/index.html docs/landing.css docs/demo scripts/tests/landing-contract-test.sh
rtk git commit -m "fix: polish landing demo reel"
```

If no defect exists, do not create an empty commit.

## Self-review checklist

- [ ] The plan implements all three approved scenarios and exactly 18 real screenshots.
- [ ] The app-to-window handoff happens inside one held-modifier session and matches current SwitchTab behavior.
- [ ] The hero is centered with one large demo beneath it; supporting landing sections remain out of scope.
- [ ] The reel loops every 18 seconds and full-desktop transitions cut cleanly without dimming.
- [ ] HTML/CSS does not redraw SwitchTab UI, app icons, application windows, or previews.
- [ ] No JavaScript, video, canvas, remote image, analytics, or new runtime dependency is introduced.
- [ ] Poster and full asset limits are enforced at 250 KiB and 4 MiB.
- [ ] Mobile crops around the central workflow rather than shrinking details below legibility.
- [ ] Reduced motion shows one stable representative poster.
- [ ] Asset, HTML, CSS, security, browser, and Swift regression checks have explicit pass criteria.
