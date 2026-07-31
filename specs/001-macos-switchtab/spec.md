# Feature Specification: macOS SwitchTab

**Feature Branch**: `001-macos-switchtab`

**Created**: 2026-06-17

**Status**: Current implementation scope as of 2026-07-31

**Input**: User description: "A window-switcher app that uses a configurable keyboard shortcut to find and quickly switch between open macOS apps and windows. For example, Cmd+Tab switches between apps and displays app icons, while Cmd+` switches between windows in the current app only and shows previews of their current on-screen content. The app should provide this simple functionality."

> Current repository note (2026-07-31): the checked-in app target implements
> current-app window switching and an opt-in application-switching mode
> (`SwitcherMode.applicationSwitching`). The `Replace macOS Cmd-Tab` setting is
> off by default. Native macOS Cmd+Tab remains available while it is disabled,
> when EventTap registration is unavailable, and after SwitchTab exits.

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

### User Story 3 - Opt Into Application Switching (Priority: P1)

As a macOS user, I want to opt in to a SwitchTab application switcher so I can
use one keyboard-first overlay for application changes while retaining native
Cmd+Tab behavior when I do not opt in.

**Why this priority**: Application switching is useful only when it is
explicitly enabled and must not change the existing current-app window flow or
macOS behavior for users who leave the setting off.

**Independent Test**: With Finder, Safari, and Notes open, verify native Cmd+Tab
while replacement is off, enable replacement with Accessibility granted, cycle
forward and reverse through application icons, release Command to activate the
highlighted app, then disable or quit SwitchTab and verify native Cmd+Tab is
restored.

**Acceptance Scenarios**:

1. **Given** replacement is off, **When** the user presses Cmd+Tab, **Then**
   macOS shows its native application switcher and no SwitchTab application
   overlay appears.
2. **Given** replacement is enabled and Accessibility is granted, **When** the
   user presses Cmd+Tab, **Then** a SwitchTab application overlay appears,
   macOS's native switcher is suppressed, and the forward/reverse shortcuts
   cycle application icons and names.
3. **Given** an application is highlighted, **When** the user releases Command,
   **Then** that application becomes frontmost and its stable identifier is
   recorded in application MRU history.
4. **Given** the replacement toggle is disabled or SwitchTab exits, **When** the
   user presses Cmd+Tab, **Then** macOS's native application switcher is
   available again and the current-app window shortcut remains registered.
5. **Given** Accessibility is missing, **When** replacement is enabled, **Then**
   the setting remains saved, the EventTap is not active, native Cmd+Tab is not
   consumed, and Settings shows application-specific recovery guidance.
6. **Given** application switching is active, **When** the user views the
   overlay, **Then** every application icon is shown, only the selected app
   shows its name and a window count of two or more, no window thumbnails or
   close controls appear, and Screen Recording is not required.

The exact Finder/Safari/Notes manual checks and evidence filenames are the
eight scenarios in the [quickstart acceptance contract](quickstart.md#application-switching-manual-acceptance-contract).

---

### Edge Cases

- Accessibility permission is missing or revoked.
- The configured shortcut conflicts with a system or application shortcut.
- The active application has only one window or no switchable windows.
- A window has no readable title.
- A selected window closes while the switcher is visible.
- Windows exist on another desktop, space, full-screen workspace, or display.
- A target window is hidden or minimized.
- Application replacement is enabled without Accessibility permission.
- The application EventTap fails to register or only partially registers.
- The replacement toggle changes while an application overlay is visible.
- SwitchTab exits or crashes while replacement is enabled.

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
  the explicit opt-in application replacement toggle, app preferences, update
  controls when available, and permission status, without arbitrary switcher
  mode or selection-behavior controls.
- **FR-015**: Users MUST be able to focus the selected window by clicking its
  visible row, icon, or preview.
- **FR-016**: Settings MUST expose a `Replace macOS Cmd-Tab` application
  replacement toggle that defaults to off and persists independently of the
  current-app window shortcut.
- **FR-017**: When replacement is enabled and Accessibility is granted, the
  system MUST register a dedicated suppressing EventTap for Cmd+Tab and
  Cmd+Shift+Tab, while leaving the configurable window shortcut registration
  independent.
- **FR-018**: When replacement is disabled, EventTap registration fails, or
  SwitchTab exits, the system MUST leave or restore native macOS Cmd+Tab
  behavior. A failed or partial registration MUST NOT consume Cmd+Tab.
- **FR-019**: Application switching MUST order applications with an MRU history
  stored separately from window MRU history and MUST record history only after
  successful activation.
- **FR-020**: Application-mode rows MUST show every application icon, reserve a
  stable caption height, and show the name only for the selected app. The
  selected caption MUST show a standard-window count only when it is two or
  more. Window thumbnails and close controls MUST remain hidden, and Screen
  Recording permission MUST NOT be required for application icons or names.
- **FR-021**: Accessibility guidance MUST identify the EventTap requirement for
  application replacement while preserving the existing Accessibility and
  Screen Recording recovery behavior for current-app windows and previews.

### Key Entities *(include if feature involves data)*

- **Shortcut Setting**: User-configured keyboard shortcut for a switcher mode;
  includes mode, key combination, validity status, and last saved value.
- **Window Item**: A switchable window belonging to an application; includes
  identifiers, owning process, focusability, optional screen-capture identifier,
  and display data for the overlay row.
- **Application Item**: A running regular application with a stable bundle or
  process-scoped identifier, process identifier, display name, active state,
  and icon data for the application overlay.
- **Switcher Mode**: The active switching context: current-app window switching
  or opt-in application switching.
- **Application MRU**: Mode-scoped application recency persisted separately
  from the current-app window history; entries are written after successful
  activation and workspace activation.
- **Permission State**: Current ability to observe and focus windows, including
  missing, granted, and revoked states. Accessibility also controls whether the
  application replacement EventTap can intercept Cmd+Tab; Screen Recording
  controls only current-app window previews.
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
- **SC-006**: With replacement disabled, unavailable, or after SwitchTab exits,
  a Cmd+Tab press reaches the native macOS switcher without a SwitchTab
  application overlay.
- **SC-007**: With replacement enabled and Accessibility granted, a Cmd+Tab or
  Cmd+Shift+Tab cycle presents the SwitchTab application overlay and activates
  the highlighted application on Command release within 2 seconds.
- **SC-008**: Application icons and names remain available without Screen
  Recording permission, while current-app window previews continue to follow
  the existing Screen Recording permission path.

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
- Application switching is opt-in and defaults off so native macOS Cmd+Tab
  remains the default behavior.
- Application MRU is SwitchTab-owned and stored separately from window MRU; it
  does not attempt to reproduce undocumented Dock ordering.
- Accessibility is required for the application EventTap and current-app window
  observation/focus. Screen Recording is required only for current-app window
  previews, not application icons or names.
- The exact Finder/Safari/Notes application-switching checks are documented in
  the quickstart and must be recorded in
  `.build/qa/application-switching/outcomes.md` with the required evidence
  fields before a manual QA sign-off.
