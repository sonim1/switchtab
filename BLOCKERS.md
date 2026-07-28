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

- Blocked item: Live Developer ID signing, notarization, stapling, and Gatekeeper validation with the automated local or GitHub release path.
- Why I cannot resolve it: The Apple Developer ID certificate and notarytool keychain profile are tied to the user's account and keychain permissions, so I cannot create or replace them.
- What the user must do: Prepare a valid `DEVELOPER_ID_APPLICATION` identity and either a local `NOTARYTOOL_KEYCHAIN_PROFILE` or the documented GitHub Apple credential secrets, then authorize live release validation. CI creates and supplies `NOTARYTOOL_KEYCHAIN_PATH` automatically; it is not a repository credential.
- Required user input or decision: Which approved Developer ID certificate and Apple notary credentials to use, and permission to perform the live signing/notarization operation.
- Next step after resolution: Run `scripts/release-local.sh` locally or push an approved protected version tag, then verify the DMG signature, checksum, notarization, stapling, and Gatekeeper results.
- Why no temporary workaround was used: Ad hoc signing or a dummy notary profile cannot validate real distribution security.

## Xcode `SwitchTabTests` scheme fails to compile (pre-existing)

- Blocked item: Running the Xcode-side `SwitchTabTests` scheme. It fails to build with `error: call to main actor-isolated initializer 'init(processIdentifier:isActive:bundleIdentifier:bundleURL:)' in a synchronous nonisolated context` at `SwitchTabTests/Services/PermissionRecoveryCopyTests.swift:892` and `:897`.
- Why it is out of scope here: Verified stash-proof — the same failure reproduces on a clean `HEAD` worktree with no local changes, so it predates the current work and is unrelated to it. The Xcode test target applies stricter actor-isolation inference than the SwiftPM target, which compiles the same file cleanly.
- Current gate: `swift test` (the supported SwiftPM gate) passes, and the Xcode Debug build of the `SwitchTab` app scheme succeeds.
- What the user must decide: Whether to fix the isolation annotations in `PermissionRecoveryCopyTests` (for example by making the affected helpers `@MainActor`) so the Xcode test scheme builds again.
- Next step after resolution: Rerun the `SwitchTabTests` scheme in Xcode alongside `swift test`.

## Live Sparkle update-channel validation

- Blocked item: Credential-backed validation of the implemented Sparkle appcast, Cloudflare R2 hosting, and GitHub tag-release automation against the live services.
- Why I cannot resolve it: The scripts and workflow now exist, but live validation requires the user's Sparkle private key, scoped Cloudflare and R2 credentials, GitHub repository access, and explicit approval for external mutations.
- What the user must do: Register the documented repository variables and secrets, approve the one-time hosting mutation, and approve an actual protected release tag.
- Required user input or decision: Permission to create or validate `switchtab` and `updates.switchtab.royjen.com`, publish immutable release objects and the mutable appcast, and publish the matching GitHub release.
- Next step after resolution: Run `scripts/setup-update-hosting.sh` once, push an approved `v<MARKETING_VERSION>` tag, then verify the public DMG checksum, `https://updates.switchtab.royjen.com/appcast.xml`, the GitHub release assets, and an in-app Sparkle update check.
- Why no temporary workaround was used: An unsigned appcast, temporary HTTP feed, or dummy key cannot validate the automatic-update trust chain and would weaken update security for users.
