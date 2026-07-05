# Direct Release Automation Follow-Up

Status: partially implemented in `scripts/build-direct-distribution.sh`.

Implemented:

- Create a dedicated direct distribution app target or generated Xcode project
  variant that links Sparkle 2.
- Add a direct distribution Info.plist with `SUFeedURL`,
  `SUPublicEDKey`, and `SUEnableAutomaticChecks`.
- Developer ID sign the direct app, including Sparkle framework, updater app,
  XPC services, and autoupdate helper.
- Create, sign, notarize, staple, and Gatekeeper-check `SwitchTab.dmg`.
- Generate a SHA-256 checksum next to the DMG.
- Verify that the default app target has no Sparkle package product dependency.

Still pending for public release:

- Generate and store the Sparkle private key outside the repository.
- Sign the Sparkle update archive with the private EdDSA key.
- Generate and publish `appcast.xml`.
- Upload release assets to the chosen hosting target for
  `https://updates.switchtab.app/appcast.xml`.
