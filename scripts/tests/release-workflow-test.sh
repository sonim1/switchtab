#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_PATH="$PROJECT_ROOT/.github/workflows/release.yml"
BUILDER_PATH="$PROJECT_ROOT/scripts/build-direct-distribution.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -f "$WORKFLOW_PATH" ]] || fail ".github/workflows/release.yml is missing"
[[ -f "$BUILDER_PATH" ]] || fail "scripts/build-direct-distribution.sh is missing"

/usr/bin/ruby - "$WORKFLOW_PATH" "$BUILDER_PATH" <<'RUBY'
require "yaml"

workflow_path, builder_path = ARGV
workflow_source = File.read(workflow_path)
builder_source = File.read(builder_path)
workflow = YAML.safe_load(workflow_source, permitted_classes: [], permitted_symbols: [], aliases: false)

def assert(condition, message)
  raise "FAIL: #{message}" unless condition
end

assert(workflow.is_a?(Hash), "workflow must parse as a mapping")
assert(workflow["name"] == "Release", "workflow name must be Release")

triggers = workflow["on"]
assert(triggers.is_a?(Hash), "workflow must quote and define the on mapping")
assert(triggers.keys.sort == %w[push workflow_dispatch], "only tag push and workflow_dispatch triggers are allowed")
assert(triggers.dig("push", "tags") == ["v*"], "push trigger must only match v* tags")
manual_tag = triggers.dig("workflow_dispatch", "inputs", "tag")
assert(manual_tag.is_a?(Hash), "workflow_dispatch.tag input is required")
assert(manual_tag["required"] == true, "workflow_dispatch.tag must be required")
assert(manual_tag["type"] == "string", "workflow_dispatch.tag must be a string")
assert(manual_tag["description"].to_s.downcase.include?("existing version tag"), "manual tag must be described as an existing version tag")
assert(!workflow_source.include?("pull_request"), "pull_request must not trigger releases")

assert(workflow["permissions"] == { "contents" => "write" }, "job must receive only contents: write")
jobs = workflow.fetch("jobs")
assert(jobs.keys == ["release"], "workflow must contain one release job")
job = jobs.fetch("release")
assert(job["runs-on"] == "macos-15", "release job must run on macos-15")
assert(job["timeout-minutes"] == 60, "release job timeout must be 60 minutes")
assert(job.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "RELEASE_TAG must resolve push and manual tags")
assert(job.dig("env", "NOTARYTOOL_KEYCHAIN_PROFILE") == "switchtab-ci-notary", "CI notary profile must be fixed")
concurrency = job["concurrency"]
assert(concurrency.is_a?(Hash), "release concurrency must be job-scoped")
assert(concurrency["cancel-in-progress"] == false, "release concurrency must not cancel in-progress releases")
assert(concurrency["group"].to_s.start_with?("release-"), "release concurrency must be tag-scoped")
assert(concurrency["group"].to_s.include?("inputs.tag") && concurrency["group"].to_s.include?("github.ref_name"), "concurrency must use the effective release tag")

steps = job.fetch("steps")
names = steps.map { |step| step["name"] }
required_order = [
  "Checkout release tag",
  "Validate release tag and provenance",
  "Install release tooling",
  "Run release contract tests",
  "Run Swift tests",
  "Build unsigned Debug app",
  "Install Apple credentials",
  "Build notarized DMG",
  "Generate signed appcast",
  "Publish release",
  "Cleanup Apple credentials"
]
positions = required_order.map { |name| names.index(name) }
assert(positions.none?(&:nil?), "required release steps are missing")
assert(positions == positions.sort, "release steps are out of order")

uses_steps = steps.select { |step| step.key?("uses") }
assert(uses_steps.length == 1, "only the pinned checkout action is allowed")
checkout = steps.fetch(names.index("Checkout release tag"))
assert(checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "checkout must use the approved full SHA")
assert(checkout.dig("with", "ref") == "${{ env.RELEASE_TAG }}", "checkout must use RELEASE_TAG")
assert(checkout.dig("with", "fetch-depth") == 0, "checkout must fetch complete history")
uses_steps.each do |step|
  assert(step["uses"].match?(%r{\A[^@]+@[0-9a-f]{40}\z}), "all actions must be SHA-pinned")
end

validation = steps.fetch(names.index("Validate release tag and provenance")).fetch("run")
assert(validation.include?("^v[0-9]+(\\.[0-9]+)*$"), "tag shape validation is missing")
assert(validation.include?("git rev-parse \"${RELEASE_TAG}^{commit}\""), "tag commit lookup is missing")
assert(validation.include?("git rev-parse HEAD"), "HEAD lookup is missing")
assert(validation.include?("MARKETING_VERSION"), "project marketing version validation is missing")
assert(!validation.include?("print $3; exit"), "MARKETING_VERSION extraction must consume xcodebuild output under pipefail")
assert(validation.include?("git fetch origin main"), "origin/main fetch is missing")
assert(validation.include?("git merge-base --is-ancestor HEAD origin/main"), "main ancestry validation is missing")

tooling = steps.fetch(names.index("Install release tooling")).fetch("run")
assert(tooling.include?("npm ci --ignore-scripts"), "release tooling must use npm ci --ignore-scripts")
contracts = steps.fetch(names.index("Run release contract tests")).fetch("run")
%w[
  release-tooling-test.sh
  release-local-test.sh
  generate-appcast-test.sh
  setup-update-hosting-test.sh
  publish-update-test.sh
  publish-release-test.sh
  release-workflow-test.sh
].each do |script|
  assert(contracts.include?("scripts/tests/#{script}"), "contract suite does not invoke #{script}")
end
assert(steps.fetch(names.index("Run Swift tests")).fetch("run").include?("swift test"), "Swift tests are missing")
unsigned_build = steps.fetch(names.index("Build unsigned Debug app")).fetch("run")
%w[xcodebuild SwitchTab.xcodeproj SwitchTab Debug arm64 CODE_SIGNING_ALLOWED=NO].each do |token|
  assert(unsigned_build.include?(token), "unsigned Xcode build is missing #{token}")
end
assert(unsigned_build.include?("DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"), "unsigned build must select Xcode.app")

credentials_index = names.index("Install Apple credentials")
steps[0...credentials_index].each do |step|
  serialized = step.to_s
  assert(!serialized.include?("secrets."), "release secrets must not be available before tests")
end
credentials = steps.fetch(credentials_index)
assert(credentials["shell"] == "bash", "credential installation must explicitly use bash")
credential_env = credentials.fetch("env")
apple_secrets = %w[
  APPLE_CERTIFICATE_P12_BASE64
  APPLE_CERTIFICATE_PASSWORD
  APPLE_NOTARY_KEY_P8_BASE64
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
]
apple_secrets.each do |name|
  assert(credential_env[name] == "${{ secrets.#{name} }}", "credential step is missing #{name}")
end
credential_run = credentials.fetch("run")
[
  "set +x",
  "umask 077",
  "/usr/bin/base64 -D",
  "/usr/bin/openssl rand -base64",
  "/usr/bin/security create-keychain",
  "/usr/bin/security unlock-keychain",
  "/usr/bin/security set-keychain-settings",
  "/usr/bin/security import",
  "/usr/bin/security set-key-partition-list",
  "/usr/bin/security list-keychains",
  "xcrun notarytool store-credentials",
  "--keychain \"$KEYCHAIN_PATH\"",
  "NOTARYTOOL_KEYCHAIN_PATH=%s"
].each do |fragment|
  assert(credential_run.include?(fragment), "credential setup is missing #{fragment}")
end
assert(credential_run.include?("switchtab-release.keychain-db"), "temporary Keychain must have the fixed release name")
assert(credential_run.include?("switchtab-release-certificate.p12"), "certificate path must be exact")
assert(credential_run.include?("switchtab-notary-auth-key.p8"), "notary key path must be exact")
assert(!credential_run.match?(/GITHUB_ENV.*(PASSWORD|P12_BASE64|P8_BASE64|PRIVATE)/), "private material must not be written to GITHUB_ENV")

build = steps.fetch(names.index("Build notarized DMG"))
assert(build.fetch("run").include?("scripts/build-direct-distribution.sh --release"), "notarized builder invocation is missing")
assert(build.dig("env", "SPARKLE_PUBLIC_ED_KEY") == "${{ vars.SPARKLE_PUBLIC_ED_KEY }}", "build must use the public Sparkle repository variable")
assert(build.dig("env", "DEVELOPER_ID_APPLICATION") == "${{ vars.DEVELOPER_ID_APPLICATION }}", "build must use the Developer ID repository variable")
assert(build.fetch("env").values.none? { |value| value.to_s.include?("secrets.") }, "build step must receive no release secrets")

appcast = steps.fetch(names.index("Generate signed appcast"))
assert(appcast.fetch("run").include?("scripts/generate-appcast.sh"), "appcast generator invocation is missing")
assert(appcast.dig("env", "SPARKLE_PUBLIC_ED_KEY") == "${{ vars.SPARKLE_PUBLIC_ED_KEY }}", "appcast generation needs the public key variable")
assert(appcast.dig("env", "SPARKLE_PRIVATE_ED_KEY") == "${{ secrets.SPARKLE_PRIVATE_ED_KEY }}", "appcast generation needs the private key secret")
assert(appcast.dig("env", "UPDATE_DOMAIN") == "updates.switchtab.app", "appcast generation must use the production update domain")

publish = steps.fetch(names.index("Publish release"))
assert(publish.fetch("run").include?("scripts/publish-release.sh \"$RELEASE_TAG\""), "release publisher must receive the validated tag")
publish_env = publish.fetch("env")
expected_publish_env = {
  "GH_TOKEN" => "${{ github.token }}",
  "CLOUDFLARE_API_TOKEN" => "${{ secrets.CLOUDFLARE_API_TOKEN }}",
  "CLOUDFLARE_ACCOUNT_ID" => "${{ vars.CLOUDFLARE_ACCOUNT_ID }}",
  "R2_ACCESS_KEY_ID" => "${{ secrets.R2_ACCESS_KEY_ID }}",
  "R2_SECRET_ACCESS_KEY" => "${{ secrets.R2_SECRET_ACCESS_KEY }}",
  "R2_BUCKET_NAME" => "switchtab-updates",
  "UPDATE_DOMAIN" => "updates.switchtab.app"
}
assert(publish_env == expected_publish_env, "publish step environment is incomplete or overprivileged")
assert(!workflow_source.include?("CLOUDFLARE_ZONE_ID"), "release workflow must not receive zone credentials")

all_secret_references = workflow_source.scan(/secrets\.([A-Z0-9_]+)/).flatten.uniq.sort
expected_secret_references = (apple_secrets + %w[
  CLOUDFLARE_API_TOKEN
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  SPARKLE_PRIVATE_ED_KEY
]).sort
assert(all_secret_references == expected_secret_references, "workflow secret set is incomplete or overprivileged")

cleanup = steps.fetch(names.index("Cleanup Apple credentials"))
assert(cleanup["if"] == "always()", "credential cleanup must run unconditionally")
cleanup_run = cleanup.fetch("run")
assert(cleanup_run.include?("set +x"), "cleanup must disable xtrace")
assert(cleanup_run.include?("/usr/bin/security delete-keychain \"$RUNNER_TEMP/switchtab-release.keychain-db\""), "cleanup must delete the exact temporary Keychain")
assert(cleanup_run.include?("\"$RUNNER_TEMP/switchtab-release-certificate.p12\""), "cleanup must delete the exact certificate file")
assert(cleanup_run.include?("\"$RUNNER_TEMP/switchtab-notary-auth-key.p8\""), "cleanup must delete the exact notary key file")
assert(!cleanup_run.include?("*"), "cleanup must not use broad globs")

assert(builder_source.include?('NOTARYTOOL_KEYCHAIN_PATH="${NOTARYTOOL_KEYCHAIN_PATH:-}"'), "builder must accept an optional notary Keychain path")
assert(builder_source.match?(/NOTARYTOOL_KEYCHAIN_PATH[[:space:]]+Optional Keychain containing the notarytool profile\./), "builder usage must document the optional Keychain")
assert(builder_source.include?('NOTARYTOOL_ARGS=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")'), "notary arguments must begin with the profile")
assert(builder_source.include?('if [[ -n "$NOTARYTOOL_KEYCHAIN_PATH" ]]; then'), "builder must conditionally add the Keychain path")
assert(builder_source.include?('NOTARYTOOL_ARGS+=(--keychain "$NOTARYTOOL_KEYCHAIN_PATH")'), "builder must append the optional Keychain path")
submit = builder_source.index("xcrun notarytool submit")
args = builder_source.index('"${NOTARYTOOL_ARGS[@]}"', submit || 0)
wait = builder_source.index("--wait", submit || 0)
assert(submit && args && wait && submit < args && args < wait, "notarytool must receive conditional arguments before --wait")
RUBY

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-release-workflow.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
FAKE_BIN="$TEMP_ROOT/bin"
NOTARY_HARNESS="$TEMP_ROOT/notary-harness.sh"
NOTARY_LOG="$TEMP_ROOT/notary.log"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
    printf '<%s>\n' "$argument" >> "$NOTARY_LOG"
done
EOF
chmod +x "$FAKE_BIN/xcrun"

{
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    /usr/bin/awk '
        /^NOTARYTOOL_ARGS=/ { capture = 1 }
        capture && /^xcrun stapler/ { capture = 0 }
        capture { print }
    ' "$BUILDER_PATH"
} > "$NOTARY_HARNESS"
chmod +x "$NOTARY_HARNESS"

: > "$NOTARY_LOG"
NOTARY_LOG="$NOTARY_LOG" \
PATH="$FAKE_BIN:/usr/bin:/bin" \
DMG_PATH='/tmp/SwitchTab.dmg' \
NOTARYTOOL_KEYCHAIN_PROFILE='switchtab-ci-notary' \
NOTARYTOOL_KEYCHAIN_PATH='' \
bash "$NOTARY_HARNESS"
expected_without_keychain=$'<notarytool>\n<submit>\n</tmp/SwitchTab.dmg>\n<--keychain-profile>\n<switchtab-ci-notary>\n<--wait>'
[[ "$(<"$NOTARY_LOG")" == "$expected_without_keychain" ]] || \
    fail "empty Keychain path changed notarytool arguments: $(<"$NOTARY_LOG")"

: > "$NOTARY_LOG"
KEYCHAIN_FIXTURE="$TEMP_ROOT/CI Release.keychain-db"
NOTARY_LOG="$NOTARY_LOG" \
PATH="$FAKE_BIN:/usr/bin:/bin" \
DMG_PATH='/tmp/SwitchTab.dmg' \
NOTARYTOOL_KEYCHAIN_PROFILE='switchtab-ci-notary' \
NOTARYTOOL_KEYCHAIN_PATH="$KEYCHAIN_FIXTURE" \
bash "$NOTARY_HARNESS"
expected_with_keychain="<notarytool>"$'\n'"<submit>"$'\n'"</tmp/SwitchTab.dmg>"$'\n'"<--keychain-profile>"$'\n'"<switchtab-ci-notary>"$'\n'"<--keychain>"$'\n'"<$KEYCHAIN_FIXTURE>"$'\n'"<--wait>"
[[ "$(<"$NOTARY_LOG")" == "$expected_with_keychain" ]] || \
    fail "nonempty Keychain path was not passed atomically: $(<"$NOTARY_LOG")"

/usr/bin/ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)' "$WORKFLOW_PATH"
bash -n "$BUILDER_PATH"
bash -n "$0"

echo "release workflow contract tests passed"
