# Development

## Requirements

- macOS 14.0 or later
- Swift 6 toolchain or Xcode with Swift 5.10+

## Xcode

Open `SwitchTab.xcodeproj`, select the `SwitchTab` scheme, then use
`Product > Build` or `Product > Test`.

The app sources are laid out for an Xcode macOS menu bar app target. A full
local verification includes an unsigned Debug build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

## Swift Package Manager

Use SwiftPM for fast command-line builds and tests:

```bash
swift build
swift test
```

SwiftPM covers the service and model test suite. Use the Xcode Debug build in
addition when verifying the complete macOS app target.

## Distribution Verification

The checked-in Xcode project remains Sparkle-free. To verify the generated
direct-distribution workspace without building a release:

```bash
SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
```

See [Direct distribution](direct-distribution.md) for production build and
signing requirements.
