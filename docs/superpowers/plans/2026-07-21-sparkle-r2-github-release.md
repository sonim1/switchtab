# Sparkle R2 GitHub Release Automation Implementation Plan

> **Historical plan — superseded by the implemented release pipeline.** Do not
> copy credential lists or workflow snippets from this file. Use `README.md`,
> `.github/workflows/release.yml`, and the executable contract tests as the
> current operator and implementation sources of truth. Current publication
> uses bucket-scoped R2 S3 credentials and conditional ETag writes; CI does not
> receive `CLOUDFLARE_API_TOKEN`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a pushed `v<MARKETING_VERSION>` tag produce a tested, Developer ID-signed, notarized SwitchTab DMG, a signed Sparkle appcast on Cloudflare R2, and a matching GitHub Release.

**Architecture:** Keep release behavior in small Bash scripts and let one GitHub Actions workflow inject ephemeral credentials and call them. Use immutable versioned DMGs, publish the appcast last, create GitHub Releases as drafts until R2 succeeds, and use fixture executables so tests never touch Apple, Cloudflare, GitHub, Keychain, DNS, or the public network.

**Tech Stack:** Bash 3.2-compatible scripts, SwiftPM/Xcode, Sparkle 2.9.4 CLI from the pinned Swift package artifact, Wrangler 4.112.0, Cloudflare R2, GitHub CLI, GitHub Actions on `macos-15`.

---

## File Map

- Create `package.json`: declares the exact Wrangler development dependency.
- Create `package-lock.json`: locks Wrangler and its transitive dependencies.
- Modify `.gitignore`: ignores local `node_modules/`.
- Modify `.env.release.local.example`: documents public local release and hosting configuration.
- Create `scripts/generate-appcast.sh`: validates the notarized artifact and generates a signed appcast.
- Create `scripts/setup-update-hosting.sh`: idempotently creates the R2 bucket and connects the custom domain.
- Create `scripts/publish-update.sh`: uploads immutable update files and replaces the appcast last.
- Create `scripts/publish-release.sh`: validates the tag, manages a GitHub draft release, calls R2 publishing, then publishes the release.
- Modify `scripts/build-direct-distribution.sh`: accepts an optional Keychain path for CI notarization credentials.
- Create `.github/workflows/release.yml`: installs ephemeral Apple credentials and orchestrates the scripts.
- Create one contract test per new script under `scripts/tests/` plus a workflow contract test.
- Modify `README.md`: documents one-time setup, local publishing, GitHub secrets/variables, and tag releases.

The existing dirty changes in `SwitchTab/SwitchTabApp.swift` and
`SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift` are outside
this plan and must not be staged, reverted, or reformatted.

### Task 1: Pin the Wrangler release toolchain

**Files:**
- Create: `package.json`
- Create: `package-lock.json`
- Modify: `.gitignore`
- Create: `scripts/tests/release-tooling-test.sh`

- [ ] **Step 1: Write the failing tooling contract test**

Create `scripts/tests/release-tooling-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

node - "$PROJECT_ROOT/package.json" "$PROJECT_ROOT/package-lock.json" <<'NODE'
const fs = require("fs");
const packageJson = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const lock = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));

if (packageJson.private !== true) throw new Error("package must be private");
if (packageJson.devDependencies?.wrangler !== "4.112.0") {
  throw new Error("wrangler must be pinned to 4.112.0");
}
if (lock.packages?.[""]?.devDependencies?.wrangler !== "4.112.0") {
  throw new Error("package-lock root must pin wrangler 4.112.0");
}
NODE

git -C "$PROJECT_ROOT" check-ignore -q node_modules || fail "node_modules is not ignored"

echo "release tooling contract tests passed"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `rtk test bash scripts/tests/release-tooling-test.sh`

Expected: FAIL because `package.json` and `package-lock.json` do not exist.

- [ ] **Step 3: Add the exact package manifest and ignore rule**

Create `package.json`:

```json
{
  "name": "switchtab-release-tools",
  "private": true,
  "devDependencies": {
    "wrangler": "4.112.0"
  }
}
```

Append this section to `.gitignore`:

```gitignore
# Node-based release tooling
node_modules/
```

Generate, rather than hand-writing, the lockfile:

Run: `rtk npm install --package-lock-only --ignore-scripts`

Expected: `package-lock.json` records Wrangler 4.112.0.

- [ ] **Step 4: Install and verify the locked CLI**

Run: `rtk npm ci --ignore-scripts`

Expected: dependencies install without modifying `package-lock.json`.

Run: `rtk npx wrangler --version`

Expected: output contains `4.112.0`.

Run: `rtk test bash scripts/tests/release-tooling-test.sh`

Expected: `release tooling contract tests passed`.

- [ ] **Step 5: Commit the toolchain pin**

```bash
rtk git add package.json package-lock.json .gitignore scripts/tests/release-tooling-test.sh
rtk git diff --cached --check
rtk git commit -m "build: pin Wrangler release tooling"
```

### Task 2: Generate and validate the signed Sparkle appcast

**Files:**
- Create: `scripts/generate-appcast.sh`
- Create: `scripts/tests/generate-appcast-test.sh`
- Modify: `.env.release.local.example`

- [ ] **Step 1: Write the failing appcast contract test**

Create `scripts/tests/generate-appcast-test.sh`. The fixture copies the script
into a temporary project, supplies fake Apple commands, and uses the real
`shasum` and `xmllint` for integrity checks:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/generate-appcast.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected '$2' in: $1"; }

[[ -x "$SCRIPT" ]] || fail "scripts/generate-appcast.sh is missing or not executable"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-appcast.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
FIXTURE="$TEMP_ROOT/project"
BUILD="$FIXTURE/.build/direct-distribution"
APP="$BUILD/DerivedData/Build/Products/Release/SwitchTab.app"
RELEASE="$BUILD/release"
FAKE_BIN="$TEMP_ROOT/bin"
LOG="$TEMP_ROOT/commands.log"
mkdir -p "$FIXTURE/scripts" "$APP/Contents" "$RELEASE" "$FAKE_BIN"
cp "$SCRIPT" "$FIXTURE/scripts/generate-appcast.sh"
printf 'dmg-bytes' > "$RELEASE/SwitchTab.dmg"
(cd "$RELEASE" && shasum -a 256 SwitchTab.dmg > SwitchTab.dmg.sha256)
printf 'plist' > "$APP/Contents/Info.plist"

cat > "$FAKE_BIN/success" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COMMAND_LOG"
EOF

cat > "$FAKE_BIN/plutil" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *CFBundleShortVersionString*) printf '1.2\n' ;;
  *CFBundleVersion*) printf '7\n' ;;
  *SUPublicEDKey*) printf 'public-key\n' ;;
  *) exit 1 ;;
esac
EOF

cat > "$FAKE_BIN/generate_appcast" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COMMAND_LOG"
if [[ "$*" == *"--ed-key-file -"* ]]; then
  IFS= read -r private_key
  [[ "$private_key" == "private-key" ]] || exit 42
fi
output=''
directory="${!#}"
signature='signature'
[[ -z "${EMPTY_SIGNATURE:-}" ]] || signature=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then output="$2"; shift 2; else shift; fi
done
cat > "$output" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><item><enclosure url="https://updates.switchtab.app/SwitchTab-1.2-7.dmg" sparkle:version="7" sparkle:shortVersionString="1.2" sparkle:edSignature="$signature" /></item></channel>
</rss>
XML
EOF
chmod +x "$FAKE_BIN"/*

cat > "$FIXTURE/.env.release.local" <<'EOF'
SPARKLE_PUBLIC_ED_KEY='public-key'
SPARKLE_KEY_ACCOUNT='ed25519'
UPDATE_DOMAIN='updates.switchtab.app'
EOF

run_script() {
  set +e
  output="$(
    COMMAND_LOG="$LOG" \
    CODESIGN_BIN="$FAKE_BIN/success" \
    XCRUN_BIN="$FAKE_BIN/success" \
    SPCTL_BIN="$FAKE_BIN/success" \
    PLUTIL_BIN="$FAKE_BIN/plutil" \
    SPARKLE_APPCAST_BIN="$FAKE_BIN/generate_appcast" \
    EMPTY_SIGNATURE="${EMPTY_SIGNATURE:-}" \
    "$FIXTURE/scripts/generate-appcast.sh" "$@" 2>&1
  )"
  status=$?
  set -e
}

run_script
[[ "$status" -eq 0 ]] || fail "local generation failed: $output"
UPDATE_DIR="$BUILD/updates"
[[ -f "$UPDATE_DIR/SwitchTab-1.2-7.dmg" ]] || fail "versioned DMG missing"
[[ -f "$UPDATE_DIR/SwitchTab-1.2-7.dmg.sha256" ]] || fail "checksum missing"
xmllint --noout "$UPDATE_DIR/appcast.xml"
assert_contains "$(cat "$LOG")" "--account ed25519"

: > "$LOG"
SPARKLE_PRIVATE_ED_KEY='private-key' run_script
[[ "$status" -eq 0 ]] || fail "CI generation failed: $output"
assert_contains "$(cat "$LOG")" "--ed-key-file -"

EMPTY_SIGNATURE=1 run_script
[[ "$status" -ne 0 ]] || fail "missing EdDSA signature was accepted"
assert_contains "$output" "Missing Sparkle EdDSA signature"

printf 'changed' >> "$RELEASE/SwitchTab.dmg"
run_script
[[ "$status" -ne 0 ]] || fail "bad checksum was accepted"
assert_contains "$output" "checksum"

run_script unexpected
[[ "$status" -eq 64 ]] || fail "unexpected arguments must return 64"

bash -n "$SCRIPT"
echo "generate-appcast contract tests passed"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `rtk test bash scripts/tests/generate-appcast-test.sh`

Expected: FAIL with `scripts/generate-appcast.sh is missing`.

- [ ] **Step 3: Implement the minimal appcast generator**

Create `scripts/generate-appcast.sh` with these exact interfaces and checks:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${RELEASE_CONFIG_PATH:-$PROJECT_ROOT/.env.release.local}"
[[ ! -f "$CONFIG_PATH" ]] || { set -a; source "$CONFIG_PATH"; set +a; }

if [[ $# -ne 0 ]]; then
    echo "Usage: scripts/generate-appcast.sh" >&2
    exit 64
fi

BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
RELEASE_DIR="${DIRECT_RELEASE_OUTPUT_DIR:-$BUILD_ROOT/release}"
UPDATE_DIR="${UPDATE_OUTPUT_DIR:-$BUILD_ROOT/updates}"
APP_PATH="${DIRECT_APP_PATH:-$BUILD_ROOT/DerivedData/Build/Products/Release/SwitchTab.app}"
DMG_PATH="$RELEASE_DIR/SwitchTab.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.app}"
UPDATE_BASE_URL="https://$UPDATE_DOMAIN"

CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
XCRUN_BIN="${XCRUN_BIN:-/usr/bin/xcrun}"
SPCTL_BIN="${SPCTL_BIN:-/usr/sbin/spctl}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
SPARKLE_APPCAST_BIN="${SPARKLE_APPCAST_BIN:-$BUILD_ROOT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast}"

require_value() {
    [[ -n "$2" ]] || { echo "$1 is required" >&2; exit 64; }
}
require_file() {
    [[ -f "$2" ]] || { echo "Missing $2" >&2; exit 66; }
}

require_value SPARKLE_PUBLIC_ED_KEY "${SPARKLE_PUBLIC_ED_KEY:-}"
require_file DMG "$DMG_PATH"
require_file checksum "$CHECKSUM_PATH"
require_file Info.plist "$INFO_PLIST"
[[ -x "$SPARKLE_APPCAST_BIN" ]] || { echo "Missing executable $SPARKLE_APPCAST_BIN" >&2; exit 66; }

if ! (cd "$RELEASE_DIR" && "$SHASUM_BIN" -a 256 -c "$(basename "$CHECKSUM_PATH")" >/dev/null); then
    echo "DMG checksum validation failed" >&2
    exit 1
fi
"$CODESIGN_BIN" --verify --verbose=2 "$DMG_PATH"
"$XCRUN_BIN" stapler validate "$DMG_PATH"
"$SPCTL_BIN" -a -vv -t open --context context:primary-signature "$DMG_PATH"

marketing_version="$("$PLUTIL_BIN" -extract CFBundleShortVersionString raw "$INFO_PLIST")"
build_number="$("$PLUTIL_BIN" -extract CFBundleVersion raw "$INFO_PLIST")"
embedded_key="$("$PLUTIL_BIN" -extract SUPublicEDKey raw "$INFO_PLIST")"
[[ "$embedded_key" == "$SPARKLE_PUBLIC_ED_KEY" ]] || { echo "Sparkle public key mismatch" >&2; exit 1; }
[[ "$marketing_version" =~ ^[0-9A-Za-z._-]+$ ]] || { echo "Unsafe marketing version" >&2; exit 64; }
[[ "$build_number" =~ ^[0-9A-Za-z._-]+$ ]] || { echo "Unsafe build number" >&2; exit 64; }

archive_name="SwitchTab-$marketing_version-$build_number.dmg"
mkdir -p "$BUILD_ROOT" "$UPDATE_DIR"
temp_dir="$(mktemp -d "$BUILD_ROOT/appcast.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
cp "$DMG_PATH" "$temp_dir/$archive_name"
archive_hash="$("$SHASUM_BIN" -a 256 "$temp_dir/$archive_name" | awk '{print $1}')"
printf '%s  %s\n' "$archive_hash" "$archive_name" > "$temp_dir/$archive_name.sha256"

appcast_args=(--download-url-prefix "$UPDATE_BASE_URL/" -o "$temp_dir/appcast.xml")
if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
    printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_APPCAST_BIN" --ed-key-file - "${appcast_args[@]}" "$temp_dir"
else
    "$SPARKLE_APPCAST_BIN" --account "$SPARKLE_KEY_ACCOUNT" "${appcast_args[@]}" "$temp_dir"
fi

"$XMLLINT_BIN" --noout "$temp_dir/appcast.xml"
enclosure_url="$("$XMLLINT_BIN" --xpath 'string(//*[local-name()="enclosure"]/@url)' "$temp_dir/appcast.xml")"
signature="$("$XMLLINT_BIN" --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$temp_dir/appcast.xml")"
[[ "$enclosure_url" == "$UPDATE_BASE_URL/$archive_name" ]] || { echo "Unexpected appcast enclosure URL" >&2; exit 1; }
[[ -n "$signature" ]] || { echo "Missing Sparkle EdDSA signature" >&2; exit 1; }

cp "$temp_dir/$archive_name" "$UPDATE_DIR/$archive_name"
cp "$temp_dir/$archive_name.sha256" "$UPDATE_DIR/$archive_name.sha256"
cp "$temp_dir/appcast.xml" "$UPDATE_DIR/appcast.xml"
echo "Generated signed appcast: $UPDATE_DIR/appcast.xml"
```

Run: `rtk proxy chmod +x scripts/generate-appcast.sh`

Expected: the repository records the script as executable when staged.

- [ ] **Step 4: Document local appcast configuration**

Append to `.env.release.local.example`:

```bash
SPARKLE_KEY_ACCOUNT='ed25519'
R2_BUCKET_NAME='switchtab-updates'
UPDATE_DOMAIN='updates.switchtab.app'
CLOUDFLARE_ACCOUNT_ID='your-cloudflare-account-id'
CLOUDFLARE_ZONE_ID='your-cloudflare-zone-id'
```

Do not add a Sparkle private key to this file; local signing uses Keychain.

- [ ] **Step 5: Run the appcast tests**

Run: `rtk test bash scripts/tests/generate-appcast-test.sh`

Expected: `generate-appcast contract tests passed`.

Run: `rtk proxy bash -n scripts/generate-appcast.sh scripts/tests/generate-appcast-test.sh`

Expected: no output and exit 0.

- [ ] **Step 6: Commit the appcast generator**

```bash
rtk git add scripts/generate-appcast.sh scripts/tests/generate-appcast-test.sh .env.release.local.example
rtk git diff --cached --check
rtk git commit -m "feat: generate signed Sparkle appcasts"
```

### Task 3: Create idempotent Cloudflare R2 hosting setup

**Files:**
- Create: `scripts/setup-update-hosting.sh`
- Create: `scripts/tests/setup-update-hosting-test.sh`

- [ ] **Step 1: Write the failing hosting setup contract test**

Create `scripts/tests/setup-update-hosting-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/setup-update-hosting.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
[[ -x "$SCRIPT" ]] || fail "setup script missing"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-hosting.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
FIXTURE="$TEMP_ROOT/project"
STATE="$TEMP_ROOT/state"
LOG="$TEMP_ROOT/wrangler.log"
mkdir -p "$FIXTURE/scripts" "$TEMP_ROOT/bin" "$STATE"
cp "$SCRIPT" "$FIXTURE/scripts/setup-update-hosting.sh"

cat > "$TEMP_ROOT/bin/wrangler" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WRANGLER_LOG"
case "$*" in
  whoami) exit "${WHOAMI_STATUS:-0}" ;;
  "r2 bucket info switchtab-updates --json") [[ -f "$WRANGLER_STATE/bucket" ]] ;;
  "r2 bucket create switchtab-updates") touch "$WRANGLER_STATE/bucket" ;;
  "r2 bucket domain get switchtab-updates --domain updates.switchtab.app") [[ -f "$WRANGLER_STATE/domain" ]] ;;
  "r2 bucket domain add switchtab-updates --domain updates.switchtab.app --zone-id zone-123 --min-tls 1.2 --force") touch "$WRANGLER_STATE/domain" ;;
  *) exit 41 ;;
esac
EOF
chmod +x "$TEMP_ROOT/bin/wrangler"

cat > "$FIXTURE/.env.release.local" <<'EOF'
R2_BUCKET_NAME='switchtab-updates'
UPDATE_DOMAIN='updates.switchtab.app'
CLOUDFLARE_ZONE_ID='zone-123'
EOF

run_setup() {
  set +e
  output="$(WRANGLER_BIN="$TEMP_ROOT/bin/wrangler" WRANGLER_LOG="$LOG" WRANGLER_STATE="$STATE" "$FIXTURE/scripts/setup-update-hosting.sh" 2>&1)"
  status=$?
  set -e
}

run_setup
[[ "$status" -eq 0 ]] || fail "first setup failed: $output"
[[ "$(grep -c 'bucket create' "$LOG")" -eq 1 ]] || fail "bucket not created once"
[[ "$(grep -c 'domain add' "$LOG")" -eq 1 ]] || fail "domain not added once"

run_setup
[[ "$status" -eq 0 ]] || fail "second setup failed: $output"
[[ "$(grep -c 'bucket create' "$LOG")" -eq 1 ]] || fail "bucket was recreated"
[[ "$(grep -c 'domain add' "$LOG")" -eq 1 ]] || fail "domain was re-added"

WHOAMI_STATUS=9 run_setup
[[ "$status" -eq 9 ]] || fail "authentication failure was not propagated"

rm "$FIXTURE/.env.release.local"
run_setup
[[ "$status" -eq 64 ]] || fail "missing zone ID must return 64"

bash -n "$SCRIPT"
echo "setup-update-hosting contract tests passed"
```

- [ ] **Step 2: Run the setup test and verify it fails**

Run: `rtk test bash scripts/tests/setup-update-hosting-test.sh`

Expected: FAIL with `setup script missing`.

- [ ] **Step 3: Implement the hosting setup script**

Create `scripts/setup-update-hosting.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${RELEASE_CONFIG_PATH:-$PROJECT_ROOT/.env.release.local}"
[[ ! -f "$CONFIG_PATH" ]] || { set -a; source "$CONFIG_PATH"; set +a; }

if [[ $# -ne 0 ]]; then
    echo "Usage: scripts/setup-update-hosting.sh" >&2
    exit 64
fi

R2_BUCKET_NAME="${R2_BUCKET_NAME:-switchtab-updates}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.app}"
WRANGLER_BIN="${WRANGLER_BIN:-$PROJECT_ROOT/node_modules/.bin/wrangler}"
[[ -n "${CLOUDFLARE_ZONE_ID:-}" ]] || { echo "CLOUDFLARE_ZONE_ID is required" >&2; exit 64; }
[[ -x "$WRANGLER_BIN" ]] || { echo "Missing Wrangler; run npm ci" >&2; exit 66; }

"$WRANGLER_BIN" whoami
if ! "$WRANGLER_BIN" r2 bucket info "$R2_BUCKET_NAME" --json >/dev/null; then
    "$WRANGLER_BIN" r2 bucket create "$R2_BUCKET_NAME"
fi
"$WRANGLER_BIN" r2 bucket info "$R2_BUCKET_NAME" --json >/dev/null

if ! "$WRANGLER_BIN" r2 bucket domain get "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN" >/dev/null; then
    "$WRANGLER_BIN" r2 bucket domain add "$R2_BUCKET_NAME" \
        --domain "$UPDATE_DOMAIN" \
        --zone-id "$CLOUDFLARE_ZONE_ID" \
        --min-tls 1.2 \
        --force
fi
"$WRANGLER_BIN" r2 bucket domain get "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN"
echo "Update hosting ready: https://$UPDATE_DOMAIN/appcast.xml"
```

Run: `rtk proxy chmod +x scripts/setup-update-hosting.sh`

Expected: the repository records the script as executable when staged.

- [ ] **Step 4: Run the hosting setup tests**

Run: `rtk test bash scripts/tests/setup-update-hosting-test.sh`

Expected: `setup-update-hosting contract tests passed`.

- [ ] **Step 5: Commit the hosting setup**

```bash
rtk git add scripts/setup-update-hosting.sh scripts/tests/setup-update-hosting-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: automate R2 update hosting setup"
```

### Task 4: Publish immutable update artifacts and appcast to R2

**Files:**
- Create: `scripts/publish-update.sh`
- Create: `scripts/tests/publish-update-test.sh`

- [ ] **Step 1: Write the failing R2 publishing test**

Create `scripts/tests/publish-update-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/publish-update.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
[[ -x "$SCRIPT" ]] || fail "publish-update script missing"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish-update.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
FIXTURE="$TEMP_ROOT/project"
UPDATE_DIR="$FIXTURE/.build/direct-distribution/updates"
PUBLIC_DIR="$TEMP_ROOT/public"
FAKE_BIN="$TEMP_ROOT/bin"
WRANGLER_LOG="$TEMP_ROOT/wrangler.log"
ORDER_LOG="$TEMP_ROOT/order.log"
mkdir -p "$FIXTURE/scripts" "$UPDATE_DIR" "$PUBLIC_DIR" "$FAKE_BIN"
cp "$SCRIPT" "$FIXTURE/scripts/publish-update.sh"
printf 'release-dmg' > "$UPDATE_DIR/SwitchTab-1.2-7.dmg"
hash="$(shasum -a 256 "$UPDATE_DIR/SwitchTab-1.2-7.dmg" | awk '{print $1}')"
printf '%s  %s\n' "$hash" SwitchTab-1.2-7.dmg > "$UPDATE_DIR/SwitchTab-1.2-7.dmg.sha256"
cat > "$UPDATE_DIR/appcast.xml" <<'XML'
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><item><enclosure url="https://updates.switchtab.app/SwitchTab-1.2-7.dmg" sparkle:version="7" sparkle:shortVersionString="1.2" sparkle:edSignature="signature" /></item></channel>
</rss>
XML

cat > "$FAKE_BIN/wrangler" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WRANGLER_LOG"
[[ "$1 $2 $3" == "r2 object put" ]] || exit 40
object_path="$4"
shift 4
file=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$file" ]] || exit 41
name="${object_path#*/}"
cp "$file" "$PUBLIC_DIR/$name"
printf 'put %s\n' "$name" >> "$ORDER_LOG"
EOF

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
output=''
url="${!#}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
name="${url##*/}"
printf 'get %s\n' "$name" >> "$ORDER_LOG"
if [[ -f "$PUBLIC_DIR/$name" ]]; then
  cp "$PUBLIC_DIR/$name" "$output"
  printf '200'
else
  : > "$output"
  printf '404'
fi
EOF
chmod +x "$FAKE_BIN"/*

assert_before() {
  local first second first_line second_line
  first="$1"; second="$2"
  first_line="$(grep -nFx "$first" "$ORDER_LOG" | head -1 | cut -d: -f1)"
  second_line="$(grep -nFx "$second" "$ORDER_LOG" | head -1 | cut -d: -f1)"
  [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] || fail "$first was not before $second"
}

run_publish() {
  set +e
  output="$(
    WRANGLER_BIN="$FAKE_BIN/wrangler" \
    CURL_BIN="$FAKE_BIN/curl" \
    WRANGLER_LOG="$WRANGLER_LOG" \
    ORDER_LOG="$ORDER_LOG" \
    PUBLIC_DIR="$PUBLIC_DIR" \
    "$FIXTURE/scripts/publish-update.sh" 2>&1
  )"
  status=$?
  set -e
}

run_publish
[[ "$status" -eq 0 ]] || fail "publish failed: $output"
assert_before "put SwitchTab-1.2-7.dmg" "put SwitchTab-1.2-7.dmg.sha256"
assert_before "put SwitchTab-1.2-7.dmg.sha256" "put appcast.xml"
grep -Fq -- '--content-type application/x-apple-diskimage' "$WRANGLER_LOG" || fail "DMG MIME type missing"
grep -Fq -- '--cache-control public, max-age=31536000, immutable' "$WRANGLER_LOG" || fail "immutable cache policy missing"
grep -Fq -- '--content-type application/xml' "$WRANGLER_LOG" || fail "appcast MIME type missing"

run_publish
[[ "$status" -eq 0 ]] || fail "idempotent publish failed: $output"
[[ "$(grep -c '^put SwitchTab-1.2-7.dmg$' "$ORDER_LOG")" -eq 1 ]] || fail "identical DMG was re-uploaded"

printf 'conflict' > "$PUBLIC_DIR/SwitchTab-1.2-7.dmg"
run_publish
[[ "$status" -ne 0 ]] || fail "remote checksum conflict was accepted"
[[ "$output" == *"checksum conflict"* ]] || fail "conflict error was unclear: $output"

bash -n "$SCRIPT"
echo "publish-update contract tests passed"
```

- [ ] **Step 2: Run the publishing test and verify it fails**

Run: `rtk test bash scripts/tests/publish-update-test.sh`

Expected: FAIL because `scripts/publish-update.sh` is missing.

- [ ] **Step 3: Implement the R2 publisher**

Create `scripts/publish-update.sh` with the following functions and call order:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${RELEASE_CONFIG_PATH:-$PROJECT_ROOT/.env.release.local}"
[[ ! -f "$CONFIG_PATH" ]] || { set -a; source "$CONFIG_PATH"; set +a; }

if [[ $# -ne 0 ]]; then echo "Usage: scripts/publish-update.sh" >&2; exit 64; fi
BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
UPDATE_DIR="${UPDATE_OUTPUT_DIR:-$BUILD_ROOT/updates}"
R2_BUCKET_NAME="${R2_BUCKET_NAME:-switchtab-updates}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.app}"
WRANGLER_BIN="${WRANGLER_BIN:-$PROJECT_ROOT/node_modules/.bin/wrangler}"
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
APPCAST="$UPDATE_DIR/appcast.xml"

[[ -x "$WRANGLER_BIN" ]] || { echo "Missing Wrangler; run npm ci" >&2; exit 66; }
[[ -f "$APPCAST" ]] || { echo "Missing $APPCAST" >&2; exit 66; }
"$XMLLINT_BIN" --noout "$APPCAST"
url="$("$XMLLINT_BIN" --xpath 'string(//*[local-name()="enclosure"]/@url)' "$APPCAST")"
prefix="https://$UPDATE_DOMAIN/"
[[ "$url" == "$prefix"* ]] || { echo "Appcast enclosure is outside $prefix" >&2; exit 64; }
archive_name="${url#"$prefix"}"
[[ "$archive_name" != */* && "$archive_name" == SwitchTab-*.dmg ]] || { echo "Unsafe archive name" >&2; exit 64; }
DMG="$UPDATE_DIR/$archive_name"
CHECKSUM="$DMG.sha256"
[[ -f "$DMG" && -f "$CHECKSUM" ]] || { echo "Missing update artifact" >&2; exit 66; }
expected_hash="$(awk 'NR == 1 {print $1}' "$CHECKSUM")"
actual_hash="$("$SHASUM_BIN" -a 256 "$DMG" | awk '{print $1}')"
[[ "$expected_hash" == "$actual_hash" ]] || { echo "Local checksum mismatch" >&2; exit 1; }

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT

fetch_status() {
    local public_url="$1" output_path="$2" code status
    set +e
    code="$("$CURL_BIN" --silent --show-error --location --output "$output_path" --write-out '%{http_code}' "$public_url")"
    status=$?
    set -e
    [[ "$status" -eq 0 ]] || { echo "Could not reach $public_url" >&2; return "$status"; }
    printf '%s' "$code"
}

upload() {
    local name="$1" file="$2" type="$3" cache="$4"
    "$WRANGLER_BIN" r2 object put "$R2_BUCKET_NAME/$name" --remote --file "$file" \
        --content-type "$type" --cache-control "$cache"
}

remote_dmg="$temp_dir/$archive_name"
code="$(fetch_status "$prefix$archive_name" "$remote_dmg")"
if [[ "$code" == 200 ]]; then
    remote_hash="$("$SHASUM_BIN" -a 256 "$remote_dmg" | awk '{print $1}')"
    [[ "$remote_hash" == "$expected_hash" ]] || { echo "Remote immutable DMG checksum conflict" >&2; exit 1; }
elif [[ "$code" == 404 ]]; then
    upload "$archive_name" "$DMG" application/x-apple-diskimage 'public, max-age=31536000, immutable'
else
    echo "Unexpected HTTP $code for $prefix$archive_name" >&2; exit 1
fi

code="$(fetch_status "$prefix$archive_name" "$remote_dmg")"
[[ "$code" == 200 ]] || { echo "Published DMG is not public" >&2; exit 1; }
remote_hash="$("$SHASUM_BIN" -a 256 "$remote_dmg" | awk '{print $1}')"
[[ "$remote_hash" == "$expected_hash" ]] || { echo "Published DMG checksum mismatch" >&2; exit 1; }

upload "$archive_name.sha256" "$CHECKSUM" text/plain 'public, max-age=31536000, immutable'
checksum_copy="$temp_dir/$archive_name.sha256"
[[ "$(fetch_status "$prefix$archive_name.sha256" "$checksum_copy")" == 200 ]] || { echo "Published checksum is not public" >&2; exit 1; }
[[ "$(awk 'NR == 1 {print $1}' "$checksum_copy")" == "$expected_hash" ]] || { echo "Published checksum content mismatch" >&2; exit 1; }

upload appcast.xml "$APPCAST" application/xml 'public, max-age=60'
public_appcast="$temp_dir/appcast.xml"
[[ "$(fetch_status "${prefix}appcast.xml" "$public_appcast")" == 200 ]] || { echo "Published appcast is not public" >&2; exit 1; }
"$XMLLINT_BIN" --noout "$public_appcast"
public_url="$("$XMLLINT_BIN" --xpath 'string(//*[local-name()="enclosure"]/@url)' "$public_appcast")"
[[ "$public_url" == "$url" ]] || { echo "Published appcast enclosure mismatch" >&2; exit 1; }
echo "Published update: ${prefix}appcast.xml"
```

Run: `rtk proxy chmod +x scripts/publish-update.sh`

Expected: the repository records the script as executable when staged.

- [ ] **Step 4: Run the R2 publishing tests**

Run: `rtk test bash scripts/tests/publish-update-test.sh`

Expected: `publish-update contract tests passed`.

- [ ] **Step 5: Commit the R2 publisher**

```bash
rtk git add scripts/publish-update.sh scripts/tests/publish-update-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: publish Sparkle updates to R2"
```

### Task 5: Publish a matching GitHub Release

**Files:**
- Create: `scripts/publish-release.sh`
- Create: `scripts/tests/publish-release-test.sh`

- [ ] **Step 1: Write the failing GitHub Release contract test**

Create `scripts/tests/publish-release-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/publish-release.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
[[ -x "$SCRIPT" ]] || fail "publish-release script missing"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish-release.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
FIXTURE="$TEMP_ROOT/project"
UPDATE_DIR="$FIXTURE/.build/direct-distribution/updates"
FAKE_BIN="$TEMP_ROOT/bin"
GH_STATE="$TEMP_ROOT/gh-state"
GH_ASSETS="$TEMP_ROOT/gh-assets"
ORDER_LOG="$TEMP_ROOT/order.log"
mkdir -p "$FIXTURE/scripts" "$UPDATE_DIR" "$FAKE_BIN" "$GH_ASSETS"
cp "$SCRIPT" "$FIXTURE/scripts/publish-release.sh"
printf 'release-dmg' > "$UPDATE_DIR/SwitchTab-1.2-7.dmg"
shasum -a 256 "$UPDATE_DIR/SwitchTab-1.2-7.dmg" > "$UPDATE_DIR/SwitchTab-1.2-7.dmg.sha256"
cat > "$UPDATE_DIR/appcast.xml" <<'XML'
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><item><enclosure url="https://updates.switchtab.app/SwitchTab-1.2-7.dmg" sparkle:version="7" sparkle:shortVersionString="1.2" sparkle:edSignature="signature" /></item></channel>
</rss>
XML

cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse HEAD") printf 'commit-1\n' ;;
  "rev-parse v1.2^{commit}") printf 'commit-1\n' ;;
  "merge-base --is-ancestor commit-1 origin/main") exit 0 ;;
  *) exit 44 ;;
esac
EOF

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ORDER_LOG"
if [[ "$*" == "release view v1.2 --json isDraft --jq .isDraft" ]]; then
  [[ -f "$GH_STATE" ]] || exit 1
  [[ "$(cat "$GH_STATE")" == draft ]] && printf 'true\n' || printf 'false\n'
elif [[ "$*" == "release view v1.2 --json assets --jq .assets[].name" ]]; then
  [[ -f "$GH_STATE" ]] || exit 1
  for path in "$GH_ASSETS"/*; do [[ ! -e "$path" ]] || basename "$path"; done
elif [[ "$1 $2 $3" == "release create v1.2" ]]; then
  printf 'draft' > "$GH_STATE"
elif [[ "$1 $2 $3" == "release upload v1.2" ]]; then
  cp "$4" "$GH_ASSETS/$(basename "$4")"
elif [[ "$1 $2 $3" == "release download v1.2" ]]; then
  pattern=''; directory=''
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pattern) pattern="$2"; shift 2 ;;
      --dir) directory="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  cp "$GH_ASSETS/$pattern" "$directory/$pattern"
elif [[ "$*" == "release edit v1.2 --draft=false" ]]; then
  printf 'published' > "$GH_STATE"
else
  exit 45
fi
EOF

cat > "$FIXTURE/scripts/publish-update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'publish-update\n' >> "$ORDER_LOG"
exit "${PUBLISH_STATUS:-0}"
EOF
chmod +x "$FAKE_BIN"/* "$FIXTURE/scripts/publish-update.sh"

assert_before() {
  local first second first_line second_line
  first_line="$(grep -nF "$1" "$ORDER_LOG" | head -1 | cut -d: -f1)"
  second_line="$(grep -nF "$2" "$ORDER_LOG" | head -1 | cut -d: -f1)"
  [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] || fail "$1 was not before $2"
}

run_release() {
  local tag="$1"
  set +e
  output="$(
    GIT_BIN="$FAKE_BIN/git" \
    GH_BIN="$FAKE_BIN/gh" \
    PUBLISH_UPDATE_SCRIPT="$FIXTURE/scripts/publish-update.sh" \
    PUBLISH_STATUS="${PUBLISH_STATUS:-0}" \
    GH_STATE="$GH_STATE" \
    GH_ASSETS="$GH_ASSETS" \
    ORDER_LOG="$ORDER_LOG" \
    "$FIXTURE/scripts/publish-release.sh" "$tag" 2>&1
  )"
  status=$?
  set -e
}

run_release v1.2
[[ "$status" -eq 0 ]] || fail "release failed: $output"
assert_before "release create v1.2" "release upload v1.2"
assert_before "release upload v1.2" "publish-update"
assert_before "publish-update" "release edit v1.2 --draft=false"
[[ "$(cat "$GH_STATE")" == published ]] || fail "release stayed as draft"

run_release v9.9
[[ "$status" -eq 64 ]] || fail "tag/version mismatch must return 64"

rm -f "$GH_STATE" "$GH_ASSETS"/*
: > "$ORDER_LOG"
PUBLISH_STATUS=31 run_release v1.2
[[ "$status" -eq 31 ]] || fail "R2 failure was not propagated"
[[ "$(cat "$GH_STATE")" == draft ]] || fail "failed R2 publish exposed the release"

printf 'draft' > "$GH_STATE"
printf 'different' > "$GH_ASSETS/SwitchTab-1.2-7.dmg"
: > "$ORDER_LOG"
run_release v1.2
[[ "$status" -ne 0 ]] || fail "conflicting GitHub asset was accepted"
[[ "$output" == *"checksum conflict"* ]] || fail "asset conflict error was unclear: $output"

bash -n "$SCRIPT"
echo "publish-release contract tests passed"
```

- [ ] **Step 2: Run the release test and verify it fails**

Run: `rtk test bash scripts/tests/publish-release-test.sh`

Expected: FAIL because `scripts/publish-release.sh` is missing.

- [ ] **Step 3: Implement GitHub draft and publication coordination**

Create `scripts/publish-release.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${RELEASE_CONFIG_PATH:-$PROJECT_ROOT/.env.release.local}"
[[ ! -f "$CONFIG_PATH" ]] || { set -a; source "$CONFIG_PATH"; set +a; }

if [[ $# -ne 1 ]]; then echo "Usage: scripts/publish-release.sh v<version>" >&2; exit 64; fi
tag="$1"
BUILD_ROOT="${DIRECT_BUILD_ROOT:-$PROJECT_ROOT/.build/direct-distribution}"
UPDATE_DIR="${UPDATE_OUTPUT_DIR:-$BUILD_ROOT/updates}"
APPCAST="$UPDATE_DIR/appcast.xml"
GIT_BIN="${GIT_BIN:-git}"
GH_BIN="${GH_BIN:-gh}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XMLLINT_BIN="${XMLLINT_BIN:-/usr/bin/xmllint}"
PUBLISH_UPDATE_SCRIPT="${PUBLISH_UPDATE_SCRIPT:-$PROJECT_ROOT/scripts/publish-update.sh}"
[[ -f "$APPCAST" ]] || { echo "Missing $APPCAST" >&2; exit 66; }

short_version="$("$XMLLINT_BIN" --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])' "$APPCAST")"
url="$("$XMLLINT_BIN" --xpath 'string(//*[local-name()="enclosure"]/@url)' "$APPCAST")"
archive_name="${url##*/}"
DMG="$UPDATE_DIR/$archive_name"
CHECKSUM="$DMG.sha256"
[[ "$tag" == "v$short_version" ]] || { echo "Tag $tag does not match version $short_version" >&2; exit 64; }
[[ -f "$DMG" && -f "$CHECKSUM" ]] || { echo "Missing GitHub release asset" >&2; exit 66; }

head_commit="$("$GIT_BIN" rev-parse HEAD)"
tag_commit="$("$GIT_BIN" rev-parse "$tag^{commit}")"
[[ "$head_commit" == "$tag_commit" ]] || { echo "Tag does not point to HEAD" >&2; exit 64; }
"$GIT_BIN" merge-base --is-ancestor "$tag_commit" origin/main || { echo "Tag commit is not on origin/main" >&2; exit 64; }

release_exists=0
is_draft=true
if is_draft="$("$GH_BIN" release view "$tag" --json isDraft --jq .isDraft 2>/dev/null)"; then
    release_exists=1
else
    "$GH_BIN" release create "$tag" --draft --verify-tag --generate-notes --title "SwitchTab $short_version"
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-github-release.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
asset_names="$("$GH_BIN" release view "$tag" --json assets --jq '.assets[].name')"
for asset in "$DMG" "$CHECKSUM"; do
    name="$(basename "$asset")"
    if grep -Fxq "$name" <<<"$asset_names"; then
        "$GH_BIN" release download "$tag" --pattern "$name" --dir "$temp_dir"
        local_hash="$("$SHASUM_BIN" -a 256 "$asset" | awk '{print $1}')"
        remote_hash="$("$SHASUM_BIN" -a 256 "$temp_dir/$name" | awk '{print $1}')"
        [[ "$local_hash" == "$remote_hash" ]] || { echo "GitHub asset checksum conflict: $name" >&2; exit 1; }
    else
        "$GH_BIN" release upload "$tag" "$asset"
    fi
done

"$PUBLISH_UPDATE_SCRIPT"
if [[ "$is_draft" == true || "$release_exists" -eq 0 ]]; then
    "$GH_BIN" release edit "$tag" --draft=false
fi
echo "Published GitHub Release: $tag"
```

Run: `rtk proxy chmod +x scripts/publish-release.sh`

Expected: the repository records the script as executable when staged.

- [ ] **Step 4: Run the GitHub Release tests**

Run: `rtk test bash scripts/tests/publish-release-test.sh`

Expected: `publish-release contract tests passed`.

- [ ] **Step 5: Commit the GitHub Release publisher**

```bash
rtk git add scripts/publish-release.sh scripts/tests/publish-release-test.sh
rtk git diff --cached --check
rtk git commit -m "feat: publish GitHub release artifacts"
```

### Task 6: Add ephemeral CI signing and tag-triggered release workflow

**Files:**
- Modify: `scripts/build-direct-distribution.sh`
- Create: `.github/workflows/release.yml`
- Create: `scripts/tests/release-workflow-test.sh`

- [ ] **Step 1: Write the failing workflow contract test**

Create `scripts/tests/release-workflow-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$PROJECT_ROOT/.github/workflows/release.yml"
BUILDER="$PROJECT_ROOT/scripts/build-direct-distribution.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 is missing: $2"; }

[[ -f "$WORKFLOW" ]] || fail "release workflow missing"
ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)' "$WORKFLOW"
require "$WORKFLOW" "tags:"
require "$WORKFLOW" "- 'v*'"
require "$WORKFLOW" "workflow_dispatch:"
require "$WORKFLOW" "contents: write"
require "$WORKFLOW" "runs-on: macos-15"
require "$WORKFLOW" "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
require "$WORKFLOW" "npm ci --ignore-scripts"
require "$WORKFLOW" "scripts/build-direct-distribution.sh --release"
require "$WORKFLOW" "scripts/generate-appcast.sh"
require "$WORKFLOW" "scripts/publish-release.sh"
require "$WORKFLOW" "if: always()"
require "$BUILDER" "NOTARYTOOL_KEYCHAIN_PATH"
require "$BUILDER" "--keychain"

echo "release workflow contract tests passed"
```

- [ ] **Step 2: Run the workflow test and verify it fails**

Run: `rtk test bash scripts/tests/release-workflow-test.sh`

Expected: FAIL with `release workflow missing`.

- [ ] **Step 3: Pass an optional CI Keychain path to notarytool**

In `scripts/build-direct-distribution.sh`, add beside the existing profile:

```bash
NOTARYTOOL_KEYCHAIN_PATH="${NOTARYTOOL_KEYCHAIN_PATH:-}"
```

Add to the usage environment section:

```text
  NOTARYTOOL_KEYCHAIN_PATH Optional Keychain containing the notarytool profile.
```

Replace the direct `notarytool submit` invocation with:

```bash
notarytool_args=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
if [[ -n "$NOTARYTOOL_KEYCHAIN_PATH" ]]; then
    notarytool_args+=(--keychain "$NOTARYTOOL_KEYCHAIN_PATH")
fi

xcrun notarytool submit \
    "$DMG_PATH" \
    "${notarytool_args[@]}" \
    --wait
```

- [ ] **Step 4: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      tag:
        description: Existing version tag to release
        required: true
        type: string

permissions:
  contents: write

concurrency:
  group: release-${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: macos-15
    timeout-minutes: 60
    env:
      RELEASE_TAG: ${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}
      NOTARYTOOL_KEYCHAIN_PROFILE: switchtab-ci-notary

    steps:
      - name: Check out release tag
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          ref: ${{ env.RELEASE_TAG }}

      - name: Install locked release tooling
        run: npm ci --ignore-scripts

      - name: Validate release tag
        shell: bash
        run: |
          marketing_version="$(awk -F ' = ' '/MARKETING_VERSION =/ {gsub(/[;[:space:]]/, "", $2); print $2; exit}' SwitchTab.xcodeproj/project.pbxproj)"
          test "$RELEASE_TAG" = "v$marketing_version"
          git merge-base --is-ancestor HEAD origin/main

      - name: Run Swift tests
        run: swift test

      - name: Build unsigned Debug app
        env:
          DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer
        run: xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build

      - name: Install Apple signing credentials
        shell: bash
        env:
          APPLE_CERTIFICATE_P12_BASE64: ${{ secrets.APPLE_CERTIFICATE_P12_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
          APPLE_NOTARY_KEY_P8_BASE64: ${{ secrets.APPLE_NOTARY_KEY_P8_BASE64 }}
          APPLE_NOTARY_KEY_ID: ${{ secrets.APPLE_NOTARY_KEY_ID }}
          APPLE_NOTARY_ISSUER_ID: ${{ secrets.APPLE_NOTARY_ISSUER_ID }}
        run: |
          certificate_path="$RUNNER_TEMP/switchtab-developer-id.p12"
          notary_key_path="$RUNNER_TEMP/AuthKey_$APPLE_NOTARY_KEY_ID.p8"
          keychain_path="$RUNNER_TEMP/switchtab-release.keychain-db"
          keychain_password="$(openssl rand -hex 32)"
          printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate_path"
          printf '%s' "$APPLE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$notary_key_path"
          security create-keychain -p "$keychain_password" "$keychain_path"
          security set-keychain-settings -lut 21600 "$keychain_path"
          security unlock-keychain -p "$keychain_password" "$keychain_path"
          security import "$certificate_path" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
          security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain_path"
          security list-keychains -d user -s "$keychain_path"
          xcrun notarytool store-credentials "$NOTARYTOOL_KEYCHAIN_PROFILE" \
            --key "$notary_key_path" \
            --key-id "$APPLE_NOTARY_KEY_ID" \
            --issuer "$APPLE_NOTARY_ISSUER_ID" \
            --keychain "$keychain_path"
          printf 'NOTARYTOOL_KEYCHAIN_PATH=%s\n' "$keychain_path" >> "$GITHUB_ENV"

      - name: Build notarized DMG
        env:
          SPARKLE_PUBLIC_ED_KEY: ${{ vars.SPARKLE_PUBLIC_ED_KEY }}
          DEVELOPER_ID_APPLICATION: ${{ vars.DEVELOPER_ID_APPLICATION }}
        run: scripts/build-direct-distribution.sh --release

      - name: Generate signed appcast
        env:
          SPARKLE_PUBLIC_ED_KEY: ${{ vars.SPARKLE_PUBLIC_ED_KEY }}
          SPARKLE_PRIVATE_ED_KEY: ${{ secrets.SPARKLE_PRIVATE_ED_KEY }}
          UPDATE_DOMAIN: updates.switchtab.app
        run: scripts/generate-appcast.sh

      - name: Publish R2 update and GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ vars.CLOUDFLARE_ACCOUNT_ID }}
          R2_BUCKET_NAME: switchtab-updates
          UPDATE_DOMAIN: updates.switchtab.app
        run: scripts/publish-release.sh "$RELEASE_TAG"

      - name: Clean up signing credentials
        if: always()
        shell: bash
        run: |
          security delete-keychain "$RUNNER_TEMP/switchtab-release.keychain-db" 2>/dev/null || true
          rm -f "$RUNNER_TEMP/switchtab-developer-id.p12"
          rm -f "$RUNNER_TEMP"/AuthKey_*.p8
```

- [ ] **Step 5: Run the workflow and existing wrapper tests**

Run: `rtk test bash scripts/tests/release-workflow-test.sh`

Expected: `release workflow contract tests passed`.

Run: `rtk test bash scripts/tests/release-local-test.sh`

Expected: `release-local contract tests passed`.

Run: `rtk proxy bash -n scripts/build-direct-distribution.sh`

Expected: no output and exit 0.

- [ ] **Step 6: Commit the workflow**

```bash
rtk git add scripts/build-direct-distribution.sh .github/workflows/release.yml scripts/tests/release-workflow-test.sh
rtk git diff --cached --check
rtk git commit -m "ci: automate notarized tag releases"
```

### Task 7: Document operation and run full verification

**Files:**
- Modify: `README.md`
- Modify: `scripts/tests/release-local-test.sh`

- [ ] **Step 1: Extend the documentation contract**

Add these tracked configuration names to the existing loop in
`scripts/tests/release-local-test.sh` or a second documentation-only loop:

```bash
for name in SPARKLE_KEY_ACCOUNT R2_BUCKET_NAME UPDATE_DOMAIN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID; do
    grep -q "^${name}=" "$EXAMPLE" || fail "$EXAMPLE is missing $name"
done
```

Add README assertions to `scripts/tests/release-local-test.sh`:

```bash
README="$PROJECT_ROOT/README.md"
for text in setup-update-hosting.sh generate-appcast.sh publish-release.sh CLOUDFLARE_API_TOKEN SPARKLE_PRIVATE_ED_KEY 'git push origin v'; do
    grep -Fq "$text" "$README" || fail "$README is missing $text"
done
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `rtk test bash scripts/tests/release-local-test.sh`

Expected: FAIL because the new release instructions are absent from README.

- [ ] **Step 3: Add the operator documentation**

Extend `README.md` with these sections and exact command flow:

````markdown
## Sparkle Update Hosting

Install the locked Wrangler CLI, copy `.env.release.local.example` to
`.env.release.local`, fill in the Cloudflare account and zone IDs, then run the
one-time idempotent setup:

```bash
npm ci --ignore-scripts
scripts/setup-update-hosting.sh
```

Local publishing uses the notarized DMG produced by `release-local.sh`:

```bash
scripts/release-local.sh
scripts/generate-appcast.sh
scripts/publish-release.sh v1.0
```

## Automated GitHub Releases

Configure repository variables `DEVELOPER_ID_APPLICATION`,
`SPARKLE_PUBLIC_ED_KEY`, and `CLOUDFLARE_ACCOUNT_ID`. Configure repository
secrets `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID`,
`APPLE_NOTARY_ISSUER_ID`, `SPARKLE_PRIVATE_ED_KEY`, and
`CLOUDFLARE_API_TOKEN`.

Create the Cloudflare API token only after the bucket exists. Scope it to the
`switchtab-updates` bucket with the `Workers R2 Storage Bucket Item Write`
permission; the release workflow does not need DNS or bucket-management
permission. See Cloudflare's current R2 authentication documentation:
https://developers.cloudflare.com/r2/api/tokens/

Export the existing Sparkle private key only long enough to store it as a
GitHub secret, then securely delete the exported file:

```bash
.build/direct-distribution/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account ed25519 -x /tmp/switchtab-sparkle-private-key
gh secret set SPARKLE_PRIVATE_ED_KEY < /tmp/switchtab-sparkle-private-key
```

Restrict creation of `v*` tags to maintainers. The tag without its leading `v`
must exactly equal `MARKETING_VERSION`:

```bash
git tag -a v1.0 -m "SwitchTab 1.0"
git push origin v1.0
```

The release workflow tests the project, creates a notarized DMG, publishes the
Sparkle update to `https://updates.switchtab.app/appcast.xml`, then publishes a
GitHub Release. Do not rebuild a partially published tag; verify the R2 checksum
and finish or discard the existing GitHub draft.
````

Outside the Markdown code block, explicitly warn that Base64 is transport
encoding, not encryption, and that the exported Sparkle key and `.p12` must not
be committed.

- [ ] **Step 4: Run all shell contract tests**

Run:

```bash
rtk test bash scripts/tests/release-tooling-test.sh
rtk test bash scripts/tests/release-local-test.sh
rtk test bash scripts/tests/generate-appcast-test.sh
rtk test bash scripts/tests/setup-update-hosting-test.sh
rtk test bash scripts/tests/publish-update-test.sh
rtk test bash scripts/tests/publish-release-test.sh
rtk test bash scripts/tests/release-workflow-test.sh
```

Expected: every command prints its `... contract tests passed` message.

- [ ] **Step 5: Run Swift and Xcode verification**

Run: `rtk test swift test`

Expected: 18 tests pass with zero failures.

Run:

```bash
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SwitchTab.xcodeproj \
  -scheme SwitchTab \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

Run:

```bash
rtk env SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
```

Expected: the generated direct-distribution project and plist pass their lint checks.

- [ ] **Step 6: Run static and repository-boundary checks**

```bash
rtk proxy bash -n scripts/*.sh scripts/tests/*.sh
rtk git diff --check
rtk git status --short
rtk git diff -- SwitchTab/SwitchTabApp.swift SwitchTabTests/Services/AppStoreDistributionSettingsTests.swift
```

Expected: Bash syntax and whitespace checks pass. The final command confirms
the pre-existing Swift edits were not changed by this implementation.

Do not run `scripts/setup-update-hosting.sh`, `scripts/publish-update.sh`,
`scripts/publish-release.sh`, create a tag, push, or start a live release during
verification.

- [ ] **Step 7: Commit documentation and verification contracts**

```bash
rtk git add README.md scripts/tests/release-local-test.sh
rtk git diff --cached --check
rtk git commit -m "docs: explain automated release operation"
```

- [ ] **Step 8: Review the complete implementation diff**

```bash
rtk git log --oneline --decorate -8
rtk git diff HEAD~7..HEAD --stat
rtk git status --short --branch
```

Expected: only the planned release tooling, tests, workflow, configuration
example, ignore rule, package lock, and README are part of the seven feature
commits; the user's two pre-existing Swift changes remain unstaged.

## Live Handoff After Implementation

The implementation is complete before any external mutation. The maintainer
then performs, in order:

1. Add the listed GitHub repository variables and secrets.
2. Create a GitHub ruleset protecting `v*` tags.
3. Run `scripts/setup-update-hosting.sh` once and wait for
   `https://updates.switchtab.app/` to resolve.
4. Push the implementation branch and merge it to `main`.
5. Create and push a tag matching the checked-in marketing version.
6. Watch the Release workflow, then verify the GitHub Release, DMG checksum,
   `appcast.xml`, and the in-app Sparkle update check.
