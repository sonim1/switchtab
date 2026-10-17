# Switching feedback verification — 2026-10-17

## Change

Empty window discovery now explains that there are no windows to switch to.
Practice displays success only after observing focus on the exact selected
window for its current verification generation. Neither notice activates the
app, accepts input, opens Settings, or changes switching/MRU rules.

One AppKit panel handles both messages. It dismisses after three seconds,
suppresses duplicate visible notices, and invalidates old dismissal work when
replaced. Placement uses the pointer screen's visible frame and moves below
the overlay when there is insufficient room above it.

## Automated and review evidence

- Baseline: 128 tests, two optional skips, zero failures.
- Updated suite: 133 tests, two optional skips, zero failures.
- Focused feedback/Practice checks: 17 tests, zero failures.
- Full unsigned Xcode Debug app build succeeded on Apple silicon.
- Separate specification and code-quality reviews found no material issues.
- Direct-distribution workspace preparation succeeded.
- All shell contract tests and shell syntax checks passed. The documentation
  privacy check initially caught a local path in the plan; it was removed before
  the successful full rerun.
- Coverage includes stale/cancelled/duplicate Practice verification, passive
  window properties, duplicate announcements, timer replacement, real timeout,
  and screen bounds/overlay placement.

## Native observations

Host: Apple M1, macOS 26.5.1, one display. The Debug candidate was signed with
the existing Developer ID and run at the established installation path using
existing Accessibility and Screen Recording permissions.

Final candidate executable SHA-256:
`f884c159f512a67bdf5cf505ebb7e1bb5bc3d977947b5fa23490d13693dfc66c`.

| Scenario | Observed result |
| --- | --- |
| Fresh switch in owned zero-window fixture | Readable empty notice, fixture remains frontmost, notice disappears automatically. |
| Empty app-to-window handoff, repeated attempt, Escape | Same app tile stays selected; cancellation ends the overlay without changing the target app. |
| Empty handoff, repeated attempt, modifier release | Same selected owned app is confirmed; no leftover overlay or notice after timeout. |
| Practice confirmation | Exact selected owned window becomes main/frontmost; success text is visible in the feedback panel. |
| Practice cancellation and reopen | Original window and next MRU selection retained; no success notice; guide reports cancellation. |
| Application traversal/cancel and successful mode handoff | Existing bounded native drivers pass. |
| Visual and AX inspection | Both messages fit in the panel; static text exposes identifier `switching-feedback`. Updated guide remains readable. |
| VoiceOver announcement | Native screenshot captures show the empty notice and the full Practice completion sentence in VoiceOver's caption panel. |

The nonshipping window fixture accepts `--empty-windows`; ordinary launches
still create three owned disposable windows. The existing driver records
feedback text after confirmation. Raw logs are kept locally under the ignored
`.omo/evidence/switching-feedback-2026-10-17/` directory.

## VoiceOver correction and limits

The caption window was unavailable through the automation tool's accessibility
tree. Native macOS screenshot capture provided separate evidence of generated
utterances. Initial Practice captures at 0.5 and 1.2 seconds showed only “system
dialog”: AppKit classified the passive NSPanel as `AXSystemDialog`. Explicitly
assigning `AXFloatingWindow` corrected the classification. The same 1.2-second
scenario then displayed the complete success sentence while the owned target
retained keyboard focus. Announcement timing and priority were unchanged.

A regression assertion failed for the original subrole and passed after the
correction. Duplicate visible announcement requests are covered by tests;
captures do not establish audible voice quality or every possible speech
interruption. The code uses Apple's documented
[announcementRequested notification](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested).

Other macOS versions, physical multi-monitor placement, TCC revocation, and
large-list performance were not tested in this change. No permissions were
granted or reset for these checks.

After testing, the exact original installed app was restored and its signature
and executable SHA-256 matched the pre-test baseline. Only the Practice completion
key created by the test was removed; other user preferences were preserved.
The owned fixture and VoiceOver were stopped and the caption-panel setting was
restored to off.
