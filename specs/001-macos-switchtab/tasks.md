# Archived Tasks: macOS SwitchTab

> Maintenance note (2026-07-12): this is an archived generated checklist, not
> the active implementation plan. It preserves earlier app-level switching
> planning and prior source/test names for history. Use `spec.md`, `plan.md`,
> `contracts/switcher-behavior.md`, `quickstart.md`, and `README.md` for the
> current implementation scope, source map, and verification flow.

**Input**: Design documents from `/specs/001-macos-switchtab/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/switcher-behavior.md, quickstart.md

**Tests**: Included because the constitution requires automated tests for behavior that can be validated without live macOS UI state, and the plan specifies XCTest for pure logic and service boundaries.

**Archived organization**: Tasks are grouped by historical user story. This
checklist may mention app-level switching work that is outside the current
checked-in implementation scope.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when it touches different files and has no dependency on incomplete tasks
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- App target: `SwitchTab/`
- Test target: `SwitchTabTests/`
- Feature docs: `specs/001-macos-switchtab/`

## Archived Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the existing implementation baseline and prepare the project for the simplified icon-strip behavior.

- [X] T001 Review current app-switch overlay behavior in `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift` and `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- [X] T002 [P] Review current settings behavior in `SwitchTab/UI/Settings/ShortcutSettingsView.swift` and `SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift`
- [X] T003 [P] Review current app activation behavior in `SwitchTab/Services/AppSwitchingService.swift`
- [X] T004 [P] Review current window confirmation behavior in `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`

---

## Archived Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Remove obsolete presentation preferences and keep the shared shortcut/session state required before updated app-switcher and settings stories can work.

**CRITICAL**: No user story work begins until this phase is complete.

- [X] T005 [P] Create failing session tests for release-first confirmation in `SwitchTabTests/Services/AppSwitcherConfirmationTests.swift`
- [X] T006 [P] Create source hygiene tests that obsolete presentation preference files do not return in `SwitchTabTests/Services/OverlaySourceHygieneTests.swift`
- [X] T007 Remove `SwitcherPreferences` and list-presentation preference state from runtime models.
- [X] T008 Keep UserDefaults-backed shortcut and registration-message persistence in `SwitchTab/Services/ShortcutSettingsStore.swift`
- [X] T009 Keep `SwitcherSession` focused on mode, items, and selected index in `SwitchTab/Models/SwitcherSession.swift`
- [X] T010 Add new model, service, and test files to the Xcode project in `SwitchTab.xcodeproj/project.pbxproj`
- [X] T011 Run preference model and store tests through `SwitchTabTests/TestRunner.swift`

**Checkpoint**: Shared shortcut/session state is ready, persisted where needed, and test-covered.

---

## Archived Phase 3: Historical User Story 1 - Switch Between Open Applications

This phase is retained as historical planning context. App-level switching is
outside the current checked-in implementation scope.

**Goal**: Press the app-level shortcut, see the icon strip, move selection with keyboard input, and activate the selected app by Enter, shortcut release, or click.

**Independent Test**: Open at least three applications, invoke the app switcher, navigate to another application, confirm by shortcut release, press Enter, click an item, and confirm the selected application becomes active.

### Tests for User Story 1

- [X] T012 [P] [US1] Create failing app-switch icon-strip presentation tests in `SwitchTabTests/Services/AppSwitcherPresentationTests.swift`
- [X] T013 [P] [US1] Create failing app-switch confirmation tests for Enter and shortcut release in `SwitchTabTests/Services/AppSwitcherConfirmationTests.swift`
- [X] T014 [P] [US1] Create failing app click-confirmation tests in `SwitchTabTests/Services/AppSwitcherClickConfirmationTests.swift`
- [X] T015 [P] [US1] Create failing foreground activation option tests in `SwitchTabTests/Services/AppSwitchingServiceTests.swift`

### Implementation for User Story 1

- [X] T016 [US1] Load app-switcher presentation and selection preferences when creating app sessions in `SwitchTab/AppDelegate.swift` and `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- [X] T017 [US1] Add list-mode Enter versus shortcut-release commit behavior in `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- [X] T018 [US1] Add repeated app-switch shortcut cycling for icon-strip mode in `SwitchTab/Services/HotkeyService.swift` and `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- [X] T019 [US1] Implement horizontal icon-strip app presentation in `SwitchTab/UI/Overlay/AppSwitcherIconStripView.swift`
- [X] T020 [US1] Render list or icon-strip app presentation from active session preferences in `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- [X] T021 [US1] Route clicks on app rows and icons through the same confirmation path as keyboard confirmation in `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift` and `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- [X] T022 [US1] Ensure selected app activation uses foreground-capable AppKit activation options in `SwitchTab/Services/AppSwitchingService.swift`
- [X] T023 [US1] Add `AppSwitcherIconStripView.swift` to the app target in `SwitchTab.xcodeproj/project.pbxproj`
- [ ] T024 [US1] Validate the App-Level Switching Scenario and App Presentation and Selection Behavior Scenario in `specs/001-macos-switchtab/quickstart.md`

**Checkpoint**: User Story 1 is functional and testable independently.

---

## Archived Phase 4: User Story 2 - Switch Between Windows in the Current Application

**Goal**: Press the current-app window shortcut, see only windows from the active app, and focus the selected window by keyboard confirmation or by clicking its row, icon, or preview.

**Independent Test**: Open several windows in one application, invoke the window switcher while that app is active, click a different window row or preview, and confirm only that app's windows were shown and the selected window becomes focused.

### Tests for User Story 2

- [X] T025 [P] [US2] Create failing window click-confirmation tests in `SwitchTabTests/Services/SwitchTabClickConfirmationTests.swift`
- [X] T026 [P] [US2] Create failing tests that click, Enter, and shortcut confirmation share one selected-window path in `SwitchTabTests/Services/SwitchTabSessionTests.swift`

### Implementation for User Story 2

- [X] T027 [US2] Route clicks on window rows, icons, and previews through the same confirmation path as keyboard confirmation in `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift` and `SwitchTab/UI/Overlay/SwitcherOverlayController.swift`
- [X] T028 [US2] Add `SwitchTabClickConfirmationTests.swift` to the test target in `SwitchTab.xcodeproj/project.pbxproj`
- [ ] T029 [US2] Validate the Current-App Window Switching Scenario click behavior in `specs/001-macos-switchtab/quickstart.md`

**Checkpoint**: User Story 2 remains independently functional with pointer confirmation.

---

## Archived Phase 5: User Story 3 - Configure Switching Shortcuts

**Goal**: Let users configure shortcuts and review permission status without losing valid shortcut settings.

**Independent Test**: Change shortcut settings, confirm obsolete presentation
mode controls are absent, relaunch settings, and confirm saved shortcuts and
permission status persist or refresh correctly.

### Tests for User Story 3

- [X] T030 [P] [US3] Create failing settings view-model tests for shortcut loading, validation, and registration-message text in `SwitchTabTests/Services/ShortcutSettingsStoreTests.swift`
- [X] T031 [P] [US3] Create failing source hygiene tests that presentation preference controls do not return in `SwitchTabTests/Services/OverlaySourceHygieneTests.swift`

### Implementation for User Story 3

- [X] T032 [US3] Keep `ShortcutSettingsViewModel` focused on shortcut loading, saving, permission refresh, and registration messages in `SwitchTab/UI/Settings/ShortcutSettingsViewModel.swift`
- [X] T033 [US3] Keep Settings controls limited to shortcuts and permission status in `SwitchTab/UI/Settings/ShortcutSettingsView.swift`
- [X] T034 [US3] Remove obsolete manual selection and switcher mode controls from `SwitchTab/UI/Settings/ShortcutSettingsView.swift`
- [X] T035 [US3] Refresh hotkey registration after shortcut settings changes in `SwitchTab/AppDelegate.swift`
- [X] T036 [US3] Keep current settings tests included in `SwitchTab.xcodeproj/project.pbxproj`
- [ ] T037 [US3] Validate the Shortcut Settings Scenario and App Presentation and Selection Behavior Scenario in `specs/001-macos-switchtab/quickstart.md`

**Checkpoint**: User Story 3 is independently functional and shortcut settings persist.

---

## Archived Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate performance, permissions, docs, and final quality across all updated behavior.

- [X] T038 [P] Add performance coverage for icon-strip rendering and session creation in `SwitchTabTests/Services/SwitcherPerformanceTests.swift`
- [X] T039 [P] Review permission recovery copy still names the blocked capability and Settings recovery path in `SwitchTab/UI/Permissions/PermissionRecoveryView.swift`
- [X] T040 Run the full automated suite through `SwitchTabTests/TestRunner.swift`
- [ ] T041 Run all manual validation steps in `specs/001-macos-switchtab/quickstart.md`
- [X] T042 Record validation results and any unresolved macOS permission caveats in `specs/001-macos-switchtab/quickstart.md`
- [X] T043 Review `SwitchTab/Services` for continuous polling and update verification notes in `specs/001-macos-switchtab/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup completion and blocks all user stories.
- **Historical User Story 1 (Phase 3)**: Retained for context; app-level
  switching is outside the current checked-in implementation scope.
- **User Story 2 (Phase 4)**: Depends on Foundational completion; can be developed after or alongside US1 because it uses the same overlay confirmation path.
- **User Story 3 (Phase 5)**: Depends on Foundational completion; can be developed alongside US1 after shared preferences exist, then validated end-to-end with US1.
- **Polish (Phase 6)**: Depends on selected user stories being complete.

### User Story Dependencies

- **US1**: Historical app-level switching context, not current checked-in scope.
- **US2**: Independent after Foundation, with shared overlay confirmation behavior.
- **US3**: Independent after Foundation for settings persistence; full value appears when US1 consumes those preferences.

### Within Each User Story

- Write story tests first and confirm they fail.
- Implement model and service behavior before UI wiring.
- Implement UI wiring before manual quickstart validation.
- Complete each story checkpoint before treating it as done.

### Parallel Opportunities

- Setup review tasks T002-T004 can run in parallel.
- Foundational test tasks T005-T006 can run in parallel.
- US1 tests T012-T015 can run in parallel.
- US2 tests T025-T026 can run in parallel.
- US3 tests T030-T031 can run in parallel.
- Polish tasks T038-T039 can run in parallel.

## Parallel Example: User Story 1

```text
Task: "T012 [P] [US1] Create failing app-switch icon-strip presentation tests in SwitchTabTests/Services/AppSwitcherPresentationTests.swift"
Task: "T013 [P] [US1] Create failing app-switch confirmation tests for Enter and shortcut release in SwitchTabTests/Services/AppSwitcherConfirmationTests.swift"
Task: "T014 [P] [US1] Create failing app click-confirmation tests in SwitchTabTests/Services/AppSwitcherClickConfirmationTests.swift"
Task: "T015 [P] [US1] Create failing foreground activation option tests in SwitchTabTests/Services/AppSwitchingServiceTests.swift"
```

## Parallel Example: User Story 2

```text
Task: "T025 [P] [US2] Create failing window click-confirmation tests in SwitchTabTests/Services/SwitchTabClickConfirmationTests.swift"
Task: "T026 [P] [US2] Create failing tests that click, Enter, and shortcut confirmation share one selected-window path in SwitchTabTests/Services/SwitchTabSessionTests.swift"
```

## Parallel Example: User Story 3

```text
Task: "T030 [P] [US3] Create failing settings view-model tests for shortcut loading, validation, and registration-message text in SwitchTabTests/Services/ShortcutSettingsStoreTests.swift"
Task: "T031 [P] [US3] Create failing source hygiene tests that presentation preference controls do not return in SwitchTabTests/Services/OverlaySourceHygieneTests.swift"
```

## Historical Implementation Strategy

### Historical MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: User Story 1.
4. Stop and validate app-level icon-strip switching manually.

This historical strategy is not the current repo cleanup plan.

### Historical Incremental Delivery

1. Deliver US1 icon-strip presentation, release confirmation, click activation, and foreground activation.
2. Add US2 window click-to-confirm behavior.
3. Add US3 shortcut settings and permission status.
4. Run Polish validation across automated and manual checks.

### Historical Quality Gates

- Every automated test task must fail before its implementation task is completed.
- Every implemented story must pass its independent quickstart validation.
- Any unrun validation step must be recorded with risk in final output.

## Archived Summary

- Total tasks: 43
- Setup tasks: 4
- Foundational tasks: 7
- User Story 1 tasks: 13
- User Story 2 tasks: 5
- User Story 3 tasks: 8
- Polish tasks: 6
- Suggested historical MVP scope: Phase 1 + Phase 2 + User Story 1
