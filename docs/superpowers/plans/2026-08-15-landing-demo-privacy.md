# Landing Demo Privacy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every personal or visually ambiguous landing-demo capture with staged, privacy-safe real macOS imagery.

**Architecture:** Keep the existing six-layer HTML/CSS animation unchanged. Replace four raster layers with staged captures, remove every unused legacy demo screenshot from the served directory, and lock the safe asset inventory in the landing contract. The app panel remains a real SwitchTab capture but is framed to contain only four generic system applications.

**Tech Stack:** macOS Finder and Preview, SwitchTab runtime, CGWindow/region screenshots, WebP, HTML, Bash contract tests, Orca browser

---

### Task 1: Lock the privacy-safe asset contract

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Write a failing asset-inventory test**

Replace the four unsafe asset names with these staged names in `demo_assets`:

```bash
layer-finder-staged.webp
layer-preview-artwork.webp
layer-app-switcher-curated.webp
layer-window-switcher-curated.webp
```

Require the served demo directory to contain only the six live WebP assets and reject the unsafe names and shortcut artwork:

```bash
test "$(find "$demo_dir" -maxdepth 1 -type f -name '*.webp' | wc -l | tr -d ' ')" = 6
if grep -qE 'layer-finder\.webp|layer-preview-secondary\.webp|layer-app-switcher\.webp|layer-window-switcher\.webp|shortcut-map' "$page"; then
  echo 'unsafe or ambiguous landing demo asset remains referenced' >&2
  exit 1
fi
```

- [ ] **Step 2: Run the contract and verify RED**

Run: `rtk test bash scripts/tests/landing-contract-test.sh`

Expected: FAIL because the page still references the old four asset names and the demo directory contains eighteen WebP files.

### Task 2: Produce four staged real-UI captures

**Files:**
- Create ignored source: `.build/landing-demo-safe/flow-context.png`
- Create ignored source: `.build/landing-demo-safe/layer-finder-staged.png`
- Create ignored source: `.build/landing-demo-safe/layer-preview-artwork.png`
- Create ignored source: `.build/landing-demo-safe/layer-app-switcher-curated.png`
- Create ignored source: `.build/landing-demo-safe/layer-window-switcher-curated.png`
- Create: `docs/demo/layer-finder-staged.webp`
- Create: `docs/demo/layer-preview-artwork.webp`
- Create: `docs/demo/layer-app-switcher-curated.webp`
- Create: `docs/demo/layer-window-switcher-curated.webp`

- [ ] **Step 1: Generate neutral Preview artwork**

Use the built-in image generation tool to create a landscape abstract product image with layered blue/violet window cards, no people, no keyboard keys, no application UI, no text, no logo, and no watermark. Save the selected PNG as `.build/landing-demo-safe/flow-context.png` and inspect it before capture.

- [ ] **Step 2: Capture a staged Finder window**

Create a dedicated `SwitchTab Demo` folder containing only generic sample files such as `Product Brief.pdf`, `Release Notes.txt`, and `Brand Assets`. Open that folder in Finder, hide the sidebar and path bar, and capture only the Finder CGWindow with alpha and shadow. Confirm the capture contains no account name, home-folder name, tag, project path, or real filename.

- [ ] **Step 3: Capture the second Preview window**

Open `flow-context.png` in Preview and capture only its CGWindow. Keep the existing `switch-faster.png` Preview capture as the first Preview window.

- [ ] **Step 4: Capture curated SwitchTab panels**

Open the two safe Preview windows and invoke SwitchTab. Region-capture the real application panel so only Notes, Preview, Finder, and Safari are present in the saved image. Then invoke the two-window Preview switcher and capture only the panel containing the two safe Preview thumbnails. Always release Command after capture.

- [ ] **Step 5: Convert and inspect WebP outputs**

Convert the four PNG sources at quality 82. Verify alpha/shadows, readable staged content, and intrinsic aspect ratios with `sips`; inspect all four outputs visually before referencing them.

### Task 3: Swap assets and remove unused screenshots

**Files:**
- Modify: `docs/index.html`
- Delete: `docs/demo/layer-finder.webp`
- Delete: `docs/demo/layer-preview-secondary.webp`
- Delete: `docs/demo/layer-app-switcher.webp`
- Delete: `docs/demo/layer-window-switcher.webp`
- Delete: unused `docs/demo/everyday-*.webp`
- Delete: unused `docs/demo/developer-*.webp`

- [ ] **Step 1: Update the four image references**

Point the existing Finder, secondary Preview, app-switcher, and window-switcher `<img>` elements at the four staged names. Set each `width` and `height` attribute to the matching intrinsic WebP dimensions.

- [ ] **Step 2: Remove old tracked captures**

Remove the four superseded layer files and all twelve unreferenced persona screenshots so `docs/demo/` contains exactly the six public assets used by the page.

- [ ] **Step 3: Verify GREEN**

Run: `rtk test bash scripts/tests/landing-contract-test.sh`

Expected: `landing contract passed`.

### Task 4: Verify privacy and responsive rendering

**Files:**
- Verify only

- [ ] **Step 1: Run automated checks**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk git diff --check
```

Expected: the contract passes and the diff check is silent.

- [ ] **Step 2: Inspect the live animation**

Reload the local landing page with a cache-busting query, inspect the base stack, app panel, window panel, and final focus at desktop and mobile widths, and confirm every layer preserves its intrinsic aspect ratio.

- [ ] **Step 3: Perform the privacy review**

Inspect each of the six served images individually. Confirm there is no personal name, sidebar, tag, real project filename, browser content, or uncurated application list, and confirm no background artwork contains keyboard shortcuts.

- [ ] **Step 4: Remove local raw captures from active build storage**

After confirming the staged WebPs, move the old `.build/landing-demo-captures` directory to a uniquely named path in `~/.Trash/` so the untracked personal screenshots are no longer in the project worktree and remain recoverable.

- [ ] **Step 5: Commit the safe current tree**

Run:

```bash
rtk git add docs/index.html docs/demo scripts/tests/landing-contract-test.sh
rtk git commit -m "fix: anonymize landing demo captures"
```

### Task 5: Handle the local Git history explicitly

**Files:**
- No file changes

- [ ] **Step 1: Report history status**

Confirm again that no remote branch contains the unsafe capture commits. Report that the old Finder blob remains reachable in local commits even though the current tree is safe.

- [ ] **Step 2: Request approval before rewriting history**

Do not rewrite or force-push automatically. If approved, squash the local feature branch onto its main-branch base so the unsafe binary is no longer reachable from the feature branch, then verify with `git log --all -- docs/demo/layer-finder.webp` and `git fsck --unreachable` before discussing garbage collection.
