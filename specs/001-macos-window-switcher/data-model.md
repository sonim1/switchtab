# Data Model: macOS Window Switcher

## ShortcutSetting

Represents a configurable keyboard shortcut for one switcher mode.

Fields:
- `id`: Stable identifier for the setting.
- `mode`: `appSwitching` or `currentAppWindowSwitching`.
- `displayName`: User-facing name.
- `keyEquivalent`: Stored key value.
- `modifiers`: Stored modifier keys.
- `isDefault`: Whether the setting matches the default example.
- `isUsable`: Whether the app can register the shortcut.
- `lastValidValue`: Previous usable shortcut for rollback.

Validation rules:
- A shortcut MUST include at least one modifier.
- A shortcut MUST be unique across switcher modes.
- An unusable shortcut MUST NOT replace `lastValidValue`.
- If Cmd+Tab or Cmd+` cannot be registered in the user's environment, the app
  MUST keep or request a usable alternative.

State transitions:
- `valid saved` -> `editing` -> `valid saved`
- `valid saved` -> `editing` -> `rejected` -> `valid saved`
- `default saved` -> `custom saved`

## ApplicationItem

Represents an open application that can appear in app-level switching.

Fields:
- `bundleIdentifier`: Stable app identifier when available.
- `processIdentifier`: Running process identifier.
- `displayName`: Readable app name.
- `icon`: App icon shown in the app switcher.
- `isActive`: Whether this is the frontmost app.
- `isHidden`: Whether the app is hidden.
- `windows`: Known switchable windows for the app.

Validation rules:
- Application items MUST exclude the switcher app itself unless explicitly
  needed for debugging.
- Items without readable names MUST use a safe fallback label.
- Closed apps MUST be removed before activation.

## WindowItem

Represents a switchable window belonging to an application.

Fields:
- `windowIdentifier`: Stable identifier while available.
- `ownerProcessIdentifier`: Owning application process identifier.
- `ownerName`: Readable application name.
- `title`: Window title when available.
- `preview`: Current visual representation when permission allows.
- `isFocused`: Whether the window is currently focused.
- `isMinimized`: Whether the window is minimized when detectable.
- `availability`: `available`, `closed`, `hidden`, `minimized`, `permissionBlocked`,
  or `unknown`.

Validation rules:
- Current-app mode MUST include only windows owned by the active application at
  invocation time.
- A missing title MUST NOT prevent the window from appearing.
- A missing preview due to permission MUST show a permission-aware fallback.
- A closed or unavailable window MUST NOT be focused.

State transitions:
- `available` -> `focused`
- `available` -> `closed`
- `available` -> `minimized`
- `permissionBlocked` -> `available` after permission recovery

## SwitcherMode

Represents the active switching context.

Values:
- `appSwitching`: Lists open applications.
- `currentAppWindowSwitching`: Lists windows from the active app only.

Validation rules:
- Exactly one mode is active while the overlay is visible.
- Canceling a mode MUST dismiss the overlay without changing focus.

## UsageDashboardSnapshot

Represents local usage counts for the About window.

Fields:
- `totalCount`: Total number of app-switching and current-app window-switching
  shortcuts used today.
- `rows`: Fixed rows for app switching and current-app window switching.

Validation rules:
- Usage metrics MUST stay local to UserDefaults.
- Counts MUST be separated by day and switcher mode.
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
- Missing Accessibility permission MUST NOT block app-level activation when
  native AppKit activation can complete it.
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

## PermissionAssistSession

Represents one permission recovery overlay launched from Settings.

Fields:
- `permissionKind`: `accessibility` or `screenRecording`.
- `settingsDestination`: The macOS Settings privacy pane URL or fallback app
  destination to open.
- `instructionText`: Permission-specific drag instruction.
- `appBundleURL`: File URL for the running SwitchTab app bundle.
- `startedAt`: Time the user clicked Allow.
- `state`: `locatingSettings`, `visible`, `fallbackVisible`, `dismissed`, or
  `completed`.

Validation rules:
- A session MUST start only after an explicit user Allow action.
- A session MUST NOT start when the relevant permission is already granted.
- `appBundleURL` MUST point at the current app bundle.
- Only one permission assist session may be visible at a time.
- Completing or dismissing the session MUST trigger a permission-state refresh.

State transitions:
- `locatingSettings` -> `visible` when a reliable System Settings window is found.
- `locatingSettings` -> `fallbackVisible` when lookup times out.
- `visible` -> `completed` after permission refresh reports granted.
- `visible` -> `dismissed` when the user closes the helper.
- `fallbackVisible` -> `dismissed` when the user closes the helper.

## SystemSettingsWindowTarget

Represents the visible Settings window used to position the permission helper.

Fields:
- `ownerName`: Window owner name from CoreGraphics metadata.
- `ownerProcessIdentifier`: Owning process identifier when available.
- `bounds`: Window bounds converted into AppKit global screen coordinates.
- `screenFrame`: Visible frame of the screen containing the window.
- `confidence`: `reliable` or `fallback`.

Validation rules:
- Reliable targets MUST be visible, large enough to be the main Settings window,
  and owned by System Settings/System Preferences.
- Targets MUST NOT depend on private System Settings view hierarchy.
- If no reliable target is found within the bounded lookup window, the app MUST
  use fallback placement instead of blocking.

## PermissionDragItem

Represents the draggable SwitchTab row shown inside the permission helper.

Fields:
- `displayName`: `SwitchTab`.
- `icon`: Current app icon.
- `fileURL`: App bundle file URL written to the drag pasteboard.
- `operation`: Copy operation for the drag session.

Validation rules:
- Drag source MUST use the actual app bundle URL.
- Drag source MUST be initiated by the user's pointer gesture.
- The app MUST NOT synthesize drag movement into System Settings.
