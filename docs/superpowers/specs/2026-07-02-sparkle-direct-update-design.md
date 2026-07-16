# SwitchTab Direct Update Design

Date: 2026-07-02
Status: Approved direction, implementation plan next

## Goal

Add self-update support for the direct website distribution of SwitchTab. Users
who install from a downloaded DMG should be able to check for updates from the
menu bar or Settings, and optionally allow automatic update checks.

App Store distribution remains separate. The App Store build must not depend on
Sparkle or expose the direct-update UI.

## Non-Goals

- Do not build a custom updater.
- Do not use Sparkle in the Mac App Store build.
- Do not implement Cloudflare deployment automation in this pass.
- Do not silently install updates without giving users normal Sparkle UI.

## Chosen Approach

Use Sparkle 2 for the direct website distribution build only.

Alternatives considered:

- App Store-only updates: simpler for updates, but it does not solve direct DMG
  users and may conflict with current permission-oriented product constraints.
- Custom updater: unnecessary security and maintenance risk.
- Sparkle for all builds: easy to wire once, but risky for App Store review and
  not needed there.

## Distribution Model

Website distribution uses Cloudflare-hosted static assets:

- Landing page and download page: Cloudflare Pages.
- Appcast and release archives: Cloudflare R2 with a custom domain.
- Initial install: user downloads a notarized DMG.
- In-app update: Sparkle reads the appcast and downloads a signed update archive.

Default placeholder URLs:

- Feed: `https://updates.switchtab.app/appcast.xml`
- Download: `https://downloads.switchtab.app/SwitchTab-latest.dmg`

The actual domain can be changed before release.

## App Architecture

Introduce a small update boundary:

- `UpdateChecking` protocol: exposes update availability state, automatic check
  preference, and `checkForUpdates()`.
- `SparkleUpdateController`: direct-distribution adapter backed by Sparkle.
- `UnavailableUpdateController`: fallback used when Sparkle is not compiled in.

`AppDelegate` owns one update controller and wires it to menu and Settings
requests.

Build gating:

- Direct distribution build defines a compile flag such as
  `DIRECT_DISTRIBUTION`.
- Only that build imports Sparkle and embeds Sparkle framework resources.
- Default local/test SwiftPM builds use `UnavailableUpdateController`.

## User Experience

Menu bar:

- Add `Check for Updates...` above `About SwitchTab`.
- The item is enabled only when update checking is available.

Settings:

- Add an `Updates` section under `General`.
- Show current app version.
- Add `Check for Updates...`.
- Add `Automatically check for updates` when Sparkle is available.

When Sparkle is unavailable, Settings should either hide update controls or show
a disabled direct-distribution-only state. For the first implementation, hide
the direct update controls outside the direct distribution build.

## Data Flow

Manual update:

1. User clicks menu bar or Settings update action.
2. UI posts an update-check request notification or calls the injected update
   controller.
3. `AppDelegate` calls Sparkle's user-initiated update check.
4. Sparkle displays standard update UI.

Automatic checks:

1. Direct build reads Sparkle defaults from `Info.plist`.
2. Settings reflects Sparkle's current automatic-check preference.
3. User toggles the setting.
4. The Sparkle updater persists the user preference.

## Info.plist Configuration

Direct distribution builds need:

- `SUFeedURL`
- `SUPublicEDKey`
- `SUEnableAutomaticChecks`

The public EdDSA key is embedded in the app. The private key stays outside the
repository and is used only during release signing.

## Testing

Automated tests:

- Menu bar posts an update-check request.
- Settings view model exposes update controls only when update checking is
  available.
- Settings view model forwards manual checks.
- Automatic-check preference updates through the update controller abstraction.
- Fallback controller reports update checking unavailable.

Manual verification:

- Direct build launches and shows `Check for Updates...`.
- Pressing the menu item opens Sparkle's update check UI.
- Pressing the Settings button opens the same flow.
- Automatic check toggle persists.
- App Store/default build does not expose direct-update UI.

## Release Notes

Release automation will be a separate plan. The expected release path is:

1. Archive direct distribution build.
2. Code sign with Developer ID.
3. Notarize with Apple.
4. Create Sparkle update archive.
5. Sign update archive with Sparkle EdDSA key.
6. Update and publish `appcast.xml`.
7. Upload DMG, archive, and appcast to Cloudflare.

## Deferred Release Decisions

The implementation will use the placeholder update domain and Sparkle `.zip`
update archives. Before public release, replace the placeholder domain and add a
release automation plan for signing, notarization, appcast generation, and
Cloudflare upload.

## Direct Build Contract

The default `SwitchTab` app target remains Sparkle-free. A direct
distribution build must supply three things together:

1. The `DIRECT_DISTRIBUTION` Swift compilation condition.
2. The Sparkle 2 package product linked into the direct app target.
3. `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks` in the direct
   distribution Info.plist.

Do not link Sparkle into the default app target used for App Store-oriented
builds. Use a separate direct distribution target or release automation that
produces a direct-only app bundle.
