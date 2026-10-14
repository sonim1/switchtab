# Accessibility and compatibility follow-up

## Scope and identity

Follow-up to the [product audit](product-e2e-audit-2026-10-13.md).
Native observations used the signed public SwitchTab 1.1.30 (41) release,
source `7bf7698a65ec9baf25abf00a08ebcca9a75b4e4c`, on the available macOS host
with one physical display. A subsequent native follow-up used locally signed
Debug candidates on macOS 26.5.1 (25F80).
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
| Settings accessibility | Native AX exposed all four sections; the follow-up captured VoiceOver announcing the selected Permissions section and recovery controls. | Pass on this host |
| VoiceOver speech | Caption captures reproduced an overlay selection/focus mismatch missed by the initial AX-only check. The follow-up validates the fix against actual utterances. | See follow-up below |
| Multiple displays | Host exposed one physical screen. | Not available |

Owned Safari targets were PID 95369 / window IDs 8197 and 8207; Finder targets
were PID 695 / IDs 8280 and 8300. IDs are session evidence, not reusable test
constants. The owned-window driver checked app, title and tile identity before
acting. Existing Finder Downloads and Safari Start Page windows were not closed.

The initial pass found no confirmed application-code defect. The subsequent
VoiceOver caption pass reproduced a selection/focus mismatch: the visually
selected window changed while VoiceOver remained on the previous unselected
button. AX labels alone had not detected that problem.

## Native follow-up evidence

The caption panel became observable through its own CGWindow ID. These captures
record VoiceOver-generated utterances, rather than inferred AX labels; they do
not establish audio quality or behavior on every supported macOS version.

Settings navigation announced the selected Permissions radio button as item 3
of 4. The permission fixture announced the required Accessibility permission,
the optional Screen Recording permission, the recovery path, and both recovery
button names. Only the isolated view fixture simulated missing permissions;
host TCC permissions were not revoked or granted. Evidence includes
`vo-selected-permissions-radio.png`, `vo-permission-section.png`,
`vo-permission-recovery.png`, `vo-permission-button.png`, and
`vo-screen-recording-button.png`.

The fullscreen observation was independently reproduced with native
`AXUIElementCopyAttributeValue(kAXWindowsAttribute)` against the owned window
fixture: three standard windows on the desktop, only the fullscreen window
while that Space was active, and three again after exiting fullscreen.
`ax-restored-desktop.log`, `ax-fullscreen.log`, and `ax-after-fullscreen.log`
capture that boundary. SwitchTab's role filter cannot recover windows absent
from the source AX list. No private Spaces API or speculative discovery change
was introduced; cross-Space switching remains outside verified coverage.

Added coordinate regression cases cover negative-left and vertically arranged
screen origins, a shared screen boundary, offset visible-frame centering, and
an empty-screen/no-fallback result. They verify the existing placement policy;
they do not replace physical multi-monitor testing.

## Overlay accessibility correction

SwiftUI's virtualized tile focus could diverge from the selected item, especially
after reopening or changing modes. The primary tile now uses an AppKit button
with the existing SwiftUI content. It preserves the button role, selected value,
identifier and target/action. Decorative content neither intercepts clicks nor
creates duplicate accessibility children.

The controller publishes a new focus generation for presentation and keyboard
selection changes, and clears it on dismissal. Metadata-only refreshes do not
request focus. The native button applies matching requests after layout while
the panel is key and VoiceOver is enabled. No timed retries or private AX APIs
are involved. The grid's accessibility identity resets on a new presentation
or item-identity sequence, preserving stable identity during selection and
thumbnail updates.

Accessibility traversal starts with the initially selected item and proceeds
forward, wrapping at the end. This order remains fixed during selection changes;
visual order is unchanged. The primary tile precedes its close control. Close
buttons remain AX-exposed but do not take ordinary keyboard focus from the
switcher, whose keyboard navigation and close command are handled centrally.

Actual caption evidence includes `vo-cyclic-reopen.png` (selected application),
`vo-cyclic-mode.png` (window-mode handoff), `vo-cyclic-rapid.png` (rapid forward
wrap), `vo-cyclic-reverse.png` (reverse selection), and
`vo-close-fixed-reopen.png` (middle-item window selection on reopen). Modifier
release activated the exact selected owned B window. The AX close action removed
only the owned A window and left the session open.

The final candidate also passed middle-item reopening (`vo-final-window-open.png`),
mouse close of owned C with B remaining selected and focused, and application
tile click confirmation with VoiceOver off. The post-close caption
`vo-final-close-selection.png` contains the selected tile's delayed switch hint;
the exact remaining identity was checked in the native AX tree. Close-button
AX activation was verified; a separate held-modifier VO-Space gesture was not
verified because the input driver could release the switcher's modifier.

Final source validation: 128 XCTest cases, 2 existing optional skips, 0 failures
(`voiceover-final-unit.log`); complete unsigned Xcode Debug build
(`voiceover-final-build.log`); signed installed-candidate verification and native
checks; distribution prepare-only (`voiceover-final-prepare.log`). The 19 shell
contracts and shell syntax checks passed earlier in this follow-up. Independent
read-only review found no additional actionable defect. Temporary diagnostics
were removed before the final build.

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
The locally signed follow-up candidate and both owned fixtures were also
terminated, VoiceOver/captions disabled, and the original installed bundle
restored with strict signature verification and matching executable SHA-256
`a22941c8963fbc956e9274c89378debdc7f8601b8070f10dc9533c034597de72`.

Actual VoiceOver utterances for selection, section navigation and permission
recovery are now captured. Physical multi-monitor testing and equivalent native
checks on macOS 14/15 remain unavailable on this host. Cross-Space behavior
remains an explicitly open compatibility question at the source AX boundary.
