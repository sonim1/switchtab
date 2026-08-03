# SwitchTab Landing Page Design

**Date:** 2026-08-03  
**Status:** Approved direction; implementation plan pending  
**Primary goal:** Make a new visitor understand SwitchTab's Cmd-Tab/Cmd-Backtick value within five seconds.

## Scope

Create a single responsive static landing page at `docs/index.html`. The page is a presentation layer only: it does not change the macOS app, release automation, update feed, permissions, or public product claims.

The page will use the existing SwitchTab app icon and inline CSS/SVG/CSS shapes for the switcher illustration. It will not load external images, analytics, advertising, tracking scripts, or runtime dependencies.

## Chosen direction

Use a macOS-native dark-glass visual system: near-black background, layered translucent panels, soft blue accent, restrained blur, rounded cards, and large familiar app icons. The first viewport is a product hero rather than a documentation index.

### First viewport

- Header: SwitchTab identity, `Build from source` CTA, and GitHub link.
- Hero copy: `Your apps, one keystroke away.`
- Supporting copy explains that SwitchTab switches applications with Cmd-Tab and windows in the current app with Cmd-Backtick.
- Primary CTA points to the repository's source-build instructions. A secondary `See how it works` anchor scrolls to the feature cards.
- Right-side visual is a CSS mockup of the compact application switcher: icon strip, selected blue outline around the icon tile only, selected app caption below, and a small window-count badge only where applicable.
- A small trust row states `macOS 14+`, `Native Swift`, and `Free forever`, matching established repository claims.

### Supporting sections

1. Three feature cards: application switching, current-app window switching, and privacy/permissions.
2. A compact “How it feels” strip showing hold → cycle → release.
3. A source-build CTA with the shortest supported command and a link to the development guide.
4. Footer links to GitHub, README, development, direct distribution, and project history where useful.

## Content rules

- Keep the first message benefit-led; do not lead with implementation terminology.
- Use only claims established by `README.md` and `docs/AI_CONTEXT.md`: macOS 14+, native Swift, configurable independent modes, Accessibility for focus/interception, Screen Recording only for window previews, and no ads/subscription/telemetry claims.
- Describe application switching as configurable and independently enabled; do not claim native Cmd-Tab is always replaced.
- Use `Build from source` until a public downloadable artifact is explicitly part of the release contract.
- Keep copy concise enough that the hero, illustration, and primary CTA fit in one desktop viewport.

## Components and boundaries

- `docs/index.html`: semantic page structure, inline illustration markup, accessible labels, and content.
- `docs/landing.css` (or a style block if the implementation remains smaller): design tokens, glass surfaces, typography, responsive layout, focus states, and reduced-motion rules.
- Existing `SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png`: product identity asset only; no new runtime asset pipeline.
- No JavaScript is required for the first version. Anchor navigation, CSS hover/focus states, and a static mockup are sufficient.

## Responsive and accessibility behavior

- Desktop uses a two-column hero with the visual on the right; narrow screens stack copy, CTA, and mockup in that order.
- Text remains selectable and readable at 320px width; no essential information is conveyed by color alone.
- Every interactive element has visible keyboard focus. Illustration tiles use meaningful labels or are hidden from the accessibility tree when decorative.
- Respect `prefers-reduced-motion`; do not require animation to understand the workflow.
- Maintain sufficient contrast for body copy, muted labels, blue selection, and glass surfaces in dark mode.

## Verification

- Static checks: referenced local files exist, no external script/image/analytics URLs, and `git diff --check` passes.
- Browser checks: desktop and mobile viewport screenshots; first-viewport comprehension; anchor navigation; keyboard tab order; focus visibility; reduced-motion rendering.
- Content checks: CTA target works, claims match README/AI context, and no placeholder/TODO copy remains.
- Repository checks: existing `swift test` remains green; no app source, workflow, or release script changes are introduced.

## Non-goals and risks

- No real-time app-switcher interaction, download hosting, pricing system, testimonials, blog, or analytics.
- A CSS mockup can be mistaken for a live demo; label it as a visual representation and keep the interaction sequence explicit in nearby copy.
- The app icon asset may be large; use an appropriate rendered size and avoid duplicating it in a way that harms page load.

## Open implementation choice

Prefer a separate `docs/landing.css` if the stylesheet exceeds a small inline block; otherwise keep one self-contained `docs/index.html` so GitHub Pages preview and local opening require no build step.
