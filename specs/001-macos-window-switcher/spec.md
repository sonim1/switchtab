# Feature Specification: macOS Window Switcher

**Feature Branch**: `001-macos-window-switcher`

**Created**: 2026-06-17

**Status**: Draft

**Input**: User description: "macOS에서 키보드 단축키로 (설정가능) MacOS에 열린 앱과 창을 검색하고 빠르게 전환하는 window switcher 앱. 기본 예제로는 Cmd+Tab이면 앱단위로 전환, 앱 아이콘이 보임 CMD+`이면 현재 앱의 window들을 전환 (해당 앱만) 이때 보이는 건 실제 현재 스크린. 이런 심플한 기능해주는 앱"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch Between Open Applications (Priority: P1)

As a macOS user, I want to press a configurable shortcut and see the open
applications so I can switch to another app without leaving the keyboard.

**Why this priority**: App-level switching is the core workflow and provides a
minimal useful product by itself.

**Independent Test**: Open at least three applications, invoke the app switcher,
filter or navigate to a different application, select it, and confirm that
application becomes active.

**Acceptance Scenarios**:

1. **Given** multiple applications are open, **When** the user presses the
   app-switch shortcut, **Then** an overlay appears showing one item per open
   application with the application icon and name.
2. **Given** the app switcher is visible, **When** the user types part of an
   application name, **Then** the list narrows to matching applications.
3. **Given** a matching application is selected, **When** the user confirms the
   selection, **Then** the selected application becomes active.
4. **Given** the app switcher is visible, **When** the user clicks an
   application row or icon, **Then** the selected application becomes active.
5. **Given** the user has selected icon-strip presentation, **When** they invoke
   app switching, **Then** the overlay shows a compact horizontal app-icon strip
   and commits the selected app when the shortcut is released.

---

### User Story 2 - Switch Between Windows in the Current Application (Priority: P2)

As a macOS user working inside one application, I want to press a configurable
shortcut and see only that application's windows so I can jump to the exact
window I need.

**Why this priority**: Window-level switching is the second core workflow and
keeps the app focused on fast keyboard navigation.

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

---

### User Story 3 - Configure Switching Shortcuts (Priority: P3)

As a macOS user, I want to configure the app-level and current-app window
shortcuts so the switcher fits my existing keyboard habits.

**Why this priority**: Configurable shortcuts are necessary for users whose
default shortcuts are already reserved or uncomfortable, but the first two
switching flows can be validated with default examples.

**Independent Test**: Change both shortcut settings, confirm the new values are
saved as the active settings, attempt an invalid shortcut, and confirm the
previous valid shortcut remains active after the failed save.

**Acceptance Scenarios**:

1. **Given** the user opens shortcut settings, **When** they set a new app-level
   shortcut, **Then** that shortcut is saved as the active app-switch shortcut.
2. **Given** the user opens shortcut settings, **When** they set a new
   current-app window shortcut, **Then** that shortcut is saved as the active
   current-app window shortcut.
3. **Given** a shortcut cannot be used, **When** the user tries to save it,
   **Then** the app explains the problem and keeps the previous working setting.

---

### Edge Cases

- Accessibility permission is missing or revoked.
- The configured shortcut conflicts with a system or application shortcut.
- No other applications are available to switch to.
- The active application has only one window or no switchable windows.
- A window has no readable title.
- Search text matches no applications or windows.
- A selected application or window closes while the switcher is visible.
- Windows exist on another desktop, space, full-screen workspace, or display.
- A target app is hidden or minimized.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support macOS only.
- **FR-002**: Users MUST be able to invoke an app-level switcher with a
  configurable keyboard shortcut.
- **FR-003**: The app-level switcher MUST show one item per open application,
  including the application icon and readable name.
- **FR-004**: Users MUST be able to filter app-level switcher results by typing
  part of an application name.
- **FR-005**: Users MUST be able to select an application from the app-level
  switcher and make it active.
- **FR-006**: Users MUST be able to invoke a current-app window switcher with a
  configurable keyboard shortcut.
- **FR-007**: The current-app window switcher MUST list only windows belonging
  to the currently active application.
- **FR-008**: The current-app window switcher MUST show each listed window's
  current screen appearance and a readable title when available.
- **FR-009**: Users MUST be able to filter current-app window results by typing
  part of a window title or owning application name.
- **FR-010**: Users MUST be able to select a window from the current-app window
  switcher and focus that window.
- **FR-011**: The system MUST provide default example shortcuts for app-level
  switching and current-app window switching, and users MUST be able to change
  both shortcuts.
- **FR-012**: The system MUST prevent unusable shortcut changes from silently
  replacing a working shortcut.
- **FR-013**: The system MUST explain missing or revoked macOS permissions and
  provide a clear recovery path.
- **FR-014**: The switcher overlay MUST be fully usable from the keyboard.
- **FR-015**: The switcher MUST dismiss without changing focus when the user
  cancels the interaction.
- **FR-016**: The switcher MUST handle closed, hidden, minimized, moved, or
  unavailable targets gracefully without crashing or leaving the user stuck.
- **FR-017**: The app switcher overlay MUST use a horizontal icon strip with
  readable selected-app context.
- **FR-018**: The switcher overlay MUST default to shortcut-release
  confirmation while keeping explicit keyboard and pointer confirmation
  available.
- **FR-019**: Settings MUST focus on shortcut configuration and permission
  status, without presentation-mode controls.
- **FR-020**: Users MUST be able to activate the selected app or window by
  clicking its visible row, icon, or preview.
- **FR-021**: App activation MUST bring the selected application to the
  foreground when macOS allows it.

### Key Entities *(include if feature involves data)*

- **Shortcut Setting**: User-configured keyboard shortcut for a switcher mode;
  includes mode, key combination, validity status, and last saved value.
- **Application Item**: A switchable open application; includes display name,
  icon, active status, and available windows.
- **Window Item**: A switchable window belonging to an application; includes
  title, current visual representation, owning application, and availability.
- **Switcher Mode**: The active switching context: app-level switching or
  current-app window switching.
- **Permission State**: Current ability to observe and focus windows, including
  missing, granted, and revoked states.
- **Usage Metrics**: Lightweight local counts for today's app-switching and
  current-app window-switching shortcut use.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can open the app-level switcher and switch to another open
  application in under 2 seconds after pressing the shortcut.
- **SC-002**: Users can open the current-app window switcher and switch to
  another window in the active application in under 2 seconds after pressing the
  shortcut.
- **SC-003**: With 20 open applications and 50 open windows, keyboard selection
  updates remain responsive without visible lag in normal use.
- **SC-004**: The switcher overlay appears within 200 ms of shortcut invocation
  in normal use.
- **SC-005**: For every missing or revoked permission state, the app shows the
  missing permission name, the blocked capability, and the macOS Settings
  recovery step before the user attempts the blocked action again.
- **SC-006**: During a 10-minute idle period, the app remains unobtrusive and
  does not produce visible UI activity or user-noticeable system slowdown.

## Assumptions

- The app is macOS-only and does not need Windows, Linux, iOS, or web support.
- The initial default shortcut examples are app-level switching with Cmd+Tab and
  current-app window switching with Cmd+`, but both are user-configurable.
- If a default shortcut cannot be captured or is reserved in a user's
  environment, the app keeps working after the user chooses another shortcut.
- App-level switching activates the most recently used switchable window for the
  selected application.
- Current-app window switching is scoped to the application that is active when
  the shortcut is pressed.
- The first release does not manage, tile, resize, or move windows.
- The icon strip is the app-switcher presentation and is optimized for
  hold-shortcut-and-release behavior.
