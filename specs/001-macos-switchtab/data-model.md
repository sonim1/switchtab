# Data Model: macOS SwitchTab

## ShortcutSetting

Represents a configurable keyboard shortcut for one switcher mode.

Fields:
- `id`: Stable identifier for the setting.
- `mode`: `currentAppWindowSwitching`.
- `displayName`: User-facing name.
- `keyEquivalent`: Stored key value.
- `modifiers`: Stored modifier keys.
- `isDefault`: Whether the setting matches the default example.
- `isUsable`: Whether the app can register the shortcut.
- `lastValidValue`: Previous usable shortcut for rollback.

Validation rules:
- A shortcut MUST include at least one modifier.
- An unusable shortcut MUST NOT replace `lastValidValue`.
- If Cmd+` cannot be registered in the user's environment, the app MUST keep or
  request a usable alternative.

State transitions:
- `valid saved` -> `editing` -> `valid saved`
- `valid saved` -> `editing` -> `rejected` -> `valid saved`
- `default saved` -> `custom saved`

## WindowItem

Represents a switchable window belonging to an application.

Fields:
- `windowIdentifier`: Stable identifier while available.
- `ownerProcessIdentifier`: Owning application process identifier.
- `screenCaptureIdentifier`: Optional ScreenCaptureKit window identifier for
  previews.
- `isMinimized`: Whether the window is minimized when detectable.
- `canFocus`: Whether focus is allowed for the current availability state.
- `switcherListItem`: Display row data used by the overlay.

Initializer inputs:
- `ownerName`: Readable application name for display fallback.
- `title`: Window title when available.
- `availability`: `available`, `minimized`, `hiddenApplication`,
  `fullScreen`, `otherSpace`, `otherDisplay`, `closed`, or `unavailable`.

Validation rules:
- Current-app mode MUST include only windows owned by the active application at
  invocation time.
- A missing title MUST NOT prevent the window from appearing.
- A missing preview due to permission MUST show a permission-aware fallback.
- Closed, unavailable, hidden-application, full-screen, other-space, and
  other-display windows MUST NOT be focused.
- Minimized windows may remain focusable so focusing can restore them first.

State transitions:
- `available` -> `focused`
- `available` -> `closed`
- `available` -> `minimized`
- `permissionBlocked` -> `available` after permission recovery

## SwitcherMode

Represents the active switching context.

Values:
- `currentAppWindowSwitching`: Lists windows from the active app only.

Validation rules:
- Exactly one mode is active while the overlay is visible.
- Canceling a mode MUST dismiss the overlay without changing focus.

## UsageDashboardSnapshot

Represents local usage counts for the About window.

Fields:
- `totalCount`: Total number of current-app window-switching shortcuts used
  today.
- `rows`: Fixed rows for current-app window switching.

Validation rules:
- Usage metrics MUST stay local to UserDefaults.
- Counts MUST be separated by day.
- Dashboard rows MUST use the current registered or saved shortcut labels.

## PermissionState

Represents whether the app can observe, preview, and focus targets.

Fields:
- `accessibility`: `missing` or `granted`.
- `screenRecording`: `missing` or `granted`.
- `permissionStatusItems`: Fixed status rows for Accessibility and Screen
  Recording.

Validation rules:
- Missing Accessibility permission MUST block current-app window observation and
  window focus behavior and show recovery guidance.
- Missing Screen Recording permission MUST block window previews and show a
  preview fallback plus recovery guidance.
- Permission recovery text MUST identify the relevant macOS Settings location.

## SwitcherSession

Represents one visible overlay interaction.

Fields:
- `mode`: Active `SwitcherMode`.
- `items`: Current application or window results.
- `selectedIndex`: Current keyboard selection.

Validation rules:
- Selection MUST stay clamped to available items.
- Empty results MUST dismiss the overlay without changing focus.
- Selection MUST be revalidated before activation or focus.
- Click, Enter, and shortcut-release confirmation MUST all route through the
  same selected-target confirmation path.

## PermissionStatusItem

Represents one permission row in Settings.

Fields:
- `permissionName`: User-facing permission name.
- `isGranted`: Whether macOS reports the permission as granted.
- `detailText`: Granted copy or blocked-capability plus recovery guidance.
- `recoveryActionTitle`: Action title for opening System Settings.
- `settingsDestination`: Privacy pane destination to open.

Validation rules:
- Missing rows MUST name the blocked capability and the System Settings recovery
  step.
- Granted rows MUST show an enabled state and no recovery action.
- Allow actions MUST open System Settings only; the app MUST NOT click, toggle,
  drag, or mutate TCC state on the user's behalf.

## SettingsPermissionSummary

Represents the compact Settings header summary.

Fields:
- `title`: Ready or missing-permission summary.
- `detail`: Short explanation of the missing capability.
- `symbolName`: SF Symbol name for the summary state.
- `isReady`: Whether both Accessibility and Screen Recording are granted.

Validation rules:
- Ready state requires both focus and preview capabilities.
- Missing Accessibility MUST identify focus as blocked.
- Missing Screen Recording MUST identify previews as blocked.
