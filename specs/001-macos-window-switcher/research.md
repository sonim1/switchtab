# Research: macOS Window Switcher

## Decision: Use SwiftUI for app shell and AppKit for macOS system behavior

Rationale: SwiftUI provides `MenuBarExtra` for a native menu bar utility, while
AppKit remains the practical layer for app activation, custom overlay windows,
and event handling. This keeps UI modern without hiding macOS-specific behavior.

Alternatives considered: AppKit-only app, which is more verbose for settings
and simple UI; cross-platform UI frameworks, rejected by constitution.

References:
- Apple SwiftUI MenuBarExtra documentation:
  https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- Apple Human Interface Guidelines, menu bar:
  https://developer.apple.com/design/Human-Interface-Guidelines/the-menu-bar

## Decision: Target macOS 14.0+

Rationale: macOS 14+ keeps the first release on current macOS APIs, supports a
native SwiftUI menu bar utility, and avoids compatibility branches while the app
is still proving core behavior.

Alternatives considered: macOS 13+, which increases compatibility but forces
more fallback decisions for activation and capture behavior. macOS 15+, rejected
because it narrows the user base without a clear feature need.

## Decision: Enumerate and focus windows through Accessibility APIs

Rationale: Current-app window switching requires observing window titles,
positions, minimized state where available, and focusing a selected window.
Apple documents `AXUIElement` for assistive applications that communicate with
and control accessible apps on macOS.

Alternatives considered: NSWindow APIs, rejected because they only cover this
app's windows. AppleScript, rejected because it is slower, harder to test, and
less direct for a repeated switching workflow.

References:
- Apple AXUIElement documentation:
  https://developer.apple.com/documentation/applicationservices/axuielement_h

## Decision: Use NSWorkspace and NSRunningApplication for app inventory and activation

Rationale: App-level switching needs the list of running applications, icons,
names, and activation. AppKit exposes `NSWorkspace.runningApplications` and
`NSRunningApplication` for these responsibilities.

Alternatives considered: Accessibility-only app enumeration, rejected because
AppKit gives cleaner application metadata and icon access.

References:
- Apple NSWorkspace runningApplications documentation:
  https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications
- Apple NSRunningApplication documentation:
  https://developer.apple.com/documentation/appkit/nsrunningapplication

## Decision: Activate selected applications with foreground activation options

Rationale: App-level switching must make the selected app frontmost, including
when the switcher overlay itself owns keyboard focus. Activation should use the
native `NSRunningApplication` activation path with foreground-capable options so
click, Enter, and shortcut-release confirmation all share one behavior.

Alternatives considered: Relying on plain activation without options, rejected
because it can fail to bring the app forward from a transient overlay. Using
Accessibility for app activation, rejected because AppKit owns app-level
activation more directly.

## Decision: Use one icon-strip app switcher with release confirmation

Rationale: The app is meant to feel immediate and keyboard-first. A single icon
strip keeps the first-release surface small, avoids presentation settings, and
matches the classic hold-shortcut-cycle-release pattern.

Alternatives considered: A separate searchable list presentation, rejected for
the current build because it adds settings and filtering surface beyond the
chosen default workflow. A separate shortcut for each presentation was also
rejected because one app-switch shortcut is simpler.

## Decision: Use ScreenCaptureKit for window previews

Rationale: The spec requires the current screen appearance for current-app
windows. ScreenCaptureKit is Apple's framework for high-performance Mac screen
and window capture. It also aligns with privacy requirements because missing
Screen Recording permission can be modeled explicitly.

Alternatives considered: Icon/title-only window rows, rejected because the spec
requires current visual appearance. Older screenshot APIs, rejected to keep the
implementation on current Apple screen-capture guidance.

References:
- Apple ScreenCaptureKit documentation:
  https://developer.apple.com/documentation/screencapturekit

## Decision: Implement global shortcut handling natively first

Rationale: The first release should avoid third-party runtime dependencies.
Shortcut registration, capture, validation, and persistence will sit behind
`HotkeyService` and `ShortcutSettingsStore`. If native handling proves too
fragile during implementation, the service boundary allows a later dependency
swap without changing the spec.

Alternatives considered: A third-party shortcut recorder package, rejected for
initial scope because it adds dependency and update surface before the native
path is proven insufficient.

## Decision: Persist settings in UserDefaults

Rationale: The feature stores only two shortcut settings and lightweight
preference/onboarding state. UserDefaults is sufficient and keeps the data model
small.

Alternatives considered: File-backed JSON and SQLite, both rejected as
unnecessary for two shortcuts and local settings.

## Decision: Separate automated and manual validation

Rationale: Filtering, shortcut validation, model state, and permission-state
mapping are testable with XCTest. Live global shortcuts, accessibility prompts,
screen recording prompts, window focus, Spaces, and minimized windows require
manual macOS validation.

Alternatives considered: Full UI automation for every behavior, rejected because
macOS privacy prompts and live window focus are brittle in automated test runs.

## Decision: Use a user-driven drag overlay for privacy recovery

Rationale: macOS privacy lists accept apps via explicit user interaction. A
floating helper panel can make the target obvious by showing the SwitchTab app
as a draggable row while preserving the user-controlled grant flow. This matches
the observed System Settings pattern without relying on synthetic input or
private UI automation.

Alternatives considered: Text-only instructions, which are safer but slower and
less obvious. Automatically clicking the plus button, dragging the app, or
toggling permission, rejected because privacy changes must remain user-driven
and automation would be fragile and likely unacceptable for distribution.

## Decision: Locate System Settings with CoreGraphics window metadata

Rationale: A precise overlay needs the visible System Settings window frame, not
the private view hierarchy inside Settings. `CGWindowListCopyWindowInfo` gives
on-screen window bounds and owner metadata that can be filtered to System
Settings/System Preferences, then converted into AppKit screen coordinates for
panel placement.

Alternatives considered: Hard-coded screen positions, rejected because window
size, display, language, and sidebar width vary. Accessibility inspection of
System Settings internals, rejected because it requires more permission surface
and couples SwitchTab to private Settings layout details.

## Decision: Keep permission panel placement deterministic and testable

Rationale: The positioning calculation can be a pure policy: input Settings
window bounds, visible screen frame, and panel size; output a clamped global
origin. This allows unit tests for small screens, multi-display bounds, and
fallback placement without launching System Settings.

Alternatives considered: Positioning directly inside the panel controller,
rejected because geometry bugs would only be caught manually.

## Decision: Use bounded lookup instead of continuous polling

Rationale: System Settings may take a moment to open the requested privacy pane.
A short bounded lookup after the user clicks Allow is justified, but the app
should stop immediately when the panel is placed or the timeout expires.

Alternatives considered: Continuous polling until permission is granted, rejected
because it violates the performance constraint and creates unnecessary idle
activity.

## Decision: Share one overlay implementation across Accessibility and Screen Recording

Rationale: Both permissions need the same interaction: open a privacy pane,
display a draggable app row, and refresh state when the user returns. A shared
session model with permission-specific copy and settings destination keeps the
implementation small.

Alternatives considered: Separate panels per permission, rejected because it
would duplicate geometry, drag-source, dismissal, and refresh behavior.
