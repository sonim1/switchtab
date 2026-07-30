# Direct Distribution

The checked-in Xcode project stays Sparkle-free for App Store-oriented builds.
The direct-distribution script copies the project into an isolated generated
workspace, then adds Sparkle, the `DIRECT_DISTRIBUTION` compilation condition,
and `Info.direct.plist` there. It does not modify `SwitchTab.xcodeproj`.

## Build

Prepare and build the website/DMG distribution variant with:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.royjen.com/appcast.xml" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
scripts/build-direct-distribution.sh
```

`SWITCHTAB_UPDATE_FEED_URL` must use `https://`. Every actual build requires a
trusted Developer ID Application identity so the hardened app can load Sparkle.
Local non-release builds disable the signing timestamp explicitly.

Generated files live under `.build/direct-distribution/`.

## Prepare Without Building

Use `--prepare-only` to generate the patched workspace without a signing
identity or build:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
scripts/build-direct-distribution.sh --prepare-only
```

This is the standard repository verification path for the generated project.

## Signed Release DMG

Use `--release` to produce a signed, notarized, stapled DMG and SHA-256
checksum:

```bash
SPARKLE_PUBLIC_ED_KEY="<public-ed25519-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.royjen.com/appcast.xml" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_KEYCHAIN_PROFILE="switchtab-notary" \
scripts/build-direct-distribution.sh --release
```

Release builds also require an Apple notarytool profile and use a trusted
signing timestamp. Sparkle signing and update publication are separate steps;
see [Update hosting](update-hosting.md).
