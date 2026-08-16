# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0.0] - 2026-08-15

### Added

- See SwitchTab's app-to-window flow directly on the landing page through a layered macOS desktop demo built from real product captures.
- Pause or resume the demo, with keyboard focus, reduced-motion support, and clear shortcut feedback.

### Changed

- Present the demo as a macOS desktop with synchronized Notes and Preview menu-bar context instead of an outer application window.
- Scale the application and window switcher panels responsively while preserving their original proportions.
- Use privacy-safe staged Finder, Notes, Preview, Safari, and SwitchTab imagery throughout the public demo.
- Remove the developer-documentation links from the public footer and send the build-from-source link to the GitHub README instead of raw Markdown.

### Fixed

- Match visible keyboard prompts, animation transitions, and menu-bar state to the exact app or window being selected.
- Keep the demo readable at 320px without stretching or oversized overlays.
- Remove personal filesystem identifiers and ambiguous shortcut artwork from deployed landing assets.
