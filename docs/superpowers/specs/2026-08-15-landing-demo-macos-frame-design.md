# Landing Demo macOS Frame Design

## Goal

Make the landing demo read as several real application windows arranged on a macOS desktop, rather than application windows nested inside another application window. Reduce the app-switcher overlay so it supports the scene instead of covering it.

## Visual thesis

A calm, current macOS desktop surface with minimal system chrome, real SwitchTab captures, and enough visible window depth to make every transition immediately legible.

## Content plan

- Keep the existing hero copy, calls to action, layered window captures, keyboard HUD, and nine-second sequence.
- Replace the outer traffic-light window bar and centered `SwitchTab in motion` title with a compact macOS menu bar.
- Show a left-side Apple mark and active app name, plus restrained right-side status glyphs and a fixed neutral time.
- Keep the menu bar decorative and hidden from assistive technology.
- Keep all six privacy-safe WebP assets and their native aspect ratios.

## Interaction thesis

- Preserve the existing app switch, window switch, and modifier-release timing.
- Preserve the pause/play control and reduced-motion behavior.
- Shrink only the app-switcher overlay to 48% on both desktop and narrow screens. The narrow scene's 120% desktop crop still gives the overlay a slightly larger effective share without an oversized jump.
- Do not change the window-switcher overlay size or the keyboard HUD timing.

## Structure

- Rename the outer visual concept from a demo window to a macOS desktop surface while retaining the existing figure and scene DOM.
- Replace `.demo-window__bar` content with `.demo-menubar` content.
- Keep the scene immediately below the menu bar so Finder, Preview, and Notes are the only elements that read as application windows.
- Use CSS-only menu bar glyphs/text; do not add scripts, remote assets, or tracking.

## Responsive behavior

- Desktop menu bar remains one compact row.
- On screens at or below 640px, hide secondary menu items and keep only the Apple mark, active app name, compact status group, and pause/play control.
- The desktop scene remains 4:3 on mobile with no horizontal overflow.

## Acceptance criteria

- No traffic-light controls or centered `SwitchTab in motion` title remain in the outer frame.
- The outer frame visibly reads as a macOS desktop/menu bar rather than an application window.
- App-switcher capture renders at 48% width on desktop and narrow screens without stretching.
- Existing pause/play, reduced-motion, keyboard timing, privacy scans, and landing contract tests pass.
- Desktop and 320px browser screenshots show no clipping or console errors.
