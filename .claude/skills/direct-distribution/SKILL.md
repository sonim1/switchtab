---
name: direct-distribution
description: Build SwitchTab's Sparkle-enabled website/DMG distribution via scripts/build-direct-distribution.sh without contaminating the checked-in project. Release builds only on explicit request.
---

# Direct Distribution (SwitchTab)

The checked-in `SwitchTab.xcodeproj` is Sparkle-free (App Store-oriented). The script generates a patched copy (adds Sparkle, `DIRECT_DISTRIBUTION`, `Info.direct.plist`) under `.build/direct-distribution/`.

## Prepare/inspect (allowed)

```bash
SPARKLE_PUBLIC_ED_KEY="<pub-key>" scripts/build-direct-distribution.sh --prepare-only
```

## Build variant

```bash
SPARKLE_PUBLIC_ED_KEY="<pub-key>" \
SWITCHTAB_UPDATE_FEED_URL="https://updates.switchtab.app/appcast.xml" \
scripts/build-direct-distribution.sh
```
`SWITCHTAB_UPDATE_FEED_URL` must be https — the script enforces it.

## Signed/notarized release (EXPLICIT REQUEST ONLY)

```bash
… DEVELOPER_ID_APPLICATION="Developer ID Application: … (TEAMID)" \
NOTARYTOOL_KEYCHAIN_PROFILE="switchtab-notary" \
scripts/build-direct-distribution.sh --release     # DMG + SHA-256
```

Rules: missing keys/identities → ask (never invent); verify post-run that `git status` shows the checked-in project unchanged; report generated artifact paths + checksum.
