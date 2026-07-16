# SwitchTab

Native macOS window switcher prototype for fast keyboard-first current-app window switching.

## Requirements

- macOS 14.0 or later
- Swift 6 toolchain or Xcode with Swift 5.10+

## Build and Test

Open `SwitchTab.xcodeproj` in Xcode, select the `SwitchTab` scheme, then use `Product > Build` or `Product > Test`.

SwitchTab leaves macOS Cmd+Tab app switching untouched. The app focuses on current-app window switching with Cmd+` by default, falling back to Option+Ctrl+` when macOS refuses the reserved shortcut.

This workspace can be tested with Swift Package Manager:

```bash
swift build
swift test
```

## Direct Distribution Build

The default Xcode project stays Sparkle-free for App Store-oriented builds. To
prepare or build the website/DMG distribution variant, use:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.app/appcast.xml" \
scripts/build-direct-distribution.sh
```

`SWITCHTAB_UPDATE_FEED_URL` must use `https://`.

Use `--prepare-only` to generate the patched workspace without building:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" scripts/build-direct-distribution.sh --prepare-only
```

Use `--release` to produce a signed, notarized, stapled DMG and SHA-256
checksum:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.app/appcast.xml" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_KEYCHAIN_PROFILE="switchtab-notary" \
scripts/build-direct-distribution.sh --release
```

Generated files live under `.build/direct-distribution/`. The generated project
adds Sparkle, `DIRECT_DISTRIBUTION`, and `Info.direct.plist`; the checked-in
`SwitchTab.xcodeproj` remains unchanged.

The app sources are laid out for an Xcode macOS menu bar app target at
`SwitchTab.xcodeproj`. Automated verification should include the SwiftPM build,
the SwiftPM test suite, and an Xcode Debug app build when full Xcode is
selected.
