<p align="center">
  <img src="SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" alt="SwitchTab app icon" width="128" />
</p>

<h1 align="center">SwitchTab</h1>

<p align="center">
  <strong>A free, open-source macOS app and window switcher with keyboard shortcuts and window previews.</strong>
</p>

<p align="center">
  <a href="https://switchtab.royjen.com/">Website</a> ·
  <a href="https://github.com/sonim1/switchtab/releases/latest">Download</a> ·
  <a href="#installation">Installation</a>
</p>

---

## Installation

Requires **macOS 14 or later**. No Xcode or Swift toolchain is needed to use the app.

With [Homebrew](https://brew.sh/):

```bash
brew install --cask sonim1/tap/switchtab
```

Or [download the latest signed and notarized DMG](https://github.com/sonim1/switchtab/releases/latest),
open it, and drag SwitchTab to Applications. Open SwitchTab and grant Accessibility
permission for switching. Screen Recording is optional and enables window previews.

[See SwitchTab in action](https://switchtab.royjen.com/#how-it-works) or read
[how to switch between apps and windows on Mac](https://switchtab.royjen.com/guides/switch-windows-on-mac/).

### Install with AI

Copy this prompt into a coding agent with **local terminal access** on your Mac.
Chat-only tools cannot install apps. You still approve macOS permissions yourself.
[Open the plain-text prompt](https://switchtab.royjen.com/install-with-ai.txt).

```text
Install SwitchTab on this Mac using local terminal access. If you cannot run local commands, say so instead of claiming installation succeeded.

1. Confirm macOS 14 or later and Apple silicon hardware (including when the terminal runs under Rosetta). Stop and explain if this Mac is unsupported.
2. Read the official README at https://github.com/sonim1/switchtab and resolve the current stable release at https://github.com/sonim1/switchtab/releases/latest. Use only the official sonim1/switchtab release or sonim1/tap Homebrew cask.
3. Check for an existing SwitchTab installation first. Report its version and ask before updating or replacing it. Preserve its settings.
4. If Homebrew is already available, run: brew install --cask sonim1/tap/switchtab
Do not install Homebrew, Xcode, or a Swift toolchain just for this app.
5. Without Homebrew, download the stable DMG and its matching .dmg.sha256 file from that same official release into a temporary directory. Verify SHA-256 before mounting read-only. Verify the app's Developer ID signature and notarization with codesign and spctl, and confirm bundle ID com.royjen.switchtab. Stop if any check fails. Copy it to /Applications only if no installation exists; if access is denied, ask me to drag the verified app there. Eject only the image you mounted.
6. Verify the installed app's version, bundle ID, signature, and notarization, then open it. Report whether its process is running. Do not claim switching works until I complete the permission and shortcut check.
7. Ask me to approve Accessibility in System Settings > Privacy & Security > Accessibility, then test my switching shortcut. Screen Recording is optional for window previews. Never grant permissions automatically.
8. Do not use sudo, remove quarantine, disable Gatekeeper, change security settings, or request passwords in chat. Report the installed version, path, verification results, and any remaining manual steps.
```

## What SwitchTab Does

SwitchTab provides two focused switching modes:

- Press <kbd>Command</kbd>+<kbd>`</kbd> to move between windows in the current
  application, with live previews when Screen Recording permission is available.
- Press <kbd>Command</kbd>+<kbd>Tab</kbd> to move between applications with
  compact icons and a caption for the selected app.

Both shortcuts can be enabled, disabled, and changed independently in
Settings > Shortcut. If macOS refuses the reserved current-window default,
SwitchTab falls back to
<kbd>Option</kbd>+<kbd>Control</kbd>+<kbd>`</kbd>.

Fresh installations enable both switching modes by default. Existing
installations preserve an explicit previous application-switcher choice; when
no previous choice can be detected, application switching remains disabled.
When enabled, <kbd>Command</kbd>+<kbd>Tab</kbd> moves forward,
<kbd>Command</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> moves backward, and releasing
Command activates the selected app. Turning the setting off or quitting
SwitchTab restores the native switcher.

Only the selected application shows its name. When Accessibility reports two or
more standard windows for that app, the caption also shows the window count.
Arrow keys move through the same selection grid, and
<kbd>Command</kbd>+<kbd>Q</kbd> asks the selected app to quit normally while the
switcher stays open; the tile disappears only after that app exits.

Accessibility permission is required for window focus and application
switching. Screen Recording is required only for window previews, not for
application icons or names. If Cmd-Tab interception is unavailable, SwitchTab
keeps the setting saved, shows recovery guidance, and leaves native Cmd-Tab
working.

## Free Forever

SwitchTab is free, and it stays free. There are no ads, no in-app purchases, no
subscription, and no paid Pro tier — every feature is available to everyone,
with nothing held back behind a paywall.

The app bundles no advertising SDK and has no third-party runtime dependency
other than Sparkle, which is present only in the direct-distribution build so it
can deliver updates.

## Requirements

- macOS 14.0 or later
- To build from source: Swift 6 toolchain or Xcode with Swift 5.10+

## Quick Start

Open `SwitchTab.xcodeproj` in Xcode, select the `SwitchTab` scheme, then use
`Product > Build` or `Product > Test`.

For command-line development:

```bash
swift build
swift test
```

## Documentation

- [Landing page](https://switchtab.royjen.com/) ([source](docs/index.html)) — an interactive visual introduction to the app and window switching workflow
- [Changelog](CHANGELOG.md) — user-facing changes grouped by release
- [Development](docs/development.md) — local setup, build, test, and verification
- [AI context and verification](docs/AI_CONTEXT.md) — current architecture, invariants, and compact macOS QA guidance
- [Project history](docs/PROJECT_HISTORY.md) — task-selective decisions, rationale, changed requirements, and release evidence
- [Direct distribution](docs/direct-distribution.md) — generated Sparkle workspace and signed DMG builds
- [Update hosting](docs/update-hosting.md) — Cloudflare R2, Sparkle publishing, and local fallback operations
- [Release workflow](docs/release-workflow.md) — versioning, GitHub releases, Homebrew integration, and recovery
- [Repository maintenance](docs/repository-maintenance.md) — dependency, security, and verification state

## License

SwitchTab is available under the [MIT License](LICENSE.md).
