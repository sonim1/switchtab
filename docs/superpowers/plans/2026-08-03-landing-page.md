# SwitchTab Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build a responsive, static dark-glass landing page that communicates SwitchTab's Cmd-Tab and Cmd-Backtick value within five seconds.

**Architecture:** Create a semantic `docs/index.html` page and a focused `docs/landing.css` stylesheet. The page uses the existing 256px app icon, CSS mockup geometry, anchor navigation, and no JavaScript or external runtime assets. Update the README documentation index to link the landing page while keeping the existing runbooks authoritative.

**Tech Stack:** HTML5, CSS3, inline SVG/CSS mockup, existing PNG asset, static GitHub Pages-compatible hosting.

---

## File Structure

- Create `docs/index.html`: semantic landing structure, approved copy, accessible mockup labels, local links, and source-build CTA.
- Create `docs/landing.css`: design tokens, dark-glass surfaces, hero/grid layout, mockup styling, focus states, responsive breakpoints, and reduced-motion rules.
- Modify `README.md:74-84`: add the landing page to the documentation index without changing product or release claims.

### Task 1: Create the semantic landing page shell

**Files:**
- Create: `docs/index.html`
- Test: static path and content checks in Task 4

- [ ] **Step 1: Add the document shell and metadata**

Create a UTF-8 HTML5 document with `<meta name="viewport" content="width=device-width, initial-scale=1">`, a descriptive title, a concise meta description, and a stylesheet link to `landing.css`. Do not add script tags, remote fonts, trackers, or external image URLs.

- [ ] **Step 2: Add the header and first-viewport content**

Use semantic `<header>`, `<main>`, and `<footer>`. The header contains the local app icon, `SwitchTab`, a `Build from source` link to `../README.md#quick-start`, and a GitHub link. The hero heading must be `Your apps, one keystroke away.`; supporting text must accurately mention configurable Cmd-Tab application switching and Cmd-Backtick current-app window switching. Add `See how it works` linking to `#how-it-works`.

- [ ] **Step 3: Add the static switcher mockup**

Build an accessible `<figure>` with `aria-labelledby` and a decorative panel representing the compact application switcher. Include four local app-icon tiles, one selected tile with a blue outline limited to the icon container, a centered caption below it, and one `2 windows` badge only on the selected tile. Mark purely decorative glow elements `aria-hidden="true"`; give the figure a text caption explaining `Hold Command, cycle with Tab, release to switch.`

- [ ] **Step 4: Add trust row and supporting sections**

Add a three-item trust row (`macOS 14+`, `Native Swift`, `Free forever`), then `#how-it-works` with three cards for application switching, current-app windows, and privacy/permissions. Add a three-step `Hold`, `Cycle`, `Release` strip and a source-build section with the exact command `swift build && swift test` plus a development-guide link.

- [ ] **Step 5: Add footer navigation**

Link to `../README.md`, `development.md`, `direct-distribution.md`, `release-workflow.md`, and `PROJECT_HISTORY.md`. Keep the footer low emphasis and do not imply a binary download is currently available.

- [ ] **Step 6: Commit the HTML structure**

Run `git diff --check`, then commit only `docs/index.html` with message `feat: add SwitchTab landing page structure`.

### Task 2: Implement the dark-glass visual system and responsive layout

**Files:**
- Create: `docs/landing.css`
- Modify: `docs/index.html` only if class/label adjustments are required

- [ ] **Step 1: Define design tokens and base styles**

Define CSS custom properties for near-black canvas, glass surface, border, primary text, muted text, blue accent, shadow, radius, and max content width. Set system UI font stack, dark canvas, readable line-height, `box-sizing: border-box`, and `scroll-behavior: smooth`.

- [ ] **Step 2: Style the header and hero grid**

Use a centered max-width wrapper, a two-column hero at desktop widths, balanced vertical spacing, and a restrained radial glow behind the mockup. The main heading should use `clamp()` and keep the first viewport compact enough for common laptop heights. Primary and secondary links must have visible hover and keyboard focus states.

- [ ] **Step 3: Style the switcher mockup**

Use translucent layers and `backdrop-filter` only as progressive enhancement. The app icon tiles must use equal dimensions, 4px inter-tile rhythm, rounded icon containers, and a selection outline that stops before the caption. Use `object-fit: cover` for the local icon asset, and keep the count badge visually secondary.

- [ ] **Step 4: Style supporting cards and workflow strip**

Create reusable glass card styles with subtle borders, icon/eyebrow treatments, and enough spacing for readable mobile stacking. Make the workflow strip visually encode hold → cycle → release without relying on motion.

- [ ] **Step 5: Add responsive and accessibility rules**

At a narrow breakpoint, stack hero copy before the mockup, reduce card padding, preserve 320px readability, and prevent horizontal overflow. Add `:focus-visible` outlines, `@media (prefers-reduced-motion: reduce)` to disable transitions/scroll animation, and a fallback background for browsers without blur support.

- [ ] **Step 6: Commit the visual system**

Run `git diff --check`, then commit `docs/landing.css` and any necessary HTML class changes with message `feat: style SwitchTab landing page`.

### Task 3: Connect repository navigation and verify content claims

**Files:**
- Modify: `README.md:74-84`
- Modify: `docs/index.html` only for link corrections

- [ ] **Step 1: Add the landing page to README documentation links**

Add `Landing page` linking to `docs/index.html` near the top of the existing documentation list. Keep the current AI context, development, distribution, update-hosting, release, and maintenance links intact.

- [ ] **Step 2: Validate local links and asset paths**

Check that every relative Markdown/HTML path used by the new page resolves from its file location, especially `../SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png`, `../README.md#quick-start`, and all `docs/*.md` links.

- [ ] **Step 3: Check privacy and dependency boundaries**

Search the new page and stylesheet for `<script`, `http://`, `https://`, tracking, analytics, ad, and subscription strings. The only allowed external URL is the visible GitHub repository link; no external runtime dependency may remain.

- [ ] **Step 4: Commit repository navigation**

Run `git diff --check`, then commit with message `docs: link landing page from README`.

### Task 4: Run static and browser QA

**Files:**
- Verify: `docs/index.html`, `docs/landing.css`, `README.md`

- [ ] **Step 1: Run static checks**

Run:

```bash
test -s docs/index.html
test -s docs/landing.css
test -f SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 2: Validate HTML structure and forbidden dependencies**

Run a local parser/check that confirms one `<h1>`, `main`, `footer`, `#how-it-works`, no script elements, no remote asset URLs, and no placeholder text. Expected: `landing contract passed`.

- [ ] **Step 3: Serve and inspect the page in a browser**

Serve the repository with `python3 -m http.server` from the repository root and inspect `http://127.0.0.1:<port>/docs/` at desktop (1440×900) and mobile (390×844). Confirm the hero communicates the product immediately, the mockup fits without horizontal scrolling, all anchors work, and the app icon loads.

- [ ] **Step 4: Perform keyboard and reduced-motion checks**

Tab through every link at desktop and mobile widths; confirm visible focus. Enable reduced motion and confirm no transition/scroll animation is required to understand the page. Confirm text remains readable at 320px.

- [ ] **Step 5: Run regression tests**

Run `swift test`. Expected: 19 tests, 0 failures. No Swift source, workflow, or release-script files should appear in the diff.

- [ ] **Step 6: Commit any scoped QA fixes**

If QA finds a concrete landing defect, fix only the affected HTML/CSS, rerun the relevant checks, and commit `fix: polish SwitchTab landing page QA`. If no fixes are needed, do not create an empty commit.

## Self-review checklist

- [ ] First viewport leads with the five-second product value and a visible source-build CTA.
- [ ] Mockup matches the shipped compact switcher: selected caption below, outline around icon only, count shown only for two or more windows.
- [ ] Copy does not promise a downloadable binary, always-on Cmd-Tab replacement, or unsupported behavior.
- [ ] No external runtime assets, analytics, or JavaScript were added.
- [ ] Desktop and 320px/mobile layouts have no horizontal overflow.
- [ ] `swift test` remains green and the diff is limited to landing/documentation files.
