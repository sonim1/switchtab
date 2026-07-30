# Update Error Diagnostics Design

## Goal

Replace Sparkle's generic update failure alert with an actionable SwitchTab
alert. A user should understand the likely failure category, retry or download
the release manually, copy safe diagnostics, and open a prefilled GitHub issue.

## Scope

- Applies only to the direct-distribution build that includes Sparkle.
- Keeps Sparkle's existing update-found, download, extraction, and installation
  UI unchanged.
- Replaces only the user-visible updater error alert.
- Records a sanitized entry in the macOS unified log for later support.

The App Store-oriented build remains Sparkle-free. This feature does not add a
general-purpose log viewer, remote telemetry, automatic log upload, or automatic
issue submission.

## User Experience

The error alert uses a two-level hierarchy:

1. A plain-language title and explanation identify the likely category. For a
   network failure, the alert explains that a company network, VPN, or security
   proxy may be blocking the update server.
2. A compact technical line shows the failed stage and stable error identifier,
   such as `Feed download · NSURLErrorDomain -1200`.

Primary actions:

- **Try Again** acknowledges the failed update cycle and starts a new
  user-initiated check after Sparkle finishes tearing down the old cycle.
- **Download Manually** opens the repository's latest GitHub Release page.
- **Cancel** dismisses the alert.

Diagnostic actions appear as secondary link-style controls:

- **Copy Diagnostics** copies the sanitized diagnostic report without closing
  the alert.
- **Report Issue** opens a new GitHub issue page with the diagnostic report
  prefilled. The user reviews and submits the issue; SwitchTab never submits it.

## Error Classification

`UpdateErrorClassifier` walks the `NSError` and its underlying-error chain. It
maps the first recognized error to one of these presentation categories:

- Offline or connection failure
- Timeout
- TLS or certificate failure
- Invalid update feed
- Download failure
- Signature or validation failure
- Installation or permission failure
- Unknown updater failure

The classifier recognizes `NSURLErrorDomain` and `SUSparkleErrorDomain` codes.
Unknown errors retain only their domain and numeric code. Raw localized error
text is not placed in reports because it may contain a URL, filesystem path, or
other machine-specific data.

## Diagnostic Payload

`UpdateDiagnostic` is a value type containing only:

- SwitchTab marketing version and build number
- macOS product version
- CPU architecture
- update stage/category
- error domain and numeric code
- UTC timestamp

It excludes usernames, home-directory paths, IP addresses, device names, feed
query parameters, and full system logs. The same formatter supplies the alert's
technical line, clipboard text, GitHub issue body, and unified-log message so
the four surfaces cannot drift.

The GitHub issue URL targets
`https://github.com/sonim1/switchtab/issues/new`. Its title identifies the
update category and its body contains the sanitized diagnostic payload plus a
prompt for the user to describe their network and reproduction steps.

## Sparkle Integration

`SwitchTabUpdateUserDriver` subclasses `SPUStandardUserDriver` and overrides only
`showUpdaterError(_:acknowledgement:)`. All other `SPUUserDriver` behavior stays
with Sparkle's standard implementation.

`SparkleUpdateController` creates an `SPUUpdater` with this user driver instead
of using `SPUStandardUpdaterController`. The controller remains responsible for
starting the updater and exposing the existing `UpdateChecking` properties.

The custom user driver delegates alert presentation to an AppKit presenter and
returns a small action value. It acknowledges Sparkle's failed cycle before the
controller schedules a retry on the next main-run-loop turn. This prevents a
second check from racing a session that Sparkle is still dismantling.

If `SPUUpdater.startUpdater` fails because the app is misconfigured, the same
classifier and presenter display the configuration error. Scheduled background
failures are logged but do not interrupt the user with a new alert unless
Sparkle has already made that update cycle visible.

## AppKit Presentation

The presenter uses a native `NSAlert` rather than introducing a new SwiftUI
window. The main buttons are Try Again, Download Manually, and Cancel. An
accessory view contains the technical line plus Copy Diagnostics and Report
Issue link-style buttons. The alert is accessible by keyboard and VoiceOver and
uses system colors in light and dark mode.

Clipboard writes use `NSPasteboard`. External pages open through `NSWorkspace`.
URL construction uses `URLComponents` so prefilled issue text is encoded safely.

## Testing

Unit tests cover:

- classification of offline, timeout, TLS, feed, download, signature,
  validation, installation, permission, and unknown errors;
- recognition of a relevant underlying error;
- retry ordering after acknowledgement;
- manual-download and report URLs;
- deterministic diagnostic formatting; and
- privacy assertions that diagnostics contain none of the supplied URL,
  username, or filesystem-path fixtures.

Existing update-controller and distribution-boundary tests must continue to
pass. The generated direct-distribution project must compile against pinned
Sparkle 2.9.4. Manual QA forces a feed connection failure, verifies all alert
actions, then restores the valid feed and confirms the normal update-found flow
still reaches the existing Sparkle UI.

## Success Criteria

- A failed user-initiated update check no longer shows Sparkle's generic
  "retrieving update information" message.
- The alert names a useful failure category and exposes a stable domain/code.
- Retry, manual download, copy, and report actions work without duplicate
  alerts or overlapping Sparkle sessions.
- No diagnostic action transmits data automatically.
- Direct-distribution and default/App Store-oriented builds keep their current
  dependency boundary and pass their existing test suites.
