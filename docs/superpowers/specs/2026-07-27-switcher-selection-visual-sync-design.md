# Switcher Selection Visual Sync Design

## Problem

When the switcher is open, repeated keyboard navigation changes the actual target window, but the highlighted item can remain visually stale. The command and selection logic already works; the SwiftUI presentation is not reliably observing each selection update.

## Success Criteria

- Every accepted navigation command immediately updates the visible selected item.
- The selected item remains visibly distinct and scrolls into view when needed.
- Confirm, cancel, keyboard shortcuts, and window activation behavior remain unchanged.
- A regression test fails when presentation state no longer publishes selection changes.

## Design

Add a small main-actor observable presentation model owned by `SwitcherOverlayController`. The model publishes the overlay state consumed by SwiftUI. The controller updates this stable model after presentation and navigation commands instead of relying on replacing the hosting controller's root view with another value snapshot.

`SwitcherOverlayRootView` observes the model, while `SwitcherOverlayState` remains responsible for session and selection rules. This keeps command behavior separate from rendering and limits the change to the overlay presentation boundary.

Strengthen the selected-item treatment with the existing accent color using a fill and border. This is a visibility adjustment, not a broader panel redesign.

## Alternatives Considered

- Force a new SwiftUI identity for every selected index: small, but rebuilds the view tree and can disrupt scrolling.
- Keep replacing the root view and force layout/display: patches the symptom and remains dependent on hosting-controller behavior.
- Use a stable observable presentation model: explicit update flow, directly testable, and preserves SwiftUI identity. Chosen.

## Testing

Write the regression test first. It will subscribe to the presentation model, apply a state with a different selection, and verify that observers receive the new selected index. Existing state tests continue to verify wraparound and command semantics. Run the complete Swift test suite and an unsigned macOS build.

## Release

Ship as the next patch release, expected `v1.0.6`, through the existing pull-request merge, automatic versioning, notarized release, Sparkle appcast, and Homebrew pipeline.
