# Landing Demo macOS Frame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the landing demo read as a macOS desktop containing application windows and reduce the app-switcher overlay without distorting it.

**Architecture:** Keep the existing static HTML, CSS-only animation, figure, and six WebP captures. Replace only the outer window chrome with a decorative macOS menu bar and adjust the app-switcher width at the existing desktop and mobile breakpoints.

**Tech Stack:** Static HTML, CSS, Bash contract tests, gstack Chromium browser.

---

### Task 1: Lock the desktop-frame contract

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh`
- Test: `scripts/tests/landing-contract-test.sh`

- [x] **Step 1: Write the failing contract assertions**

Add assertions that require `class="demo-menubar"`, a scene-synchronized active app label, and app-switcher width `48%` at both breakpoints. Add negative assertions rejecting `SwitchTab in motion`, `demo-window__bar`, and `window-dot`.

- [x] **Step 2: Run the contract test and confirm RED**

Run: `rtk proxy bash scripts/tests/landing-contract-test.sh`

Expected: FAIL because the current page still uses `demo-window__bar` and the app-switcher width is `64%`.

### Task 2: Replace outer window chrome with a macOS menu bar

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/landing.css`
- Test: `scripts/tests/landing-contract-test.sh`

- [x] **Step 1: Replace the outer bar markup**

Use this decorative structure inside `.demo-window`:

```html
<div class="demo-menubar" aria-hidden="true">
  <div class="demo-menubar__left">
    <span class="demo-menubar__apple"></span>
    <strong class="demo-menubar__app">SwitchTab</strong>
    <span class="demo-menubar__item">File</span>
    <span class="demo-menubar__item">Edit</span>
    <span class="demo-menubar__item">View</span>
  </div>
  <div class="demo-menubar__status">
    <span>⌁</span><span>◒</span><span>9:41</span>
  </div>
</div>
```

- [x] **Step 2: Replace obsolete bar CSS with menu-bar CSS**

Keep the menu bar 32px high, use translucent dark material, small system typography, a subtle bottom separator, and enough right padding for the existing pause control. Remove `.demo-window__bar`, `.window-dot`, and `.demo-window__title` rules.

- [x] **Step 3: Reduce the app-switcher width**

Change desktop `.demo-layer--app-switcher` from `width: 64%` to `width: 48%`. Keep the mobile override at `48%`; the cropped mobile desktop still makes it slightly larger relative to the visible stage without the former breakpoint jump. Do not set a height so the image's 1320×376 ratio remains intrinsic.

- [x] **Step 4: Run the contract test and confirm GREEN**

Run: `rtk proxy bash scripts/tests/landing-contract-test.sh`

Expected: `landing contract passed`.

### Task 3: Verify and commit the visual change

**Files:**
- Verify: `docs/index.html`
- Verify: `docs/landing.css`
- Verify: `scripts/tests/landing-contract-test.sh`

- [x] **Step 1: Run repository checks**

Run `rtk proxy swift test`, every `scripts/tests/*.sh` file with Bash, `rtk git diff --check`, and the privacy scan for `/Users/`, `kendrick`, and `file:///`.

Expected: all checks pass and the privacy scan returns no matches.

- [x] **Step 2: Verify desktop and mobile in Chromium**

At 1440px and 320px widths, confirm the menu bar is not clipped, the scene has zero horizontal overflow, the app-switcher ratio is unchanged, pause/play still works, and the console has no errors. Capture the app-switch phase at 2 seconds.

- [x] **Step 3: Commit**

```bash
rtk git add docs/index.html docs/landing.css scripts/tests/landing-contract-test.sh docs/superpowers/plans/2026-08-15-landing-demo-macos-frame.md
rtk git commit -m "fix: present landing demo as macOS desktop"
```
