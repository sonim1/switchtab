# Feature Specification: macOS SwitchTab

**Feature Branch**: `001-macos-switchtab`

**Created**: 2026-06-17

**Status**: Current implementation scope as of 2026-07-12

**Input**: User description: "macOS에서 키보드 단축키로 (설정가능) MacOS에 열린 앱과 창을 검색하고 빠르게 전환하는 window switcher 앱. 기본 예제로는 Cmd+Tab이면 앱단위로 전환, 앱 아이콘이 보임 CMD+`이면 현재 앱의 window들을 전환 (해당 앱만) 이때 보이는 건 실제 현재 스크린. 이런 심플한 기능해주는 앱"

> Current repository note (2026-07-12): the checked-in app target implements
> current-app window switching only (`SwitcherMode.currentAppWindowSwitching`).
> App-level switching is out of the current implementation scope unless code,
> tests, and docs are updated together in a future feature goal.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch Between Windows in the Current Application (Priority: P1)

As a macOS user working inside one application, I want to press a configurable
shortcut and see only that application's windows so I can jump to the exact
window I need.

**Why this priority**: Current-app window switching is the checked-in app's core
workflow and keeps the product focused on fast keyboard navigation inside the
frontmost application.

**Independent Test**: Open several windows in one application, invoke the window
switcher while that application is active, select a different window, and confirm
that only windows from the active application were shown and the selected window
becomes focused.

**Acceptance Scenarios**:

1. **Given** an application has multiple open windows, **When** the user presses
   the current-app window shortcut, **Then** the overlay shows only windows from
   the currently active application.
2. **Given** the window switcher is visible, **When** the user reviews the list,
   **Then** each window item shows the current screen appearance for that window
   and a readable title when available.
3. **Given** a window item is selected, **When** the user confirms the selection,
   **Then** that window becomes focused without switching to unrelated apps.
4. **Given** the window switcher is visible, **When** the user clicks a visible
   window row, icon, or preview, **Then** that window becomes focused through the
   same confirmation path as keyboard selection.

---

### User Story 2 - Configure Window Switching Shortcut (Priority: P2)

As a macOS user, I want to configure the current-app window shortcut so the
switcher fits my existing keyboard habits.

**Why this priority**: Configurable shortcuts are necessary for users whose
default shortcut is already reserved or uncomfortable.

**Independent Test**: Change the current-app window shortcut, confirm the new
value is saved as the active setting, attempt an invalid shortcut, and confirm
the previous valid shortcut remains active after the failed save.

**Acceptance Scenarios**:

1. **Given** the user opens shortcut settings, **When** they set a new
   current-app window shortcut, **Then** that shortcut is saved as the active
   current-app window shortcut.
2. **Given** a shortcut cannot be used, **When** the user tries to save it,
   **Then** the app explains the problem and keeps the previous working setting.

---

### Edge Cases

- Accessibility permission is missing or revoked.
- The configured shortcut conflicts with a system or application shortcut.
- The active application has only one window or no switchable windows.
- A window has no readable title.
- A selected window closes while the switcher is visible.
- Windows exist on another desktop, space, full-screen workspace, or display.
- A target window is hidden or minimized.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support macOS only.
- **FR-002**: Users MUST be able to invoke a current-app window switcher with a
  configurable keyboard shortcut.
- **FR-003**: The current-app window switcher MUST list only windows belonging
  to the currently active application.
- **FR-004**: The current-app window switcher MUST show each listed window's
  current screen appearance and a readable title when available.
- **FR-005**: Users MUST be able to select a window from the current-app window
  switcher and focus that window.
- **FR-006**: The system MUST provide a default current-app window shortcut and
  users MUST be able to change it.
- **FR-007**: The system MUST prevent unusable shortcut changes from silently
  replacing a working shortcut.
- **FR-008**: The system MUST explain missing or revoked macOS permissions and
  provide a clear recovery path.
- **FR-009**: The switcher overlay MUST be fully usable from the keyboard.
- **FR-010**: The switcher MUST dismiss without changing focus when the user
  cancels the interaction.
- **FR-011**: The switcher MUST handle closed, hidden, minimized, moved, or
  unavailable targets gracefully without crashing or leaving the user stuck.
- **FR-012**: The switcher overlay MUST use a horizontal icon strip with
  readable selected-window context.
- **FR-013**: The switcher overlay MUST default to shortcut-release
  confirmation while keeping explicit keyboard and pointer confirmation
  available.
- **FR-014**: Settings MUST focus on current-app window shortcut configuration,
  app preferences, update controls when available, and permission status,
  without switcher mode or selection-behavior controls.
- **FR-015**: Users MUST be able to focus the selected window by clicking its
  visible row, icon, or preview.

### Key Entities *(include if feature involves data)*

- **Shortcut Setting**: User-configured keyboard shortcut for a switcher mode;
  includes mode, key combination, validity status, and last saved value.
- **Window Item**: A switchable window belonging to an application; includes
  identifiers, owning process, focusability, optional screen-capture identifier,
  and display data for the overlay row.
- **Switcher Mode**: The active switching context: current-app window switching.
- **Permission State**: Current ability to observe and focus windows, including
  missing, granted, and revoked states.
- **Usage Metrics**: Lightweight local counts for today's current-app
  window-switching shortcut use.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can open the current-app window switcher and switch to
  another window in the active application in under 2 seconds after pressing the
  shortcut.
- **SC-002**: With 20 open applications and 50 open windows, keyboard selection
  updates remain responsive without visible lag in normal use.
- **SC-003**: The switcher overlay appears within 200 ms of shortcut invocation
  in normal use.
- **SC-004**: For every missing or revoked permission state, the app shows the
  missing permission name, the blocked capability, and the macOS Settings
  recovery step before the user attempts the blocked action again.
- **SC-005**: During a 10-minute idle period, the app remains unobtrusive and
  does not produce visible UI activity or user-noticeable system slowdown.

## Assumptions

- The app is macOS-only and does not need Windows, Linux, iOS, or web support.
- The initial default shortcut example is current-app window switching with
  Cmd+`, and it is user-configurable.
- If a default shortcut cannot be captured or is reserved in a user's
  environment, the app keeps working after the user chooses another shortcut.
- Current-app window switching is scoped to the application that is active when
  the shortcut is pressed.
- The first release does not manage, tile, resize, or move windows.
- The icon strip is the switcher presentation and is optimized for
  hold-shortcut-and-release behavior.
- App-level switching remains out of scope for the current checked-in target.
