# SwitchTab Project History

## How to Use This Document

This is a task-selective decision record, not default context. Read `docs/AI_CONTEXT.md` first, then only the feature section relevant to the work. Current code, tests, README, and operational runbooks outrank historical intent when they disagree.

Each section preserves the problem, shipped decision, rationale, changed and superseded choices, invariants, and evidence. Exact retired sources are recoverable from the `Source Archive Index`; commit `9507cbf` is the last snapshot containing all 43 sources together.

## Product Foundation and Original macOS Scope

**Status:** Shipped and evolved. **Evidence:** initial imports `47cecec`/`52d5bc0`, v1.0, `SwitchTab/AppDelegate.swift`, `Models/`, `Services/`, `UI/`, and `SwitchTabTests/`.

### Context
The original product needed a fast, native, keyboard-first way to identify and focus windows belonging to the frontmost macOS application, with visible previews, configurable shortcuts, safe permission failure, and no idle UI activity.

### Decision
Use a SwiftUI menu-bar/settings shell with AppKit for panels and event handling, Accessibility APIs for cross-process window discovery/focus, ScreenCaptureKit for previews, native hotkey registration, UserDefaults persistence, and a SwiftPM-visible model/service core. Target macOS 14+ and keep one icon-grid interaction with release, Return, click, and Escape paths.

### Rationale
First-party frameworks minimized runtime dependencies and matched the macOS-only scope. AX is required because `NSWindow` cannot inspect other apps; ScreenCaptureKit provides current visual content; service boundaries keep OS effects injectable and testable.

### Changed from Original Plan
Early records mixed a broader app-level switcher and source-only launch-kit ideas with the current-window MVP. The first shipped baseline centered on current-app windows; application switching later shipped separately in v1.1.0. Resize/close/hover arrived in v1.0.7–v1.0.9, and signed distribution replaced the proposed source-only launch posture.

### Invariants
Only eligible windows from the invocation-time frontmost app appear; unavailable targets fail safely; cancel never changes focus; missing Screen Recording removes previews, not window metadata; no continuous polling or synthetic permission changes; settings errors never silently replace a working shortcut.

### Superseded Decisions
The archived task list's presentation preferences and separate list mode were removed in favor of one icon grid. The proposed `docs/index.html`, copy map, and source-only CTA were not adopted as the durable documentation architecture.

### Verification Evidence
Pure behavior is covered by `SwitcherSession`, provider, focus, settings, and overlay suites in `SwitchTabTests/`; `swift test` is canonical. Permission-dependent focus and previews still require a real macOS session. The original quickstart recorded successful SwiftPM/Xcode builds but explicitly did not claim blocked TCC scenarios passed.

## Window Switcher Layout and Filtering

**Status:** Shipped and subsequently refined. **Evidence:** v1.0.7–v1.0.9, `AccessibilityWindowProvider.swift`, `ApplicationSettingsStore.swift`, `SwitcherOverlayLayoutPolicy.swift`, and their tests.

### Context
Single-window overlays were unnecessarily wide, titles competed with previews, users wanted adjustable size, and Chrome Find/non-window AX panels leaked into results.

### Decision
Persist overlay scale, derive tile/thumbnail/icon/spacing metrics from it, let the panel hug content, render window title plus app icon above the preview, and accept only `AXWindow` elements with `AXStandardWindow` subrole through one pure inclusion policy wired to AX element lookup.

### Rationale
Extending the existing layout policy and settings store avoided a second layout system. Filtering at snapshot creation keeps displayed IDs and retained AX elements consistent and prevents UI-specific heuristics.

### Changed from Original Plan
The original segmented Compact/Default/Large preference evolved into the current continuous scale. Later releases changed exact geometry and thumbnail capture quality, but window-mode title, preview, inset, and close behavior remained isolated from application-mode compaction.

### Invariants
Rendered spacing must use the same metrics as panel sizing; one item must not inherit a large minimum width; only standard user-facing AX windows are candidates; a missing title does not exclude a window; app icon lookup reuses the icon store.

### Superseded Decisions
Fixed layout constants and accepting every AX window were replaced by scale-derived metrics and strict role/subrole filtering. Using CGWindowID as the primary AX identity was considered but deferred because it was not required for safe filtering/focus.

### Verification Evidence
`ApplicationSettingsStoreTests`, `SwitcherOverlayPresentationTests`, and `AccessibilityWindowProviderTests` cover persistence, one/multi-row scaling, and accepted mapping. Live Chrome Cmd-F filtering and final visual balance remain manual checks.

## Signed Updates and Local Release Tooling

**Status:** Shipped. **Evidence:** `f56f19a`/`17f0f0e`, `3d61915`/`ac8f4aa`, `5c9d935`, v1.0+, `build-direct-distribution.sh`, `release-local.sh`, and direct-distribution tests.

### Context
Direct DMG users needed trusted self-updates, while the checked-in/App Store-oriented build could not inherit Sparkle review and dependency risk. Maintainers also needed a reproducible local signing/notarization entry point without repeated shell exports.

### Decision
Keep `UpdateChecking` behind an unavailable default adapter and compile Sparkle only in a generated direct-distribution project. Pin Sparkle, embed feed/public key only there, sign nested components, notarize/staple/Gatekeeper-check the DMG, and emit SHA-256. A small local wrapper loads an ignored `.env.release.local` containing identifiers/public values and delegates exactly once to the release builder.

### Rationale
A generated variant preserves one source tree while proving the default project stays Sparkle-free. Sparkle avoids custom-updater security work. The wrapper provides one command without putting project-specific values in global shell profiles or hard-coding a developer identity.

### Changed from Original Plan
The earliest direct-update design deferred publication and assumed ZIP update archives. The implemented release contract standardized on one notarized DMG usable by initial download and Sparkle; R2/appcast/GitHub publication followed in separate scripts.

### Invariants
Never link Sparkle or set `DIRECT_DISTRIBUTION` in the checked-in project; never store private keys/passwords in env files; `--prepare-only` must not sign or publish; release builds require Developer ID and notarization; private EdDSA input stays out of argv and logs.

### Superseded Decisions
A custom updater, Sparkle in all builds, global shell exports, and committed certificate defaults were rejected. Manual sequences were replaced by the local wrapper and later by CI orchestration over the same scripts.

### Verification Evidence
`AppStoreDistributionSettingsTests` protects the build boundary; `release-local-test.sh` uses fake backends; prepare-only generation compiles the direct project. Live signing/notarization is proven by released DMGs rather than fixture tests.

## R2, GitHub Release, and Homebrew Distribution

**Status:** Shipped. **Evidence:** `e5c545d`, `4a51004`, `414a092`, `985c70a`, `82f45ff`, `5980220`, `2cc10f0`, `a26e3a2`, and v1.0+ release assets.

### Context
Signed artifacts needed a reproducible public pipeline with safe retries, an authenticated update feed, GitHub assets, and a narrowly trusted Homebrew handoff shared conceptually with UpdateBar but not coupled by version or secrets.

### Decision
Keep purpose-specific scripts for appcast generation, one-time R2 setup, conditional R2 publication, release-manifest creation, GitHub draft publication, and tap dispatch. Publish immutable versioned DMG/checksum/manifest assets; verify public bytes; update `appcast.xml` last with monotonic-version and ETag guards; publish the GitHub draft only after R2 succeeds; dispatch only repository/tag to an allowlisting tap.

### Rationale
Scripts make local and CI behavior identical and fixture-testable. Draft-first, pointer-last ordering prevents clients seeing missing bytes. Checksums, allowlists, short-lived GitHub App tokens, protected environments, and bucket-scoped R2 credentials narrow trust boundaries.

### Changed from Original Plan
The initial R2 design grew a versioned release manifest and Homebrew receiver contract. Later hardening pinned action/runtime/tool versions, required exact fully qualified tags/main ancestry, separated secret-free verification from protected release, made R2 writes atomic, and handled Sparkle XML version variants and cache-stale public checks.

### Invariants
Never overwrite differing immutable bytes or rebuild a partially published signed tag; same-version reruns are allowed only when bytes match; appcast versions only increase; CI gets no DNS authority; no automatic rollback/deletion; checked-in release docs remain the live operational source.

### Superseded Decisions
Workflow-embedded release logic and one monolithic local/CI script were rejected. A clean runner generating deltas/history was deferred. Cross-repository `GITHUB_TOKEN`, arbitrary manifest URLs/paths, and shared Sparkle keys were rejected.

### Verification Evidence
Contract scripts under `scripts/tests/` fake Apple, Cloudflare, GitHub, Keychain, DNS, and network effects. Released tags include notarized DMG, checksum, and manifest; `release.yml` plus `docs/release-workflow.md` define the current acceptance and partial-failure recovery contract.

## Automatic Pull-Request Versioning

**Status:** Shipped. **Evidence:** `5df2e3d` (v1.0.5), `prepare-pr-version.sh`, `.github/workflows/ci.yml`, `.github/workflows/automatic-release.yml`, and associated contract tests.

### Context
Manual Xcode version edits caused drift, but tags still had to point at source metadata containing the exact released marketing/build version.

### Decision
Trusted same-repository PRs get an idempotent bot commit that updates only active Xcode version declarations from the trusted base: patch by default, minor/major by label, and build number +1. Documentation-only diffs are no-op. Read-only verification runs only after the expected version is present; main merge planning then creates and dispatches the exact annotated tag.

### Rationale
Versioning inside the PR is auditable and avoids merge-time commits, workflow recursion, and tag/source mismatch. A dedicated GitHub App can trigger a fresh synchronize event while the normal token remains read-only.

### Changed from Original Plan
Rollout hardening added author/branch/fork trust guards, no force pushes, branch-up-to-date requirements, conflicting-label failure, malformed/dotted build rejection, exact release-job approval ordering, and documentation-only classification shared with the release planner.

### Invariants
The bot owns Xcode versions; each release-relevant PR increments build exactly once; both release labels are invalid; stale/equal/decreasing versions fail closed; release credentials are never exposed to PR code; docs-only changes neither bump nor release.

### Superseded Decisions
Manual contributor version edits and arbitrary branch-state tag creation were replaced. A merge-time version commit was rejected because it weakens reviewability and complicates workflow triggering.

### Verification Evidence
Preparation, CI workflow, release-planning, and automatic-release contract tests cover calculations, trust gates, idempotence, and unchanged release behavior. v1.0.5 was the first tagged result of the automated PR-version flow.

## Permission Recovery

**Status:** Shipped Finder handoff; proposed drag helper not implemented. **Evidence:** `02cf5a3`/`191f110`, design commit `4db481c`, `PermissionSettingsDestination.swift`, `PermissionService.swift`, and permission recovery tests.

### Context
Accessibility and Screen Recording grants are manual macOS privacy actions. The shipped recovery opens the exact privacy pane and reveals the running app bundle in Finder; a later design proposed a draggable helper over System Settings to reduce window switching.

### Decision
Current code keeps a race-safe, cancellation-aware System Settings/Finder handoff, verifies exact application identities, and refreshes permission state when SwitchTab becomes active. It never grants, toggles, edits TCC, or synthesizes input.

### Rationale
First-party deep links plus Finder expose the exact running bundle while respecting the user-controlled TCC boundary. The proposed non-activating drag panel was sound but would add locator, coordinate, lifecycle, and drag-source complexity without being delivered.

### Changed from Original Plan
The July 26 design approved replacing Finder with a single reusable non-activating panel, bounded System Settings window lookup, and real file-URL drag. The implementation did not occur; current source/tests and copy still explicitly use Finder.

### Invariants
Privacy changes remain user-driven; use the current bundle URL, never a hard-coded install path; no TCC mutation, synthetic input, private Settings hierarchy, or continuous polling; cancellation and wrong-PID events cannot complete a newer recovery session.

### Superseded Decisions
Earlier plain “open Settings” recovery was enhanced with Finder reveal/activation. The drag-helper proposal is retained as an unshipped alternative, not current truth.

### Verification Evidence
`PermissionRecoveryCopyTests`, activation waiter tests, and async tests cover destinations, exact-PID races, cancellation, failures, and Finder result separation. Real grants/revocation and relaunch-dependent preview access require native manual QA.

## Selection Highlight and Thumbnail Quality

**Status:** Shipped. **Evidence:** v1.0.6 (`0cc9260`) and v1.0.9 (`e70c5e9`), overlay presentation/session tests, and thumbnail tests.

### Context
Keyboard selection changed internally while SwiftUI sometimes displayed a stale highlight; fixed 180×112 preview captures also became blurry at large overlay scales. Async close notifications could reflow tiles under a stationary pointer and corrupt perceived selection.

### Decision
Publish overlay state through one stable main-actor observable presentation model. Capture thumbnails asynchronously at a bounded 1.5× rendered viewport using aspect-fill, native-size clamping, and a 480-pixel long-edge cap. Remove closed windows by stable ID, preserve/normalize selection in `SwitcherSession`, reset hover movement origin, and advance the scroll token.

### Rationale
Stable observation fixes the rendering boundary without rebuilding SwiftUI identity. Single-pass adaptive capture improves visible detail without progressive cache/race complexity. Stable-ID removal preserves user intent across delayed AX destruction.

### Changed from Original Plan
The highlight-only patch later gained stable-ID close handling and adaptive capture. About metadata was also split into labeled Version and Build Number lines in the same v1.0.9 delivery.

### Invariants
Navigation semantics remain in session state; async image updates never move selection; captures remain bounded/cancellable; fallback icons survive capture failure; stationary hover cannot steal keyboard selection after reflow; window ordering and permissions are unchanged.

### Superseded Decisions
Forcing new SwiftUI identities/root-view layout, a fixed larger capture, progressive two-pass capture, rebuilding the entire AX list after close, and index-based removal were rejected.

### Verification Evidence
Presentation-model observation, target sizing/aspect ratios, cancellation/cache, close-first/middle/last, delayed destruction, hover gating, scroll-token, and About formatting are covered in `SwitchTabTests/`. Released v1.0.6 and v1.0.9 provide distribution evidence; visual clarity remains a manual comparison.

## Cmd-Tab Application Switching

**Status:** Shipped in v1.1.0 and evolved. **Evidence:** `85e1213`/PR #11, `ApplicationItem.swift`, `RunningApplicationProvider.swift`, `ApplicationActivationService.swift`, `ApplicationSwitchingHotkeyController.swift`, and related tests.

### Context
Users wanted SwitchTab to replace macOS Cmd-Tab without disturbing the existing window shortcut or leaving the system shortcut consumed when SwitchTab was disabled, unprivileged, unavailable, or quit.

### Decision
Add an application mode with regular-running-app filtering, stable bundle/PID identity, separate MRU, active-app-first ordering, existing-overlay reuse, and an independent suppressing EventTap registrar. Only consume a successfully registered application shortcut; release confirms; successful activation alone writes MRU.

### Rationale
Cmd-Tab is reserved and needs an EventTap, while current-window shortcuts can remain Carbon-first. Separate controllers and histories prevent one mode's lifecycle/order from affecting the other. NSWorkspace provides cleaner app inventory/icon data than AX.

### Changed from Original Plan
The approved v1.1.0 design made replacement a fixed Cmd-Tab toggle, off by default, with plain `activate(.activateAllWindows)`. v1.1.4 added coordinated activation; v1.1.6 made the shortcut configurable and fresh-install default enabled while preserving legacy explicit state.

### Invariants
Disabled/failed/terminated application interception leaves native behavior available; current-window registration is independent; application icons/names do not need Screen Recording; active app is pinned first so forward starts at the next app; unavailable/failed targets do not write MRU.

### Superseded Decisions
Fixed Cmd-Tab values and a standalone `Replace macOS Cmd-Tab` setting were replaced by unified per-mode configurations. The original default-off rule now applies only to ambiguous legacy migration, not fresh installs.

### Verification Evidence
Application switching suites cover filtering, identity, MRU keys/order, activation results, registration atomicity, overlay policies, and permission fallback. The Finder/Safari/Notes contract defines native-off, forward/reverse, release activation, disable, permission, relaunch, and quit checks without claiming unrecorded live evidence.

## Compact Application Switcher

**Status:** Shipped in v1.1.0, then superseded in part by v1.1.4 geometry. **Evidence:** `85e1213`, `SwitcherOverlayLayoutPolicy.swift`, `SwitcherIconStripView.swift`, and overlay presentation tests.

### Context
Reusing the window tile made application mode wide and duplicated a small header icon/title above the large app icon.

### Decision
Choose layout metrics by `SwitcherMode`; application mode uses large icons and denser spacing, while window mode retains thumbnails and headers. The initial compact tile placed a centered single-line name below each icon.

### Rationale
Mode-specific metrics reused one overlay/presentation stack without compromising the richer window tile and let more applications fit on screen.

### Changed from Original Plan
Initial targets were about 96-point icons, 120×128 tiles, 8-point gaps, and a selection background around the entire tile. Later focus-layout work reduced gaps, hid unselected names, reserved a stable caption, and restricted selection treatment to the icon container.

### Invariants
Application compaction must not change window preview/title/close geometry; names tail-truncate; scale follows the existing overlay-size setting; keyboard, hover, click, and accessibility selection share the same item identity.

### Superseded Decisions
The entire-tile blue outline and always-visible app names were replaced in v1.1.4. The duplicated window-style header remains removed.

### Verification Evidence
Layout tests compare application/window metrics and column density; source/presentation tests protect the icon-first branch and retained window header. v1.1.0 is the release evidence for the first compact layout.

## Application Switching Interaction Parity

**Status:** Shipped in v1.1.2 with follow-up fixes. **Evidence:** commits `0d08256` through `6ed9efd`, v1.1.2/PR #14, overlay/application/provider tests.

### Context
Modifier release and pointer confirmation were unreliable, fully visible grids scrolled unnecessarily, selection outlines could be clipped, app window counts were absent, and application mode lacked native-style Cmd-Q.

### Decision
Handle trigger release through the session EventTap with AppKit monitors as fallback; keep one shared command state machine; query standard/minimized window counts through AX; allow Cmd-Q normal termination only in application mode and remove a tile only on matching workspace termination; make overflow and mode-specific panel inset explicit.

### Rationale
The EventTap already owns session input and sees modifier transitions reliably. Native termination respects save dialogs/refusal. Explicit scrollability/padding aligns calculated panel bounds with rendering and prevents stationary visible grids.

### Changed from Original Plan
Performance fixes replaced snapshot-heavy per-app counting with isolated count queries and deterministic AX lookup. Follow-ups kept the overlay open during activation while Command remained held, exposed counts to VoiceOver, and removed a retired padding policy after window/application inset regressions were fixed.

### Invariants
Release and click use the same confirmation path; Cmd-W remains window-only; Cmd-Q is not force quit and never optimistically removes a tile; non-overflowing grids stay still; async counts do not destabilize selection; window mode behavior remains intact.

### Superseded Decisions
Depending on global `NSEvent` release alone, always scrolling to selection, one fixed root inset, and counting through full thumbnail snapshots were replaced.

### Verification Evidence
Event-policy, state/controller, application-window summary, termination-notification, scrollability, inset, accessibility, and presentation suites cover the paths. v1.1.2 includes the integrated fixes; real save-dialog and activation behavior still needs native QA.

## Application Switcher Focus Layout

**Status:** Shipped in v1.1.4; Settings routing fixed in v1.1.5. **Evidence:** `2bd2e37`/PR #17, `ebdf06a`/PR #18, activation and overlay presentation tests.

### Context
Users required selected-only captions, symmetric icon padding, a blue outline that did not cover text, natural icon-matched corner curvature, hidden single-window counts, and reliable release/click activation of the selected app's windows.

### Decision
Reserve one fixed caption row for every app but render metadata only for the selection. At default scale use a 96pt icon inside a 104pt selection container, equal 4pt insets, 4pt inter-app spacing, about 14pt caption height, and 26pt selection radius; allow captions up to 240pt and bias edge captions inward. Show counts only at two or more. Activation first dismisses input UI, then requests coordinated activation from the actual frontmost app with `.activateAllWindows`, falling back to ordinary activation.

### Rationale
Separating icon selection and caption eliminates visual overlap while fixed reservation prevents panel jumps. Coordinated activation gives AppKit a legitimate focus handoff source even though SwitchTab's panel is non-activating.

### Changed from Original Plan
This explicitly superseded the v1.1.0 whole-tile selection and all-name layout and the v1.1.2 every-known-count caption. After release, Command-comma exposed an empty implicit Settings scene; v1.1.5 replaced that command to open the custom SwitchTab settings controller.

### Invariants
Only the selected app shows a centered name; counts show only when >=2; outline/background cover only the icon container; all tiles reserve equal height; long captions do not change grid geometry; activation success is required before MRU promotion; window mode remains unchanged.

### Superseded Decisions
Plain target activation, whole-tile outlining, always-visible names, counts of zero/one, and an unmanaged SwiftUI Settings scene were replaced by coordinated handoff, focused metadata, and explicit settings routing.

### Verification Evidence
Tests lock metadata visibility, geometry, caption bounds, activation source/options, common confirmation coordinator, and success-only MRU. v1.1.4 and v1.1.5 are the shipped release evidence; Finder/Safari/TextEdit focus matching is the native QA contract.

## Configurable Independent Shortcuts

**Status:** Shipped in v1.1.6. **Evidence:** `af0a189`, shortcut model/store/view-model/controller/UI files, and shortcut suites.

### Context
Both modes needed the same visible enabled state, editable shortcut, and reset action. Users also needed to edit a disabled mode without activating it, while the two fundamentally different registrars stayed safe and independent.

### Decision
Persist two `SwitcherShortcutConfiguration` values in one versioned payload. Settings renders matching rows with Enabled/Disabled text, toggle, keycap recorder, and reset. Recording temporarily unregisters both modes, validates modifiers/physical-key and Shift-reverse conflicts, preflights registration, commits on success, and restores previous live registrations on failure.

### Rationale
One configuration/store/UI model prevents inconsistent settings behavior, but retaining Carbon-style window and EventTap application registrars preserves their distinct input semantics. Transactional registration ensures a bad edit never destroys a working shortcut.

### Changed from Original Plan
The UI was refined from a lone app-replacement toggle to two full rows. Fresh installs enable Command-Backtick and Command-Tab; explicit legacy app state is preserved, while installations with known old data but no explicit state migrate application switching off. v1.1.5's custom Command-comma settings window remains the entry point.

### Invariants
Each mode enables/disables independently; disabled shortcuts remain editable; reset changes the shortcut only; reverse is Shift-toggled; duplicate/conflicting physical keys are rejected; recording Escape is non-mutating; failed registration keeps saved intent/error guidance without consuming input.

### Superseded Decisions
Window-only shortcut persistence, `ApplicationSettingsStore` ownership of `replacesCommandTab`, fixed application Cmd-Tab, and the separate replacement row were retired. Legacy keys remain only for one-time migration/rollback compatibility.

### Verification Evidence
`ShortcutCaptureTests`, `ShortcutSettingsStoreTests`, registration/controller tests, view-model permission tests, and settings layout/presentation tests cover defaults, migration, conflict, rollback, toggles, recording, and persistence. v1.1.6 is the shipped release evidence.

## Update Error Diagnostics

**Status:** Shipped in v1.1.1. **Evidence:** `14f0f9c`, `UpdateDiagnostic.swift`, direct-only Sparkle presenter/user driver, and diagnostic/distribution tests.

### Context
Sparkle's generic failure alert did not tell users whether a network, TLS, feed, download, validation, or installation problem occurred and offered no privacy-safe support path.

### Decision
Classify the `NSError`/underlying chain in a Sparkle-independent Foundation model and format a sanitized payload containing only app/build, macOS, architecture, category/stage, domain/code, and UTC time. In direct builds only, override Sparkle's error callback with a native alert offering retry, manual download, copy diagnostics, and a prefilled—but never auto-submitted—GitHub issue.

### Rationale
One formatter prevents clipboard, issue, alert, and unified-log drift. Stable codes are actionable without leaking raw localized strings, URLs, usernames, paths, IPs, hostnames, or full logs. A narrow user-driver override retains standard Sparkle UI for all non-error states.

### Changed from Original Plan
The implementation used Sparkle 2.9.4's verified throwing start path and acknowledgement-before-next-run-loop retry to avoid overlapping update sessions; default/App Store builds remained compilation-tested without Sparkle.

### Invariants
No automatic diagnostic transmission or issue submission; background failures do not create unsolicited alerts unless Sparkle already exposed the cycle; raw localized errors are excluded; default project remains Sparkle-free; normal update-found/install UI remains standard Sparkle.

### Superseded Decisions
The generic Sparkle error surface was replaced only for failures. A general log viewer, telemetry, upload service, and a fully custom updater were rejected.

### Verification Evidence
`UpdateDiagnosticTests` covers categories, nested errors, deterministic formatting, URL encoding, retry order, and privacy fixtures. Distribution tests enforce direct-only guards and generated-project compilation; v1.1.1 is release evidence.

## Documentation Structure

**Status:** Shipped and maintained. **Evidence:** design commit history through `6096d25`, `README.md`, `docs/development.md`, `direct-distribution.md`, `update-hosting.md`, `release-workflow.md`, and `repository-maintenance.md`.

### Context
The README mixed first-time product guidance with long credential, hosting, release, and recovery procedures, making both user scanning and maintenance difficult.

### Decision
Keep README user-first with product behavior, permissions/privacy, minimal setup, and a documentation index. Put development, direct build, R2/Sparkle hosting, release automation, and repository audits in focused live runbooks; keep documentation in English and contract-test important links/safety text.

### Rationale
Audience-based boundaries reduce duplication and prevent operational detail from obscuring the product. Focused runbooks can evolve independently while README stays concise.

### Changed from Original Plan
The approved restructure was implemented without the earlier launch-kit static site/copy-map/GIF requirement. Product documentation later added application switching, interaction semantics, free-forever positioning, and configurable shortcuts as they shipped.

### Invariants
README claims must match current behavior and distribution reality; operational safety and credential boundaries stay in live docs; links are repository-relative and tested; do not invent download/license/support claims.

### Superseded Decisions
One monolithic README and a proposed `docs/index.html` launch surface were replaced by README plus focused Markdown guides. Historical implementation plans are no longer operational documentation.

### Verification Evidence
`AppStoreDistributionSettingsTests` and shell documentation contracts verify guide presence/content; current README links all live guides. Git history records incremental behavior and safety corrections.

## Documentation Compaction

**Status:** Implemented by this documentation-only change. **Evidence:** design `301ae1e`, plan `9507cbf`, AI context `54c25f5`, and this file.

### Context
Completed Superpowers and Spec Kit trees totaled roughly 13,400 lines and the default agent route loaded a completed 243-line plan, spending context on copied code, checklists, and superseded detail.

### Decision
Use `docs/AI_CONTEXT.md` (current truth, <=200 lines) as default context and this task-selective history (<=600 lines) for decisions/rationale/change evidence. Delete completed plan/spec trees from the current branch only after a source-by-source audit; keep exact originals in Git.

### Rationale
Two layers separate frequently needed operating truth from occasional history. Feature-local `Changed from Original Plan` and `Superseded Decisions` retain cause and consequence better than a standalone `CHANGED.md`; Git remains the lossless archive without polluting search/context with an archive directory.

### Changed from Original Plan
The inventory contains 43 files after including the compaction design and execution plan themselves. The final dangling-reference audit intentionally excludes this archive index because it must retain each exact retired path for recovery.

### Invariants
Current code/tests/runbooks outrank history; every retired source maps exactly once below; no runtime/release behavior changes; default context stays <=200 lines and history <=600; decisions, rationale, changed/superseded choices, risks, invariants, and evidence are preserved.

### Superseded Decisions
Keeping every completed plan in-tree, moving them into `archive/`, or adding a separate `CHANGED.md` were rejected because each keeps too much context visible or separates changes from rationale.

### Verification Evidence
Line budgets, exact source count, route checks, removed-path checks excluding this index, `git diff --check`, documentation contracts, `swift test`, and a documentation-only diff are the completion gates.

## Source Archive Index

All paths below exist together at commit `9507cbf`. Recover one with `git show 9507cbf:<path>`; discover other revisions with `git log --all -- <path>`. The section column is the single consolidation destination for that source.

| Retired source path | Consolidated section |
| --- | --- |
| `specs/001-macos-switchtab/spec.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/plan.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/research.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/data-model.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/tasks.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/quickstart.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/launch-kit-plan.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/contracts/switcher-behavior.md` | Product Foundation and Original macOS Scope |
| `specs/001-macos-switchtab/checklists/requirements.md` | Product Foundation and Original macOS Scope |
| `docs/superpowers/plans/2026-07-02-overlay-sizing-header-window-filter.md` | Window Switcher Layout and Filtering |
| `docs/superpowers/plans/2026-07-02-direct-release-automation-followup.md` | Signed Updates and Local Release Tooling |
| `docs/superpowers/plans/2026-07-02-sparkle-direct-update.md` | Signed Updates and Local Release Tooling |
| `docs/superpowers/specs/2026-07-02-sparkle-direct-update-design.md` | Signed Updates and Local Release Tooling |
| `docs/superpowers/plans/2026-07-20-local-release-wrapper.md` | Signed Updates and Local Release Tooling |
| `docs/superpowers/specs/2026-07-20-local-release-wrapper-design.md` | Signed Updates and Local Release Tooling |
| `docs/superpowers/plans/2026-07-21-sparkle-r2-github-release.md` | R2, GitHub Release, and Homebrew Distribution |
| `docs/superpowers/specs/2026-07-21-sparkle-r2-github-release-design.md` | R2, GitHub Release, and Homebrew Distribution |
| `docs/superpowers/plans/2026-07-22-homebrew-tap-release-automation.md` | R2, GitHub Release, and Homebrew Distribution |
| `docs/superpowers/plans/2026-07-22-switchtab-homebrew-release-integration.md` | R2, GitHub Release, and Homebrew Distribution |
| `docs/superpowers/plans/2026-07-22-updatebar-sparkle-release-automation.md` | R2, GitHub Release, and Homebrew Distribution |
| `docs/superpowers/specs/2026-07-22-unified-release-operations-design.md` | R2, GitHub Release, and Homebrew Distribution |
| `docs/superpowers/plans/2026-07-27-automatic-pr-versioning.md` | Automatic Pull-Request Versioning |
| `docs/superpowers/specs/2026-07-26-automatic-pr-versioning-design.md` | Automatic Pull-Request Versioning |
| `docs/superpowers/specs/2026-07-26-permission-drag-helper-design.md` | Permission Recovery |
| `docs/superpowers/plans/2026-07-27-switcher-selection-visual-sync.md` | Selection Highlight and Thumbnail Quality |
| `docs/superpowers/specs/2026-07-27-switcher-selection-visual-sync-design.md` | Selection Highlight and Thumbnail Quality |
| `docs/superpowers/plans/2026-07-28-adaptive-thumbnail-quality.md` | Selection Highlight and Thumbnail Quality |
| `docs/superpowers/specs/2026-07-28-adaptive-thumbnail-quality-design.md` | Selection Highlight and Thumbnail Quality |
| `docs/superpowers/plans/2026-07-29-application-switching-cmd-tab.md` | Cmd-Tab Application Switching |
| `docs/superpowers/specs/2026-07-29-application-switching-cmd-tab-design.md` | Cmd-Tab Application Switching |
| `docs/superpowers/plans/2026-07-29-compact-application-switcher.md` | Compact Application Switcher |
| `docs/superpowers/specs/2026-07-29-compact-application-switcher-design.md` | Compact Application Switcher |
| `docs/superpowers/plans/2026-07-30-application-switcher-interaction-parity.md` | Application Switching Interaction Parity |
| `docs/superpowers/specs/2026-07-30-application-switcher-interaction-parity-design.md` | Application Switching Interaction Parity |
| `docs/superpowers/plans/2026-07-31-application-switcher-focus-layout.md` | Application Switcher Focus Layout |
| `docs/superpowers/specs/2026-07-31-application-switcher-focus-layout-design.md` | Application Switcher Focus Layout |
| `docs/superpowers/plans/2026-08-02-configurable-switcher-shortcuts.md` | Configurable Independent Shortcuts |
| `docs/superpowers/specs/2026-08-02-configurable-switcher-shortcuts-design.md` | Configurable Independent Shortcuts |
| `docs/superpowers/plans/2026-07-30-update-error-diagnostics.md` | Update Error Diagnostics |
| `docs/superpowers/specs/2026-07-30-update-error-diagnostics-design.md` | Update Error Diagnostics |
| `docs/superpowers/specs/2026-07-29-readme-documentation-restructure-design.md` | Documentation Structure |
| `docs/superpowers/specs/2026-08-03-documentation-compaction-design.md` | Documentation Compaction |
| `docs/superpowers/plans/2026-08-03-documentation-compaction.md` | Documentation Compaction |
