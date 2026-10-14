# Accessibility and compatibility follow-up

## Scope and identity

Follow-up to the [product audit](product-e2e-audit-2026-10-13.md).
Native observations used the signed public SwitchTab 1.1.30 (41) release,
source `7bf7698a65ec9baf25abf00a08ebcca9a75b4e4c`, on the available macOS host
with one physical display. Test changes are isolated from application code.
Evidence is retained locally under `.omo/evidence/accessibility-compat-2026-10-14/`.
Screenshots may contain desktop content and are not published.

## Results

| Surface | Observation | Result |
| --- | --- | --- |
| Safari window selection | Held Command-Backtick selected owned window A; release activated that exact window. | Pass |
| Safari click confirmation | Pressing owned B's overlay tile activated B. | Pass |
| Safari cancellation | Moving selection then Escape preserved A as the focused window. | Pass |
| Safari minimized window | A was minimized, selected by its exact tile identity, restored and focused. | Pass |
| Finder window selection | Modifier release activated owned folder window A. | Pass |
| Finder click/cancellation | Click activated B; cancellation preserved A. | Pass |
| Finder minimized window | A restored from minimized state and became frontmost. | Pass |
| Finder reverse traversal | Forward then Shift-reverse returned selection to owned B; Escape dismissed. | Pass |
| Safari fullscreen | B entered fullscreen; overlay remained available and listed B. After exiting fullscreen the desktop windows were available again. | Pass for current Space only |
| Safari cross-Space discovery | In B's fullscreen Space, System Events did not expose A and the overlay listed only B. The guarded A-selection scenario stopped before input because A was absent. | Limitation observed; cross-Space selection not verified |
| Settings accessibility | Native AX exposed all four section selectors and labeled toggles/slider; VoiceOver navigation visibly moved its cursor to the application description. | Partial |
| VoiceOver speech | VoiceOver ran, but its caption panel was not observable despite the enabled option. No audio recording or utterance transcript was obtained. | Not verified; do not equate AX labels with speech correctness |
| Multiple displays | Host exposed one physical screen. | Not available |

Owned Safari targets were PID 95369 / window IDs 8197 and 8207; Finder targets
were PID 695 / IDs 8280 and 8300. IDs are session evidence, not reusable test
constants. The owned-window driver checked app, title and tile identity before
acting. Existing Finder Downloads and Safari Start Page windows were not closed.

There is no confirmed application-code defect from this follow-up to patch.
In particular, off-Space discovery needs an independent native AX reproduction
before changing window filtering or introducing additional macOS APIs. This run
does not establish that every application or macOS version has the same limit.

## Test maintainability change

`SwitchTabTests/TestRunner.swift` previously ran 33 legacy suites inside one
`testAllSuites` method. A thrown error could stop every later suite and identify
only the aggregate method. Each existing suite now has its own named XCTest
entry point, preserving its original `run()` call and main-actor isolation.
Only the thumbnail suite requires `async`. No assertions were removed or added;
the higher discovered count is improved granularity, not 32 new behaviors.

Baseline: **96 tests, 2 existing optional skips, 0 failures**.
After separation: **128 tests, 2 existing optional skips, 0 failures**.
The About, thumbnail and Settings activation suites also passed as separate
filtered processes. All 33 original suite calls were checked for exact retention.
All 19 shell contract tests, shell syntax checks and direct-distribution
prepare-only validation passed. The secret-scanner contract used the existing
local gitleaks binary explicitly because it was not on the shell PATH.

The earlier `InvalidTransition { phase: idle; targetPhase: failed(deinit) }`
failure was not reproduced in the baseline or three serial isolated aggregate
runs. The error type is not defined in the application/test sources searched.
Its origin remains unconfirmed; no speculative AppKit initialization, retry,
sleep, or exception suppression was added.

Run a legacy functional suite independently with:

```sh
swift test --filter 'SwitchTabTests.SwitchTabTests/testAboutSwitchTabContent'
swift test --filter 'SwitchTabTests.SwitchTabTests/testWindowThumbnail'
```

Use the exact failed XCTest method from CI for investigation. Keep the complete
test run as the regression gate; a passing filtered run does not replace it.

## Measurement status

The existing [site operations runbook](site-operations.md) already specifies
Cloudflare Pages Web Analytics injection. The production HTML fetched during
this audit contained one Cloudflare beacon. Source HTML intentionally lacks the
deployment-injected script; a source-only search is insufficient to conclude
analytics is missing. Beacon presence does not prove dashboard ingestion.

Keep these measures separate:

- Website visits: existing Cloudflare Web Analytics, production hostname and bot filters.
- Download clicks: not established by this audit; Web Analytics is not a custom conversion-event system.
- Asset downloads: GitHub release asset counts cover GitHub delivery only, not R2 or Homebrew delivery. HTTP requests/retries are not unique installations.
- Actual installs or active users: not measured; the native app has no telemetry SDK.

No tracking or privacy behavior changed. Further conversion instrumentation
needs a defined event and destination; adding app telemetry is not needed for
website measurement.

## Restoration and remaining acceptance checks

Owned Finder/Safari windows were closed, fullscreen exited, VoiceOver turned
off, the test caption option disabled, and VoiceOver Utility closed. The original
installed 1.1.29 app bundle was restored after testing 1.1.30. Preferences and
permissions were not reset; normal shortcut-use counters may reflect QA input.

Before claiming complete accessibility/compatibility coverage, obtain actual
VoiceOver utterances for selection changes, section navigation and permission
recovery, and run the same owned-window scenarios on a second physical display.
Cross-Space behavior remains an explicitly open compatibility question.
