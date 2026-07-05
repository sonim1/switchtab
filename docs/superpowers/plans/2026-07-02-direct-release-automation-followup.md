# Direct Release Automation Follow-Up

Scope for the release automation pass:

- Create a dedicated direct distribution app target or generated Xcode project
  variant that links Sparkle 2.
- Add a direct distribution Info.plist with `SUFeedURL`,
  `SUPublicEDKey`, and `SUEnableAutomaticChecks`.
- Generate and store the Sparkle private key outside the repository.
- Archive, Developer ID sign, notarize, zip, sign the update archive, generate
  `appcast.xml`, and upload release assets to Cloudflare R2.
- Verify that the default app target has no Sparkle package product dependency.
