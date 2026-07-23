# UpdateBar Sparkle Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give UpdateBar a strict signed/notarized DMG release, Sparkle 2.9.4 updates at `updates.updatebar.sonim1.com`, protected GitHub release approval, and automatic updates for its three Homebrew packages.

**Architecture:** Keep UpdateBar's independent CLI/TUI builds, replace only the macOS app tarball with one canonical DMG, and add app-owned release scripts for Sparkle/R2/GitHub publication. The app repository publishes a versioned manifest; `homebrew-tap` remains responsible for rendering and testing Formula/Cask files.

**Tech Stack:** Swift 6/SwiftPM, AppKit, Sparkle 2.9.4 at commit `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`, Bash, Apple `codesign`/`notarytool`/`stapler`, Cloudflare R2, Wrangler 4.112.0, GitHub Actions, GitHub CLI.

---

## File Map

- Modify `Package.swift` and `Package.resolved`: add the revision-pinned Sparkle product only to the macOS app target.
- Modify `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`: add the Check for Updates action.
- Modify `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`: place that action in normal/error menus.
- Modify `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`: own `SPUStandardUpdaterController` and route the menu action.
- Modify `Tests/UpdateBarMenuBarTests/MenuBarMenuActionTests.swift` and `MenuBarMenuModelTests.swift`: test the public menu behavior.
- Modify `Scripts/package-app.sh`: embed feed/key metadata, bundle Sparkle.framework, and sign Sparkle helpers inside-out.
- Modify `Scripts/package-app-signing-test.sh`: cover the bundled framework and strict release metadata.
- Create `Scripts/build-app-dmg.sh` and `Scripts/build-app-dmg-test.sh`: create, sign, notarize, staple, and checksum the canonical DMG.
- Create `Scripts/app-dmg-smoke-test.sh`: mount and validate DMG layout without installing it.
- Remove `Scripts/build-app-archive.sh`, `Scripts/build-app-archive-test.sh`, and `Scripts/app-archive-smoke-test.sh` after all callers use the DMG.
- Create root `package.json` and `package-lock.json`; modify `.gitignore`: pin and isolate Wrangler release tooling.
- Create `Scripts/setup-update-hosting.sh` and its contract test: idempotently prepare `updatebar-updates` and `updates.updatebar.sonim1.com`.
- Create `Scripts/generate-appcast.sh` and its contract test: validate/sign a one-item UpdateBar appcast.
- Create `Scripts/publish-update.sh` and its contract test: immutable DMG upload and appcast-last conditional publication.
- Create `Scripts/generate-release-manifest.sh` and its contract test: describe CLI, app, and TUI Homebrew sources.
- Create `Scripts/publish-release.sh` and its contract test: manage the draft GitHub Release, R2 update, and final publication.
- Create `Scripts/dispatch-homebrew-update.sh` and its contract test: notify the tap after publication.
- Rewrite `.github/workflows/release.yml` and extend workflow contracts: verify matrix, protected release job, strict credentials, and tap dispatch.
- Modify `Packaging/homebrew/Casks/updatebar-app.rb` and metadata tests: use the DMG locally until tap automation becomes authoritative.
- Modify `README.md`: document setup, secrets, release, Sparkle, domain migration, and recovery.

The existing untracked design/plan documents in the UpdateBar main worktree are user files and must not be staged, deleted, renamed, or reformatted.

### Task 1: Add the Sparkle runtime and menu action

**Files:**
- Modify: `Package.swift`
- Modify: `Package.resolved`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`
- Modify: `Tests/UpdateBarMenuBarTests/MenuBarMenuActionTests.swift`
- Modify: `Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift`

- [ ] **Step 1: Add failing menu behavior tests**

Add this title assertion and update the expected footer/error-recovery sequences:

```swift
func testCheckForUpdatesUsesSparkleTitle() {
    XCTAssertEqual(MenuBarMenuAction.checkForUpdates.title, "Check for Updates...")
    XCTAssertTrue(MenuBarMenuAction.footer.contains(.checkForUpdates))
    XCTAssertTrue(MenuBarMenuAction.errorRecovery.contains(.checkForUpdates))
}
```

In `MenuBarMenuModelTests`, assert `.menu(.checkForUpdates)` appears after `.viewLogs` and before `.quit` in normal and error menus.

Run: `rtk test swift test --filter MenuBarMenuActionTests`

Expected: compile failure because `.checkForUpdates` is absent.

- [ ] **Step 2: Add the menu action and selector routing**

Add `case checkForUpdates`, title `Check for Updates...`, and include it immediately before `.quit` in both static arrays. Add this AppKit handler:

```swift
@objc private func checkForUpdates() {
    updaterController.checkForUpdates(nil)
}
```

Add `.checkForUpdates: return #selector(checkForUpdates)` to the `MenuBarMenuAction` selector switch.

- [ ] **Step 3: Pin Sparkle and initialize its controller**

Add the dependency and conditional product:

```swift
.package(
    url: "https://github.com/sparkle-project/Sparkle",
    revision: "b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
)
```

```swift
.product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))
```

Inside the existing `#if os(macOS)` block import Sparkle and add:

```swift
private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

Run `rtk swift package resolve`, then verify `Package.resolved` contains the exact revision and version `2.9.4`.

- [ ] **Step 4: Run Swift tests on macOS and Linux-compatible package resolution**

Run: `rtk test swift test`

Expected: all existing and new tests pass.

Run: `rtk swift build -c release --product updatebar-menubar`

Expected: the app executable links against Sparkle with no unresolved symbols.

- [ ] **Step 5: Commit Sparkle app behavior**

```bash
rtk git add Package.swift Package.resolved Sources/UpdateBarMenuBar Sources/UpdateBarMenuBarApp Tests/UpdateBarMenuBarTests
rtk git diff --cached --check
rtk git commit -m "feat: add Sparkle update checks"
```

### Task 2: Bundle and sign Sparkle in the UpdateBar app

**Files:**
- Modify: `Scripts/package-app.sh`
- Modify: `Scripts/package-app-signing-test.sh`

- [ ] **Step 1: Extend the failing packaging contract**

Use fake Swift build output and a fixture `Sparkle.framework`. Assert the packaged app contains `Contents/Frameworks/Sparkle.framework`, the executable resolves Sparkle through `@executable_path/../Frameworks`, and Info.plist contains:

```xml
<key>SUFeedURL</key>
<string>https://updates.updatebar.sonim1.com/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>fixture-public-key</string>
<key>SUEnableAutomaticChecks</key>
<false/>
```

When `UPDATEBAR_SIGN_APP=1`, assert `codesign` order is Sparkle `Autoupdate`, `Updater.app`, both XPC services, `Sparkle.framework`, bundled CLI, main executable, then `UpdateBar.app`. Assert a missing public key, missing framework, or missing identity fails before signing.

Run: `rtk test bash Scripts/package-app-signing-test.sh`

Expected: FAIL because Sparkle metadata/framework handling is absent.

- [ ] **Step 2: Add strict package inputs and framework discovery**

At the top of `package-app.sh` add:

```bash
UPDATEBAR_UPDATE_FEED_URL="${UPDATEBAR_UPDATE_FEED_URL:-https://updates.updatebar.sonim1.com/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
[[ "$UPDATEBAR_UPDATE_FEED_URL" == https://* ]] || { echo "UPDATEBAR_UPDATE_FEED_URL must use HTTPS" >&2; exit 64; }
[[ -n "$SPARKLE_PUBLIC_ED_KEY" ]] || { echo "SPARKLE_PUBLIC_ED_KEY is required" >&2; exit 64; }
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
```

Resolve the binary framework only below `.build/artifacts/sparkle/Sparkle`, require exactly one matching macOS `Sparkle.framework`, copy it with `ditto`, and create `Frameworks` before signing. Add `-Xlinker -rpath -Xlinker @executable_path/../Frameworks` to the menu app build invocation if `otool -L` shows an `@rpath` Sparkle dependency without that executable rpath.

- [ ] **Step 3: Add plist metadata and inside-out signing**

Insert the three Sparkle keys into the generated Info.plist and update `sign_app_if_requested` to sign Sparkle's nested code in the same inside-out order asserted by the test. Use `DEVELOPER_ID_APPLICATION` as the standardized identity, retaining `UPDATEBAR_SIGN_IDENTITY` only as a documented local compatibility alias during this release.

Remove notarization from `package-app.sh`; Task 3 notarizes the final DMG. The app packaging command remains usable unsigned for local development, but the public release workflow always sets `UPDATEBAR_SIGN_APP=1` and fails closed.

- [ ] **Step 4: Run packaging contracts and an unsigned local package build**

```bash
rtk test bash Scripts/package-app-signing-test.sh
rtk env SPARKLE_PUBLIC_ED_KEY=fixture-public-key UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 Scripts/package-app.sh
rtk proxy plutil -lint dist/UpdateBar.app/Contents/Info.plist
```

Expected: contract tests pass, app packaging succeeds, and plist lint is silent.

- [ ] **Step 5: Commit Sparkle packaging**

```bash
rtk git add Scripts/package-app.sh Scripts/package-app-signing-test.sh
rtk git diff --cached --check
rtk git commit -m "build: bundle Sparkle in UpdateBar app"
```

### Task 3: Replace the app tarball with the canonical notarized DMG

**Files:**
- Create: `Scripts/build-app-dmg.sh`
- Create: `Scripts/build-app-dmg-test.sh`
- Create: `Scripts/app-dmg-smoke-test.sh`
- Remove: `Scripts/build-app-archive.sh`
- Remove: `Scripts/build-app-archive-test.sh`
- Remove: `Scripts/app-archive-smoke-test.sh`
- Modify: `Packaging/homebrew/Casks/updatebar-app.rb`
- Modify: `Scripts/homebrew-packaging-test.sh`
- Modify: `Scripts/verify-homebrew-metadata.sh`
- Modify: `Scripts/verify-homebrew-metadata-test.sh`

- [ ] **Step 1: Write failing DMG contracts**

With fake `hdiutil`, `codesign`, `xcrun`, `spctl`, and `shasum`, assert this order:

```text
package signed app
hdiutil create staging directory containing UpdateBar.app and Applications symlink
codesign DMG
codesign verify DMG
notarytool submit DMG --wait
stapler staple DMG
stapler validate DMG
spctl open DMG
spctl exec app
write SHA-256
```

Assert the output is `dist/UpdateBar-<version>-macos-arm64.dmg`, all signing/notary inputs are required, the optional Keychain path is passed safely, and any external failure prevents later calls.

Run: `rtk test bash Scripts/build-app-dmg-test.sh`

Expected: FAIL because the DMG builder is missing.

- [ ] **Step 2: Implement strict DMG production**

Create `Scripts/build-app-dmg.sh` with required inputs:

```bash
required=(SPARKLE_PUBLIC_ED_KEY DEVELOPER_ID_APPLICATION NOTARYTOOL_KEYCHAIN_PROFILE)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || { echo "$name is required" >&2; exit 64; }
done
```

Set `UPDATEBAR_SIGN_APP=1` and invoke `Scripts/package-app.sh`; verify the app signature. Build a temporary staging directory containing `UpdateBar.app` and a symlink named `Applications` to `/Applications`, then create/sign/notarize/staple the versioned DMG. Never overwrite a pre-existing different DMG silently. Write `dist/<name>.sha256` only after all Apple validations pass.

- [ ] **Step 3: Add a real DMG smoke test**

`Scripts/app-dmg-smoke-test.sh <dmg>` mounts read-only with `hdiutil attach -nobrowse -readonly`, traps detach, checks `UpdateBar.app`, the `/Applications` symlink target, executable permissions, bundle identifier/version, Sparkle framework, feed URL, and public key, then detaches.

- [ ] **Step 4: Point local Homebrew metadata at DMG**

Change only the Cask URL suffix to `UpdateBar-#{version}-macos-arm64.dmg`. Preserve the Cask token, app stanza, zap paths, and caveats. Update metadata tests to reject `.app.tar.gz` and require `.dmg`.

- [ ] **Step 5: Remove obsolete app archive scripts and run tests**

```bash
rtk test bash Scripts/build-app-dmg-test.sh
rtk test bash Scripts/homebrew-packaging-test.sh
rtk test bash Scripts/verify-homebrew-metadata-test.sh
rtk proxy bash -n Scripts/build-app-dmg.sh Scripts/build-app-dmg-test.sh Scripts/app-dmg-smoke-test.sh
rtk proxy rg -n "build-app-archive|app[.]tar[.]gz|app-archive-smoke" .github Scripts Packaging README.md
```

Expected: all tests pass and the final search returns no live release references.

- [ ] **Step 6: Commit canonical DMG distribution**

```bash
rtk git add Scripts Packaging/homebrew/Casks/updatebar-app.rb
rtk git diff --cached --check
rtk git commit -m "build: distribute UpdateBar app as notarized DMG"
```

### Task 4: Add pinned Cloudflare and Sparkle publication scripts

**Files:**
- Create: `package.json`
- Create: `package-lock.json`
- Modify: `.gitignore`
- Create: `Scripts/release-tooling-test.sh`
- Create: `Scripts/setup-update-hosting.sh`
- Create: `Scripts/setup-update-hosting-test.sh`
- Create: `Scripts/generate-appcast.sh`
- Create: `Scripts/generate-appcast-test.sh`
- Create: `Scripts/publish-update.sh`
- Create: `Scripts/publish-update-test.sh`

- [ ] **Step 1: Pin Wrangler with a failing tooling contract**

Require a private root package with exact `wrangler: 4.112.0`, a matching lockfile root entry, and ignored root `node_modules/`.

Run: `rtk test bash Scripts/release-tooling-test.sh`

Expected: FAIL before the root package files exist.

- [ ] **Step 2: Add the locked tool package**

```json
{
  "name": "updatebar-release-tools",
  "private": true,
  "devDependencies": {
    "wrangler": "4.112.0"
  }
}
```

Run `rtk npm install --package-lock-only --ignore-scripts`, add `/node_modules/` to `.gitignore`, then run `rtk npm ci --ignore-scripts` and the tooling test.

- [ ] **Step 3: Test and implement idempotent hosting setup**

`Scripts/setup-update-hosting.sh` uses the locked Wrangler CLI to verify identity, create bucket `updatebar-updates` only when absent, and attach `updates.updatebar.sonim1.com` in the provided `CLOUDFLARE_ZONE_ID`. It accepts an existing exact match, rejects conflicts, re-queries final state, and never deletes/replaces a bucket, domain, DNS record, object, or token. The fixture test injects fake Wrangler output for absent, existing, unauthorized, and conflicting states.

- [ ] **Step 4: Test and implement appcast generation**

`Scripts/generate-appcast.sh` consumes the canonical DMG and checksum, verifies codesign/stapling/Gatekeeper, validates `CFBundleShortVersionString`, numeric `CFBundleVersion`, `SUFeedURL`, and `SUPublicEDKey`, then runs the Sparkle 2.9.4 `generate_appcast` found in the pinned SwiftPM artifact. CI supplies `SPARKLE_PRIVATE_ED_KEY` through a permission-0600 temporary file or stdin; it is never an argument, child environment value, or log line. Output is `dist/updates/appcast.xml` plus the versioned DMG/checksum.

The fixture test covers local Keychain mode, CI key mode, public-key mismatch, invalid archive/signature, malformed output, wrong feed, missing signature, and secret non-disclosure.

- [ ] **Step 5: Test and implement R2 publication**

`Scripts/publish-update.sh` requires bucket-scoped S3 credentials and account ID, uploads the immutable versioned DMG/checksum, verifies public bytes, and conditionally updates `appcast.xml` last. It rejects lower versions, different bytes for the same version, immutable-object conflicts, unsafe ETags, reversed completion order, and concurrent writes. A byte-identical rerun is verification-only.

Use these fixed defaults:

```bash
R2_BUCKET_NAME="${R2_BUCKET_NAME:-updatebar-updates}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.updatebar.sonim1.com}"
```

- [ ] **Step 6: Run publication contract suites**

```bash
rtk test bash Scripts/release-tooling-test.sh
rtk test bash Scripts/setup-update-hosting-test.sh
rtk test bash Scripts/generate-appcast-test.sh
rtk test bash Scripts/publish-update-test.sh
rtk proxy bash -n Scripts/setup-update-hosting.sh Scripts/generate-appcast.sh Scripts/publish-update.sh
```

Expected: all fixture suites pass without network access.

- [ ] **Step 7: Commit update hosting**

```bash
rtk git add package.json package-lock.json .gitignore Scripts/release-tooling-test.sh Scripts/setup-update-hosting.sh Scripts/setup-update-hosting-test.sh Scripts/generate-appcast.sh Scripts/generate-appcast-test.sh Scripts/publish-update.sh Scripts/publish-update-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: publish signed Sparkle updates"
```

### Task 5: Generate the multi-package manifest and publish GitHub Releases

**Files:**
- Create: `Scripts/generate-release-manifest.sh`
- Create: `Scripts/generate-release-manifest-test.sh`
- Create: `Scripts/publish-release.sh`
- Create: `Scripts/publish-release-test.sh`
- Create: `Scripts/dispatch-homebrew-update.sh`
- Create: `Scripts/dispatch-homebrew-update-test.sh`

- [ ] **Step 1: Write the manifest contract**

For tag `v0.6.0`, require exactly three packages:

```json
[
  {
    "type": "formula",
    "token": "updatebar",
    "source": {
      "kind": "release-asset",
      "name": "updatebar-0.6.0-macos-arm64.tar.gz",
      "sha256": "<computed CLI SHA>"
    }
  },
  {
    "type": "cask",
    "token": "updatebar-app",
    "source": {
      "kind": "release-asset",
      "name": "UpdateBar-0.6.0-macos-arm64.dmg",
      "sha256": "<computed DMG SHA>"
    }
  },
  {
    "type": "formula",
    "token": "updatebar-tui",
    "source": {
      "kind": "github-tag-archive",
      "sha256": "<downloaded tag archive SHA>"
    }
  }
]
```

The generator validates `version.env`, exact tag/HEAD/origin-main provenance, all local checksums, and a downloaded GitHub tag archive checksum. Tests inject `git`, `curl`, and checksum commands and reject missing/duplicate/wrong-platform assets.

- [ ] **Step 2: Implement deterministic manifest generation**

Write `dist/release-manifest.json` using Ruby `JSON.pretty_generate`. The only
network input is the fixed public URL below, downloaded to a temporary file for
hashing; the manifest contains no URL or path.

```bash
tag_archive_url="https://github.com/sonim1/UpdateBar/archive/refs/tags/$tag.tar.gz"
"${CURL_BIN:-curl}" --fail --location --silent --show-error \
  --output "$temporary_archive" "$tag_archive_url"
```

Ensure the full commit is lowercase 40-character hex and the three packages
appear in the fixed order above.

- [ ] **Step 3: Write and implement GitHub draft publication**

The publisher requires the macOS/Linux CLI archives and checksums, DMG/checksum, appcast, and manifest. It creates/reuses a draft, uploads all immutable assets, rejects any same-name checksum conflict, calls `Scripts/publish-update.sh`, publishes the draft, and returns success for byte-identical reruns. If R2 succeeds but final publication fails, recovery reuses the existing artifacts rather than rebuilding the tag.

Replace the workflow's `softprops/action-gh-release` use; publication behavior must live in this script for local and CI parity.

- [ ] **Step 4: Write and implement tap dispatch**

Use the same typed endpoint contract as SwitchTab but set `SOURCE_REPOSITORY=sonim1/UpdateBar`. Require `TAP_GH_TOKEN`, validate `v<version>`, and send only repository and tag after the GitHub Release is public.

- [ ] **Step 5: Run release contracts**

```bash
rtk test bash Scripts/generate-release-manifest-test.sh
rtk test bash Scripts/publish-release-test.sh
rtk test bash Scripts/dispatch-homebrew-update-test.sh
rtk proxy bash -n Scripts/generate-release-manifest.sh Scripts/publish-release.sh Scripts/dispatch-homebrew-update.sh
```

Expected: all success, retry, conflict, ordering, and failure-propagation cases pass.

- [ ] **Step 6: Commit release coordination**

```bash
rtk git add Scripts/generate-release-manifest.sh Scripts/generate-release-manifest-test.sh Scripts/publish-release.sh Scripts/publish-release-test.sh Scripts/dispatch-homebrew-update.sh Scripts/dispatch-homebrew-update-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: coordinate UpdateBar releases"
```

### Task 6: Replace the release workflow with protected, strict publication

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `Scripts/release-workflow-test.sh`

- [ ] **Step 1: Write the failing workflow contract**

Parse YAML and require:

- `verify` matrix for `macos-15` and pinned Ubuntu, with tests, CLI builds, smoke tests, and uploaded artifacts;
- exact tag/version and `origin/main` provenance with a `release_commit` output;
- `publish` running on `macos-15`, `needs: verify`, `environment: release`, and global UpdateBar release concurrency;
- Apple API-key secret names matching SwitchTab and no Apple-ID/app-password or unsigned fallback strings;
- temporary Keychain cleanup under `if: always()`;
- strict DMG, appcast, manifest, draft release, GitHub App token, and tap dispatch order;
- top-level `contents: read`, job-local `contents: write`; and
- all third-party actions pinned to full reviewed SHAs.

Run: `rtk test bash Scripts/release-workflow-test.sh`

Expected: FAIL against the current optional-signing workflow.

- [ ] **Step 2: Keep the existing cross-platform verification matrix**

Rename the current `build` job to `verify`, preserve CLI tests/build/smoke/checksum steps, and upload only CLI artifacts. Remove app packaging, optional signing, and Homebrew SHA verification from the matrix. Emit the validated tag commit as a job output.

- [ ] **Step 3: Add the protected macOS release job**

Create `publish` with:

```yaml
needs: verify
if: github.event_name == 'push'
environment: release
runs-on: macos-15
permissions:
  contents: write
```

Download CLI artifacts, compare checkout HEAD with the verified commit, install locked Node tooling, create an ephemeral Keychain, import `APPLE_CERTIFICATE_P12_BASE64`, and store App Store Connect API credentials from `APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER_ID`. Missing secrets fail before a public operation.

Run in order:

```bash
Scripts/build-app-dmg.sh
Scripts/app-dmg-smoke-test.sh "$(ls dist/UpdateBar-*-macos-arm64.dmg)"
Scripts/generate-appcast.sh
Scripts/generate-release-manifest.sh "$GITHUB_REF_NAME"
Scripts/publish-release.sh "$GITHUB_REF_NAME"
Scripts/dispatch-homebrew-update.sh "$GITHUB_REF_NAME"
```

Mint the tap token after publication with the same reviewed GitHub App action/configuration as SwitchTab. Cleanup deletes only the validated runner-temporary Keychain/certificate/key paths.

- [ ] **Step 4: Run workflow and quality contracts**

```bash
rtk test bash Scripts/release-workflow-test.sh
rtk test bash Scripts/quality-gate-contract-test.sh
rtk test bash Scripts/script-syntax-test.sh
rtk test swift test
```

Expected: all tests pass; the workflow contains no optional unsigned public-release path.

- [ ] **Step 5: Commit protected automation**

```bash
rtk git add .github/workflows/release.yml Scripts/release-workflow-test.sh
rtk git diff --cached --check
rtk git commit -m "ci: automate protected UpdateBar releases"
```

### Task 7: Document operation and verify the complete implementation

**Files:**
- Modify: `README.md`
- Modify: `Scripts/quality-gate.sh`
- Modify: `Scripts/quality-gate-contract-test.sh`

- [ ] **Step 1: Add release tooling to the quality gate**

Add all new contract tests and Bash syntax checks to `Scripts/quality-gate.sh`. The contract test must assert that every new executable release script is covered and that obsolete app archive scripts are absent.

- [ ] **Step 2: Document one-time and per-release operation**

Document:

- `updatebar-updates` and `updates.updatebar.sonim1.com` setup with locked Wrangler;
- separate UpdateBar Sparkle EdDSA keys despite shared Apple credentials;
- GitHub `release` Environment variables/secrets and required reviewer;
- GitHub App variables/secrets and minimal installation;
- tag → verify → approval → signed DMG/Sparkle/GitHub → tap PR flow;
- partial-release recovery without rebuilding public tags; and
- future `updatebar.app` migration while retaining the old appcast URL for installed versions.

- [ ] **Step 3: Run the full UpdateBar suite**

```bash
rtk test bash Scripts/quality-gate.sh
rtk test swift test
rtk env SPARKLE_PUBLIC_ED_KEY=fixture-public-key UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 Scripts/package-app.sh
rtk proxy plutil -lint dist/UpdateBar.app/Contents/Info.plist
rtk proxy bash -n Scripts/*.sh
rtk git diff --check
rtk git status --short --branch
```

Expected: quality and Swift suites pass, app packaging succeeds, syntax/whitespace checks are silent, and only planned files are modified.

- [ ] **Step 4: Confirm user documents were not included**

Run:

```bash
rtk git status --short docs/superpowers
rtk git diff --cached --name-only
```

Expected: the user's pre-existing untracked documents remain untracked and are absent from every commit.

- [ ] **Step 5: Commit documentation and gate coverage**

```bash
rtk git add README.md Scripts/quality-gate.sh Scripts/quality-gate-contract-test.sh
rtk git diff --cached --check
rtk git commit -m "docs: explain UpdateBar release operation"
```

## Live Configuration Handoff

After all three repositories are merged, run `Scripts/setup-update-hosting.sh` once with local Cloudflare authorization, configure DNS/TLS, add protected Environment secrets, and make one prerelease tag. Approve only after both matrix jobs pass. On a clean Mac verify Gatekeeper, Sparkle update from the previous signed build, the public appcast/DMG checksum, GitHub manifest, all three tap updates, and Homebrew installation before enabling routine production tags.
