# Switching Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute this plan with specification and code review.

**Goal:** Explain an empty window list and confirm verified Practice success without taking focus or changing switching behavior.

**Architecture:** AppDelegate owns one passive, nonactivating feedback panel. Empty discovery emits a notice after permission checks; verified Practice emits success only when its current verification generation completes. The existing session, event tap, selection, and MRU logic remain authoritative.

**Tech Stack:** Swift 6, AppKit, SwiftUI, XCTest, macOS 14+.

Implementation and local verification are complete. See
[`switching-feedback-qa-2026-10-17.md`](../../switching-feedback-qa-2026-10-17.md)
for evidence, restoration, and the unverified VoiceOver announcement limitation.
The checklist below preserves the execution plan; delivery status is recorded
in the pull request.

## Task 1 — Feedback and integration

- [x] Add regression tests in `SwitchTabTests/Services/SwitchingPracticeTests.swift` for a success result from verification, rejecting stale, cancelled, failed, and duplicate completion.
- [x] Make `SwitchingPracticeModel.verify` return whether this call completed the active practice, preserving persistence and existing state transitions.
- [x] Add `SwitchTab/UI/Overlay/SwitchingFeedbackController.swift` with explicit no-windows and practice-completed messages. Its borderless nonactivating panel cannot become key/main, ignores mouse input, and auto-dismisses. Cancel previous dismissal work so stale timers cannot hide newer feedback. Suppress repeated identical announcements while visible.
- [x] Place feedback inside the pointer screen's visible frame, above the centered switcher. Use existing screen-selection policy. Expose readable static text to accessibility and request an announcement without changing accessibility focus.
- [x] Wire AppDelegate: show no-windows only after successful permission check and empty discovery, including retained handoff; show success only for a true verification return. Dismiss notices on a new successful switching presentation, Settings/Practice entry, and termination. Preserve retained-session failure, release, Escape, and MRU behavior.
- [x] Update `SwitchingGuideView.swift` so the instructions describe immediate verified feedback and returning to How to Use for recovery. Register the new controller in `SwitchTab.xcodeproj/project.pbxproj`.
- [x] Add deterministic controller tests in `SwitchTabTests/Services/SwitchingFeedbackTests.swift` for passive window properties, repeated notices, replacement, dismissal cancellation, and screen placement. Avoid real-time sleeps where possible.
- [x] Run `rtk proxy swift test --scratch-path "$SWITCHTAB_PRIMARY_CHECKOUT/.build/product-e2e-spm"`; then specification review followed by quality review. Resolve all material findings.

## Task 2 — Native verification and delivery

- [x] Build the full unsigned app using the existing `product-e2e-xcode` derived-data directory.
- [x] Run owned-fixture checks: fresh empty list; empty handoff retains selection and release/cancel behavior; exact-window Practice completion; cancellation never announces success; notice does not activate SwitchTab or intercept input; automatic dismissal and rapid replacement.
- [x] Preserve and restore installed app, preferences, modifiers, and owned fixtures. Record actual accessibility announcement evidence separately from AX-tree assertions.
- [x] Update `docs/AI_CONTEXT.md` and a focused QA report with observed results and environmental limits. Do not claim other OS or physical multi-monitor coverage.
- [ ] Commit, push, and validate PR checks. Let CI own version preparation. Release only after checks and required QA pass.
