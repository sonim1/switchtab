# Landing Demo Pacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slow the landing demo from an 18-second loop to a 27-second loop so every application and window switching step remains visible for 1.5 seconds.

**Architecture:** Keep the existing CSS-only three-scene, six-frame animation. Change only its duration and negative delays, then lock the timing in the existing landing contract and verify the real browser animation sequence.

**Tech Stack:** HTML, CSS animations, Bash contract test, agent-browser

---

### Task 1: Slow the CSS demo timeline

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh:80-100`
- Modify: `docs/landing.css:1-200`

- [ ] **Step 1: Write the failing contract assertions**

Replace the existing cycle assertion and add assertions for the longer frame cycle and scene/frame delays:

```bash
grep -q -- '--demo-cycle: 27s' "$style"
grep -q 'animation: demo-frame-cycle 9s steps(1, end) infinite' "$style"
grep -q '.demo-scene--developer { animation-delay: -18s; }' "$style"
grep -q '.demo-scene--creative { animation-delay: -9s; }' "$style"
grep -q '.demo-frame:nth-of-type(2) { animation-delay: -7.5s; }' "$style"
grep -q '.demo-frame:nth-of-type(6) { animation-delay: -1.5s; }' "$style"
grep -q '.demo-hud--apps { animation: demo-hud-apps 9s linear infinite; }' "$style"
grep -q '.demo-hud--windows { animation: demo-hud-windows 9s linear infinite; }' "$style"
grep -q '.demo-hud--release { animation: demo-hud-release 9s linear infinite; }' "$style"
```

- [ ] **Step 2: Run the contract to verify it fails**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL because `docs/landing.css` still declares the 18-second loop and 6-second frame cycle.

- [ ] **Step 3: Implement the minimal timing change**

Update the CSS timing values while preserving hard cuts and existing percentage keyframes:

```css
:root { --demo-cycle: 27s; }
.demo-scene--everyday { animation-delay: 0s; }
.demo-scene--developer { animation-delay: -18s; }
.demo-scene--creative { animation-delay: -9s; }
.demo-frame { animation: demo-frame-cycle 9s steps(1, end) infinite; }
.demo-frame:nth-of-type(1) { animation-delay: 0s; }
.demo-frame:nth-of-type(2) { animation-delay: -7.5s; }
.demo-frame:nth-of-type(3) { animation-delay: -6s; }
.demo-frame:nth-of-type(4) { animation-delay: -4.5s; }
.demo-frame:nth-of-type(5) { animation-delay: -3s; }
.demo-frame:nth-of-type(6) { animation-delay: -1.5s; }
.demo-hud--apps { animation: demo-hud-apps 9s linear infinite; }
.demo-hud--windows { animation: demo-hud-windows 9s linear infinite; }
.demo-hud--release { animation: demo-hud-release 9s linear infinite; }
```

- [ ] **Step 4: Run automated verification**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk test swift test
rtk git diff --check
```

Expected: landing contract passes, Swift tests pass, and the diff check produces no output.

- [ ] **Step 5: Verify the browser timeline**

Open `http://127.0.0.1:4173/` in a named agent-browser session, pause the animations through the Web Animations API, and sample computed opacity every 1.5 seconds. Confirm each scene exposes frames 1 through 6 in order and that `creative-05-window-overlay.webp` is visible before `creative-06-design-focused.webp`. Confirm the browser console and page error lists are empty, then close the session.

- [ ] **Step 6: Show the updated demo in Orca**

Reload the existing Orca page with a cache-busting query string, scroll `.demo-reel` into the center of the viewport, and switch to that tab. Leave the animation running.

- [ ] **Step 7: Commit**

```bash
rtk git add docs/landing.css scripts/tests/landing-contract-test.sh
rtk git commit -m "fix: slow landing demo pacing"
```
