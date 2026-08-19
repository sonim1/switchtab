# Cross-Mode Hotkey Routing Fix Design

## Problem

While the application switcher is open, pressing the registered window-switching
key can reach the global hotkey handler before the overlay's event tap. The global
handler starts a fresh current-application window session, so it targets the
frontmost application pinned at the left edge instead of the application currently
highlighted in the overlay. The same competing-handler risk exists in the reverse
direction.

## Behavior

- If no overlay is open, each registered shortcut keeps its existing fresh-session
  behavior.
- If the requested mode is already open, the shortcut advances the existing
  selection as it does today.
- If the opposite mode is open, the global handler routes the request through the
  existing held-session mode switch instead of starting a fresh session.
- The existing mode switch remains responsible for reading the highlighted item,
  discovering that application's windows, retaining the panel and held modifiers,
  and refusing the switch without disturbing the live session when it cannot
  complete.

## Implementation

Add a small invocation-routing policy that distinguishes fresh presentation,
same-mode advancement, and cross-mode switching from the overlay's presentation
state and requested mode. Use the policy from both public shortcut entry points.
Keep window discovery, selection memory, event-tap handling, and shortcut
registration unchanged.

This makes behavior independent of which competing hotkey callback receives the
key first. Event-tap priority changes and temporary hotkey unregistration are out
of scope because they add platform-ordering or registration-state risk.

## Verification

Add regression coverage proving that:

- a window request while the application overlay is active routes to a mode switch;
- an application request while the window overlay is active routes to a mode switch;
- a same-mode request still advances;
- a request without an overlay still starts a fresh presentation.

Run the focused regression test, the complete Swift test suite, and the unsigned
Xcode app build. Manual runtime verification should hold Command, highlight a
non-leftmost application, press Backtick, and confirm that only that application's
windows appear.
