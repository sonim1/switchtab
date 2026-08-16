# SwitchTab Landing Demo Reel Design

**Date:** 2026-08-13<br>
**Status:** Approved direction; implementation plan pending<br>
**Primary goal:** Show SwitchTab's app-to-window handoff with real product imagery so a visitor understands the product without reading the feature list.

## Scope

Replace the current CSS-drawn switcher in the landing-page hero with one wide, continuously looping demo reel. The reel uses screenshots captured from real macOS applications and the real SwitchTab overlay. CSS controls only frame timing, opacity, and small presentation transitions.

This design supersedes the first-viewport illustration and two-column hero decisions in `2026-08-03-landing-page-design.md`. The existing install section, how-it-works section, feature grid, footer, product claims, deployment pipeline, and native macOS app remain unchanged unless spacing must move to accommodate the new hero.

## Chosen experience

### Hero composition

- Center the existing benefit-led headline, supporting copy, and install actions.
- Place a large, wide demo immediately below the hero copy and actions.
- Present the demo inside one restrained macOS desktop frame that belongs to the landing page's existing dark visual system.
- Remove the current CSS-drawn application icons, switcher tiles, and fake app-window chrome.
- Keep the first frame useful as a static product image before animation starts.

The large single frame keeps attention on one workflow at a time. It avoids the density of three simultaneous demos and gives the app-to-window handoff enough room to remain legible.

### Demo story

The reel contains three six-second scenarios, for an 18-second loop:

1. **Everyday:** Notes → Safari → a specific Safari GitHub window.
2. **Developer:** Ghostty → Xcode → a specific Xcode code window.
3. **Creative:** Brave Browser → Preview → a specific design document window.

Each scenario demonstrates the same product truth with different work:

1. Start in an ordinary working window.
2. Show the Command-Tab keyboard HUD.
3. Show the real SwitchTab application overlay.
4. Advance selection to the destination application.
5. While the opening modifier remains held, hand off to the selected application's real window list and select the desired window.
6. Dismiss the overlay and show the exact target window in front.

The scenarios use neutral sample documents with no personal data, account names, notifications, private repositories, or unrelated menu-bar items.

## Image and animation model

### Real imagery boundary

Use 18 core screenshots: six frames for each of the three scenarios. Capture the macOS applications, their content, application icons, window thumbnails, selection state, and SwitchTab overlay from the real app. Do not redraw those elements in HTML, CSS, SVG, or generated artwork.

The following presentation elements may be web-native:

- the outer desktop/frame treatment;
- a compact keyboard HUD that explains the currently held or pressed keys;
- scenario labels such as `Everyday`, `Developer`, and `Creative`;
- frame visibility and transition timing.

The keyboard HUD must remain visually secondary and must not imply that it is SwitchTab UI.

### Playback

- Start automatically when the page is visible.
- Loop continuously with no playback controls or audio.
- Hold each scenario for approximately six seconds.
- Cut directly between screenshots and scenarios so the captured desktop never dims or flashes.
- Keep the keyboard HUD fade visually secondary; do not animate the full desktop opacity or slide it laterally.
- Allow normal browser background-tab animation throttling. Do not add page-visibility logic solely for the reel.

The implementation must remain CSS-only. No script, canvas renderer, video player, or runtime frame generator is introduced.

### Asset format and loading

- Keep lossless capture originals outside the served landing assets or in an ignored working directory.
- Export web assets as local WebP files at sufficient resolution for a sharp desktop presentation.
- Provide a representative poster/first frame in the initial document flow.
- Keep the poster at or below 250 KiB and the complete 18-frame WebP set at or below 4 MiB. Preserve legibility rather than native capture dimensions.
- Reuse the same source imagery on mobile with responsive sizing and cropping unless verification proves text is illegible. Do not create a second 18-image mobile set speculatively.
- Do not load images from third-party hosts.

## Responsive and accessible behavior

- Desktop shows the full wide demo below centered hero content.
- Narrow screens retain the same narrative order and crop the desktop frame around the active overlay and target window rather than shrinking all details below legibility.
- Mark rapidly changing screenshot layers as decorative and provide a concise adjacent caption that states the app-to-window workflow in text.
- Do not expose 18 duplicate image descriptions to assistive technology.
- Preserve visible keyboard focus for all existing links and buttons.
- Under `prefers-reduced-motion: reduce`, stop the reel and show one representative final poster frame. The product remains understandable without motion.
- The demo conveys selection using the real SwitchTab highlight plus spatial change; scenario meaning must not depend only on color.

## File boundaries

Expected implementation scope:

- `docs/index.html`: centered hero structure, semantic demo figure, screenshot layers, keyboard HUD, caption, and local asset references.
- `docs/landing.css`: responsive hero layout, desktop frame, timed hard cuts, HUD fades, and reduced-motion behavior.
- `docs/demo/`: optimized local screenshot assets with stable descriptive filenames.
- `scripts/tests/landing-contract-test.sh`: only the smallest contract additions needed to verify the demo asset set and continued script-free behavior.

No Swift source, app resources, release workflow, deployment workflow, or entitlement changes are part of this feature.

## Verification

### Static checks

- Every referenced screenshot exists and is non-empty.
- The page contains no script, analytics, tracker, insecure URL, video, canvas, or third-party image dependency.
- The demo has exactly three labelled scenarios in the intended order.
- Reduced-motion CSS selects a stable representative frame and disables the loop.
- `scripts/tests/landing-contract-test.sh` and `git diff --check` pass.

### Browser checks

- At desktop width, headline, actions, and the top of the demo establish one clear first-view hierarchy.
- All 18 frames appear in the intended order and the complete loop returns without a visible flash or blank frame.
- Scenario and frame changes use hard cuts without a brightness dip; the desktop does not slide sideways.
- At 320px and a common mobile width, the active overlay and target window remain readable without horizontal page overflow.
- With reduced motion enabled, only the representative poster is visible and stable.
- Keyboard navigation and existing anchors continue to work.
- Browser console and network inspection show no missing assets or unexpected remote requests.

### Content and product checks

- Captures match current SwitchTab application and window overlay behavior.
- The mode handoff shown is achievable in one held-modifier session and does not imply a commit between modes.
- No capture exposes personal or confidential information.
- Existing install, compatibility, signing, privacy, and permission claims remain accurate.

## Non-goals

- No interactive simulator or clickable fake switcher.
- No HTML/CSS reconstruction of SwitchTab, app icons, application windows, or window previews.
- No recorded marketing video, autoplay video element, audio, narration, cursor choreography, or playback controls.
- No redesign of the supporting landing sections.
- No new analytics or engagement tracking.
- No speculative asset pipeline or general animation framework.

## Risks and mitigations

- **Large transfer size:** Optimize WebP exports and enforce the 250 KiB poster and 4 MiB complete-set limits.
- **Screenshot drift after product changes:** Keep stable filenames and a documented capture sequence so assets can be replaced without restructuring the page.
- **Motion fatigue from infinite looping:** Use restrained opacity transitions, no large lateral motion, and a complete reduced-motion fallback.
- **App-brand distraction:** Use neutral sample content and keep labels focused on the switching action rather than the third-party application.
- **False product behavior:** Capture the real held-modifier app-to-window handoff and verify it against the current app before publishing.
