# Landing Demo Window Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three full-screen persona demos with one spatially stable, real macOS window-stack demo whose keyboard effects and screen changes share exact boundaries.

**Architecture:** Capture Finder, Notes, two Preview windows, and the two SwitchTab panels independently so no user desktop content is exposed. Layer those real transparent window assets on one neutral desktop surface; animate the app panel, window panel, and selected Preview layer at 1.5/4.5/7.5-second hard boundaries alongside the keyboard HUD.

**Tech Stack:** macOS Accessibility/System Events, SwitchTab runtime, WebP, HTML, CSS animations, Bash contract test, agent-browser, Orca browser

---

### Task 1: Lock the single-scene contract

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh:10-110`

- [ ] **Step 1: Write the failing structure and timing assertions**

Require one scene, six unique real window assets, no persona labels, a 9-second loop, hard-cut HUD timing, and key micro-interactions:

```bash
test "$(grep -o 'class="demo-scene"' "$page" | wc -l | tr -d ' ')" = 1
test "$(grep -oE 'src="demo/layer-[^"]+\.webp"' "$page" | sort -u | wc -l | tr -d ' ')" = 6
test "$(grep -o 'class="demo-layer' "$page" | wc -l | tr -d ' ')" = 7
if grep -qE 'Everyday|Developer|Creative|demo-scene__label|demo-scene--' "$page"; then
  echo 'persona scenes remain on landing page' >&2
  exit 1
fi
grep -q -- '--demo-cycle: 9s' "$style"
grep -q '.demo-scene { position: absolute; inset: 0; }' "$style"
grep -q '.demo-layer--app-switcher { animation: demo-app-overlay 9s steps(1, end) infinite; }' "$style"
grep -q '.demo-layer--window-switcher { animation: demo-window-overlay 9s steps(1, end) infinite; }' "$style"
grep -q '.demo-layer--preview-final { animation: demo-preview-final 9s steps(1, end) infinite; }' "$style"
grep -q '.demo-hud--apps { animation: demo-hud-apps 9s steps(1, end) infinite; }' "$style"
grep -q '.demo-hud--windows { animation: demo-hud-windows 9s steps(1, end) infinite; }' "$style"
grep -q '.demo-hud--release { animation: demo-hud-release 9s steps(1, end) infinite; }' "$style"
grep -q '@keyframes demo-key-tab' "$style"
grep -q '@keyframes demo-key-window' "$style"
grep -q '@keyframes demo-key-release' "$style"
```

Replace the six Creative asset names in `demo_assets` with:

```bash
layer-finder.webp
layer-notes.webp
layer-preview-primary.webp
layer-preview-secondary.webp
layer-app-switcher.webp
layer-window-switcher.webp
```

- [ ] **Step 2: Run the contract to verify it fails**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL because three persona scenes and full-screen frame assets still exist.

---

### Task 2: Capture six real transparent window layers

**Files:**
- Rename and replace: `docs/demo/creative-01-browser-working.webp` through `docs/demo/creative-06-design-focused.webp`
- Create ignored sources: `.build/landing-demo-captures/layer-finder.png`, `layer-notes.png`, `layer-preview-primary.png`, `layer-preview-secondary.png`, `layer-app-switcher.png`, `layer-window-switcher.png`

- [ ] **Step 1: Rename the six tracked Creative assets**

Use `git mv` so the demo directory keeps 18 total WebP files:

```bash
rtk git mv docs/demo/creative-01-browser-working.webp docs/demo/layer-finder.webp
rtk git mv docs/demo/creative-02-app-shortcut.webp docs/demo/layer-notes.webp
rtk git mv docs/demo/creative-03-app-overlay.webp docs/demo/layer-preview-primary.webp
rtk git mv docs/demo/creative-04-preview-selected.webp docs/demo/layer-preview-secondary.webp
rtk git mv docs/demo/creative-05-window-overlay.webp docs/demo/layer-app-switcher.webp
rtk git mv docs/demo/creative-06-design-focused.webp docs/demo/layer-window-switcher.webp
```

- [ ] **Step 2: Capture each real application window independently**

Resize the safe demo windows, then capture their CGWindow ids with `screencapture -l` so unrelated desktop pixels are excluded and alpha/shadows are preserved:

```text
Finder “docs” → layer-finder.png
Notes “Launch checklist” → layer-notes.png
Preview “switch-faster.png” → layer-preview-primary.png
Preview “shortcut-map.png” → layer-preview-secondary.png
```

- [ ] **Step 3: Capture the two real SwitchTab panels independently**

Prime Preview, restore Notes, hold Command, and press Tab. Find the visible SwitchTab-owned CGWindow id and capture only that panel as `layer-app-switcher.png`. Keep Command held, switch/cycle to the second Preview window, find the replacement SwitchTab panel id, and capture only it as `layer-window-switcher.png`. Always send a final Command key-up event.

- [ ] **Step 4: Convert sources to tracked WebP files**

Preserve each layer's natural aspect ratio and alpha:

```bash
rtk proxy cwebp -quiet -q 82 .build/landing-demo-captures/layer-finder.png -o docs/demo/layer-finder.webp
rtk proxy cwebp -quiet -q 82 .build/landing-demo-captures/layer-notes.png -o docs/demo/layer-notes.webp
rtk proxy cwebp -quiet -q 82 .build/landing-demo-captures/layer-preview-primary.png -o docs/demo/layer-preview-primary.webp
rtk proxy cwebp -quiet -q 82 .build/landing-demo-captures/layer-preview-secondary.png -o docs/demo/layer-preview-secondary.webp
rtk proxy cwebp -quiet -q 82 .build/landing-demo-captures/layer-app-switcher.png -o docs/demo/layer-app-switcher.webp
rtk proxy cwebp -quiet -q 82 .build/landing-demo-captures/layer-window-switcher.png -o docs/demo/layer-window-switcher.webp
```

Verify each WebP preserves its source aspect ratio and alpha, remains sharp at its rendered size, and keeps the demo directory under the existing 4 MiB contract budget.

---

### Task 3: Render one scene with synchronized key feedback

**Files:**
- Modify: `docs/index.html:48-90`
- Modify: `docs/landing.css:136-200,250-300`

- [ ] **Step 1: Replace three scenes with one layered desktop**

Use one scene without a persona label:

```html
<div class="demo-scene">
  <div class="demo-desktop demo-frame--poster">
    <img class="demo-layer demo-layer--finder" src="demo/layer-finder.webp" alt="" decoding="async" fetchpriority="high">
    <img class="demo-layer demo-layer--preview-primary" src="demo/layer-preview-primary.webp" alt="" loading="lazy" decoding="async">
    <img class="demo-layer demo-layer--preview-secondary" src="demo/layer-preview-secondary.webp" alt="" loading="lazy" decoding="async">
    <img class="demo-layer demo-layer--notes" src="demo/layer-notes.webp" alt="" loading="lazy" decoding="async">
    <img class="demo-layer demo-layer--preview-final" src="demo/layer-preview-primary.webp" alt="" loading="lazy" decoding="async">
    <img class="demo-layer demo-layer--app-switcher" src="demo/layer-app-switcher.webp" alt="" loading="lazy" decoding="async">
    <img class="demo-layer demo-layer--window-switcher" src="demo/layer-window-switcher.webp" alt="" loading="lazy" decoding="async">
  </div>
  <span class="demo-hud demo-hud--apps"><small>Hold</small><kbd>⌘</kbd><kbd class="demo-key demo-key--tab">Tab</kbd></span>
  <span class="demo-hud demo-hud--windows"><small>keep holding</small><kbd>⌘</kbd><kbd class="demo-key demo-key--window">′</kbd></span>
  <span class="demo-hud demo-hud--release"><small>release</small><kbd class="demo-key demo-key--release">⌘</kbd></span>
</div>
```

- [ ] **Step 2: Position the real layers and align all boundaries**

Set `--demo-cycle: 9s`, place the real windows in a stable stack, and use the same hard boundaries for overlays, final focus, and the HUD:

```css
.demo-scene { position: absolute; inset: 0; }
.demo-desktop { position: absolute; inset: 0; overflow: hidden; background: radial-gradient(circle at 72% 20%, #294c7d 0, #17283f 40%, #0d1521 100%); }
.demo-layer { position: absolute; display: block; height: auto; max-width: none; filter: drop-shadow(0 18px 26px rgba(0, 0, 0, 0.28)); }
.demo-layer--finder { top: 5%; left: 3%; z-index: 1; width: 94%; }
.demo-layer--preview-primary { top: 8%; left: 27%; z-index: 2; width: 62%; }
.demo-layer--preview-secondary { top: 18%; left: 40%; z-index: 3; width: 56%; }
.demo-layer--notes { top: 25%; left: 14%; z-index: 4; width: 56%; }
.demo-layer--preview-final { top: 8%; left: 27%; z-index: 5; width: 62%; opacity: 0; animation: demo-preview-final 9s steps(1, end) infinite; }
.demo-layer--app-switcher { top: 50%; left: 50%; z-index: 6; width: 88%; opacity: 0; transform: translate(-50%, -50%); animation: demo-app-overlay 9s steps(1, end) infinite; }
.demo-layer--window-switcher { top: 50%; left: 50%; z-index: 6; width: 48%; opacity: 0; transform: translate(-50%, -50%); animation: demo-window-overlay 9s steps(1, end) infinite; }
.demo-hud--apps { animation: demo-hud-apps 9s steps(1, end) infinite; }
.demo-hud--windows { animation: demo-hud-windows 9s steps(1, end) infinite; }
.demo-hud--release { animation: demo-hud-release 9s steps(1, end) infinite; }
@keyframes demo-app-overlay { 0%, 16.666% { opacity: 0; } 16.667%, 49.999% { opacity: 1; } 50%, 100% { opacity: 0; } }
@keyframes demo-window-overlay { 0%, 49.999% { opacity: 0; } 50%, 83.332% { opacity: 1; } 83.333%, 100% { opacity: 0; } }
@keyframes demo-preview-final { 0%, 83.332% { opacity: 0; } 83.333%, 100% { opacity: 1; } }
@keyframes demo-hud-apps { 0%, 16.666% { opacity: 0; } 16.667%, 49.999% { opacity: 1; } 50%, 100% { opacity: 0; } }
@keyframes demo-hud-windows { 0%, 49.999% { opacity: 0; } 50%, 83.332% { opacity: 1; } 83.333%, 100% { opacity: 0; } }
@keyframes demo-hud-release { 0%, 83.332% { opacity: 0; } 83.333%, 99.999% { opacity: 1; } 100% { opacity: 0; } }
```

- [ ] **Step 3: Add 0.2-second key effects**

Animate only the changed key at each exact HUD boundary:

```css
.demo-key--tab { animation: demo-key-tab 9s linear infinite; }
.demo-key--window { animation: demo-key-window 9s linear infinite; }
.demo-key--release { animation: demo-key-release 9s linear infinite; }
@keyframes demo-key-tab { 0%, 16.666%, 18.889%, 100% { transform: none; } 16.667% { transform: translateY(2px) scale(0.94); } }
@keyframes demo-key-window { 0%, 49.999%, 52.222%, 100% { transform: none; } 50% { transform: translateY(2px) scale(0.94); } }
@keyframes demo-key-release { 0%, 83.333% { transform: translateY(2px) scale(0.94); } 85.555%, 100% { transform: none; } }
```

At the pressed keyframes also apply the existing blue accent to border, background, and shadow. Extend the reduced-motion rule to disable `.demo-key` animations.

On mobile, keep the internal desktop at 16:10 and center-crop it inside the existing 4:3 stage:

```css
.demo-desktop { top: 0; left: 50%; width: 120%; height: 100%; transform: translateX(-50%); }
```

- [ ] **Step 4: Run the contract to verify it passes**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: `landing contract passed`.

---

### Task 4: Verify and show the updated dev page

**Files:**
- Verify only

- [ ] **Step 1: Run automated checks**

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk test swift test
rtk git diff --check
```

Expected: both test commands pass and the diff check produces no output.

- [ ] **Step 2: Sample exact browser boundaries**

Pause animations through the Web Animations API and sample at 1499/1501, 4499/4501, and 7499/7501 milliseconds. Confirm the visible SwitchTab/final-Preview layer, HUD, and pressed key change on the same side of each boundary. Confirm the 0.2-second key effect has returned to rest by 1701, 4701, and 7701 milliseconds.

- [ ] **Step 3: Check desktop, mobile, and reduced motion**

Visually inspect the window stack and z-order change at desktop width, confirm no horizontal overflow at 390px, confirm browser console/errors are empty, and confirm reduced motion shows only the poster with zero running animations.

- [ ] **Step 4: Commit**

```bash
rtk git add docs/index.html docs/landing.css docs/demo scripts/tests/landing-contract-test.sh
rtk git commit -m "feat: show one layered window-switching demo"
```

- [ ] **Step 5: Open dev in Orca**

Reload the existing Orca browser page with a cache-busting query string, center `.demo-reel`, switch to that tab, and leave the 9-second loop running.
