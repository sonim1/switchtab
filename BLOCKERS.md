# Blockers

## Live macOS permission and focus-flow validation

- Blocked item: End-to-end manual validation of Accessibility permission, Screen Recording permission, real current-app window switching, real window thumbnails, and the System Settings permission-recovery flow.
- Why I cannot resolve it: macOS TCC permissions require direct user approval in System Settings; the app cannot grant or toggle them on the user's behalf. SwitchTab does not toggle or grant permission, alter TCC, install or copy itself, or automate the drag.
- Recovery behavior: Clicking Allow for a missing permission opens the matching macOS Privacy pane, then selects the currently running SwitchTab.app in Finder. Finder is the final foreground app in this recovery flow, and the user must manually drag the selected app into the pane if necessary and grant permission.
- What the user must do: Run SwitchTab, click Allow for Accessibility and Screen Recording, use the currently running app selected in Finder to add or drag it into the matching Privacy pane if necessary, grant permission, and relaunch the app.
- Required user input or decision: Whether the permissions were granted and whether Cmd+` or the configured alternative shortcut can be used in the real environment.
- Next step after resolution: Rerun `swift test` and the Xcode Debug build, then open at least two windows in the current app and verify overlay presentation, selection movement, release-to-confirm focus, and thumbnail display in the real app.
- Why no temporary workaround was used: Modifying the TCC database, automating clicks in System Settings, or faking permission state would bypass the macOS security model without validating the real user flow.

## Signed and notarized release validation

- Blocked item: Real Developer ID signing, notarization, stapling, and Gatekeeper validation with `scripts/build-direct-distribution.sh --release`.
- Why I cannot resolve it: The Apple Developer ID certificate and notarytool keychain profile are tied to the user's account and keychain permissions, so I cannot create or replace them.
- What the user must do: Prepare valid `DEVELOPER_ID_APPLICATION` and `NOTARYTOOL_KEYCHAIN_PROFILE` values and authorize release validation.
- Required user input or decision: The Developer ID certificate name, notarytool keychain profile name, and release artifact output location to use.
- Next step after resolution: Set `SPARKLE_PUBLIC_ED_KEY`, `DEVELOPER_ID_APPLICATION`, and `NOTARYTOOL_KEYCHAIN_PROFILE`, then run `scripts/build-direct-distribution.sh --release` and verify the DMG, checksum, notarization, stapling, and Gatekeeper results.
- Why no temporary workaround was used: Ad hoc signing or a dummy notary profile cannot validate real distribution security.

## Sparkle appcast and update channel publication

- Blocked item: Validation of the Sparkle update archive, signed `appcast.xml`, and hosting/distribution path required for the public automatic-update channel.
- Why I cannot resolve it: This requires an appcast signing key, update-feed hosting permission, and operational decisions about the distribution URL. The current release script automates only DMG and checksum generation.
- What the user must do: Decide how to generate, sign, and host the Sparkle appcast, then prepare the required signing key and update-feed deployment permissions.
- Required user input or decision: The production `SWITCHTAB_UPDATE_FEED_URL`, Sparkle appcast signing-key management approach, update-archive hosting location, and release publication process.
- Next step after resolution: Generate the release artifact, create the Sparkle update archive and signed appcast, and verify that the app can retrieve updates from the HTTPS feed URL.
- Why no temporary workaround was used: An unsigned appcast, temporary HTTP feed, or dummy key cannot validate the automatic-update trust chain and would weaken update security for users.
