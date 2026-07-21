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
  "Prepare signing workspace",
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
assert(checkout.dig("with", "ref") == "refs/tags/${{ env.RELEASE_TAG }}", "checkout must use the fully qualified release tag ref")
assert(checkout.dig("with", "fetch-depth") == 0, "checkout must fetch complete history")
assert(checkout.dig("with", "persist-credentials") == false, "checkout credentials must not persist into validation or tests")
uses_steps.each do |step|
  assert(step["uses"].match?(%r{\A[^@]+@[0-9a-f]{40}\z}), "all actions must be SHA-pinned")
end

validation = steps.fetch(names.index("Validate release tag and provenance")).fetch("run")
assert(validation.include?("^v[0-9]+(\\.[0-9]+)*$"), "tag shape validation is missing")
assert(validation.include?('tag_ref="refs/tags/$RELEASE_TAG"'), "validation must construct the exact tag ref")
assert(validation.include?('git show-ref --verify --quiet "$tag_ref"'), "validation must verify the exact tag ref exists")
assert(validation.include?('git rev-parse "$tag_ref^{commit}"'), "validation must resolve the exact tag ref commit")
assert(!validation.include?('git rev-parse "${RELEASE_TAG}^{commit}"'), "validation must never resolve the bare release tag")
assert(validation.lines.grep(/git rev-parse/).none? { |line| line.include?("RELEASE_TAG") }, "validation must never pass RELEASE_TAG directly to rev-parse")
tag_ref_position = validation.index('tag_ref="refs/tags/$RELEASE_TAG"')
tag_verify_position = validation.index('git show-ref --verify --quiet "$tag_ref"')
tag_resolve_position = validation.index('git rev-parse "$tag_ref^{commit}"')
assert(tag_ref_position < tag_verify_position && tag_verify_position < tag_resolve_position, "exact tag construction, verification, and resolution are out of order")
assert(validation.include?("git rev-parse HEAD"), "HEAD lookup is missing")
assert(validation.include?("MARKETING_VERSION"), "project marketing version validation is missing")
assert(!validation.include?("print $3; exit"), "MARKETING_VERSION extraction must consume xcodebuild output under pipefail")
assert(validation.include?("if ! git rev-parse --verify origin/main"), "origin/main must be checked before any fallback fetch")
assert(validation.include?("git fetch --no-tags origin"), "unauthenticated origin/main fallback fetch is missing")
assert(validation.include?("refs/heads/main:refs/remotes/origin/main"), "origin/main fallback fetch must update only the main remote-tracking ref")
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
prepare_index = names.index("Prepare signing workspace")
assert(prepare_index == credentials_index - 1, "signing workspace must be prepared immediately before credential installation")
prepare = steps.fetch(prepare_index)
assert(prepare["shell"] == "bash", "signing workspace preparation must explicitly use bash")
assert(!prepare.to_s.include?("secrets."), "signing workspace preparation must receive no secrets")
prepare_run = prepare.fetch("run")
[
  "set -euo pipefail",
  "set +x",
  "umask 077",
  "mktemp -d \"$RUNNER_TEMP/switchtab-release.XXXXXX\"",
  "SIGNING_TEMP_DIR=%s",
  "NOTARYTOOL_KEYCHAIN_PATH=%s",
  ">> \"$GITHUB_ENV\""
].each do |fragment|
  assert(prepare_run.include?(fragment), "signing workspace preparation is missing #{fragment}")
end
exported_prepare_names = prepare_run.scan(/printf '[^']*?([A-Z][A-Z0-9_]+)=%s/).flatten.uniq.sort
assert(exported_prepare_names == %w[NOTARYTOOL_KEYCHAIN_PATH SIGNING_TEMP_DIR], "signing workspace may export only safe paths")
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
  "--keychain \"$KEYCHAIN_PATH\""
].each do |fragment|
  assert(credential_run.include?(fragment), "credential setup is missing #{fragment}")
end
assert(credential_run.include?('SIGNING_TEMP_DIR="${SIGNING_TEMP_DIR:-}"'), "credential setup must safely read the prepared directory")
assert(credential_run.include?('NOTARYTOOL_KEYCHAIN_PATH="${NOTARYTOOL_KEYCHAIN_PATH:-}"'), "credential setup must safely read the prepared Keychain path")
assert(credential_run.include?('KEYCHAIN_PATH="$NOTARYTOOL_KEYCHAIN_PATH"'), "credential setup must use the prepared Keychain path")
assert(credential_run.include?('CERTIFICATE_PATH="$SIGNING_TEMP_DIR/switchtab-release-certificate.p12"'), "certificate must stay inside the random signing directory")
assert(credential_run.include?('NOTARY_KEY_PATH="$SIGNING_TEMP_DIR/switchtab-notary-auth-key.p8"'), "notary key must stay inside the random signing directory")
assert(credential_run.include?('EXPECTED_KEYCHAIN_PATH="$SIGNING_TEMP_DIR/switchtab-release.keychain-db"'), "credential setup must validate the prepared Keychain path")
assert(!credential_run.include?('$RUNNER_TEMP/switchtab-release'), "credential files must not use fixed RUNNER_TEMP paths")
assert(!credential_run.include?("GITHUB_ENV"), "credential installation must not rewrite prepared environment paths")
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
assert(cleanup_run.include?('runner_temp="${RUNNER_TEMP:-}"'), "cleanup must tolerate a missing runner temp under bash -u")
assert(cleanup_run.include?('signing_temp_dir="${SIGNING_TEMP_DIR:-}"'), "cleanup must tolerate a missing signing directory under bash -u")
assert(cleanup_run.include?('keychain_path="${NOTARYTOOL_KEYCHAIN_PATH:-}"'), "cleanup must tolerate a missing Keychain path under bash -u")
assert(cleanup_run.include?('"$runner_temp"/switchtab-release.*'), "cleanup must validate the random signing directory prefix")
assert(cleanup_run.include?('expected_keychain_path="$signing_temp_dir/switchtab-release.keychain-db"'), "cleanup must validate the exact Keychain path")
assert(cleanup_run.include?('[[ "$keychain_path" == "$expected_keychain_path" && -e "$keychain_path" ]]'), "cleanup must not ask Security to delete an absent Keychain")
security_cleanup = cleanup_run.lines.find { |line| line.include?("security delete-keychain") }
assert(security_cleanup&.include?('"$keychain_path"') && security_cleanup.include?("|| true"), "Keychain cleanup must be exact and failure-suppressed")
certificate_cleanup = cleanup_run.lines.find { |line| line.include?("switchtab-release-certificate.p12") && line.include?("rm -f") }
assert(certificate_cleanup&.include?('"$signing_temp_dir/') && certificate_cleanup.include?("|| true"), "certificate cleanup must be exact and failure-suppressed")
notary_cleanup = cleanup_run.lines.find { |line| line.include?("switchtab-notary-auth-key.p8") && line.include?("rm -f") }
assert(notary_cleanup&.include?('"$signing_temp_dir/') && notary_cleanup.include?("|| true"), "notary key cleanup must be exact and failure-suppressed")
directory_cleanup = cleanup_run.lines.find { |line| line.match?(/\brmdir\b/) }
assert(directory_cleanup&.include?('"$signing_temp_dir"') && directory_cleanup.include?("|| true"), "signing directory cleanup must be exact and failure-suppressed")
assert(!cleanup_run.include?("rm -rf"), "cleanup must not recursively delete paths")
assert(!cleanup_run.match?(/rm -f[^\n]*[*?]/), "cleanup file deletion must not use globs")

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
PREPARE_HARNESS="$TEMP_ROOT/prepare-signing-workspace.sh"
CLEANUP_HARNESS="$TEMP_ROOT/cleanup-signing-workspace.sh"
VALIDATION_SOURCE="$TEMP_ROOT/validate-release.sh"
TAG_REF_HARNESS="$TEMP_ROOT/validate-tag-ref.sh"
mkdir -p "$FAKE_BIN"

extract_workflow_step() {
    local step_name="$1"
    local destination="$2"

    /usr/bin/ruby - "$WORKFLOW_PATH" "$step_name" > "$destination" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
step_name = ARGV.fetch(1)
step = workflow.fetch("jobs").fetch("release").fetch("steps").find { |entry| entry["name"] == step_name }
raise "missing workflow step: #{step_name}" unless step

puts "#!/usr/bin/env bash"
puts step.fetch("run")
RUBY
    chmod +x "$destination"
}

extract_workflow_step "Prepare signing workspace" "$PREPARE_HARNESS"
extract_workflow_step "Cleanup Apple credentials" "$CLEANUP_HARNESS"
extract_workflow_step "Validate release tag and provenance" "$VALIDATION_SOURCE"

{
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    /usr/bin/awk '
        /tag_ref="refs\/tags\/\$RELEASE_TAG"/ { capture = 1 }
        capture { print }
        capture && /tag_commit=.*git rev-parse/ { exit }
    ' "$VALIDATION_SOURCE"
    printf '%s\n' 'printf "%s\n" "$tag_commit"'
} > "$TAG_REF_HARNESS"
chmod +x "$TAG_REF_HARNESS"

# A same-named branch must never satisfy exact release-tag validation.
TAG_REPOSITORY="$TEMP_ROOT/tag-repository"
mkdir -p "$TAG_REPOSITORY"
(
    cd -- "$TAG_REPOSITORY"
    git init -q
    git -c user.name='SwitchTab Test' -c user.email='switchtab@example.invalid' \
        -c commit.gpgsign=false commit --allow-empty -q -m 'branch target'
    git branch v1.2
)
BRANCH_COMMIT="$(cd -- "$TAG_REPOSITORY" && git rev-parse 'refs/heads/v1.2^{commit}')"
[[ "$(cd -- "$TAG_REPOSITORY" && git rev-parse 'v1.2^{commit}')" == "$BRANCH_COMMIT" ]] || \
    fail "local ambiguity fixture did not resolve the bare branch"
set +e
output="$(cd -- "$TAG_REPOSITORY" && RELEASE_TAG='v1.2' /bin/bash "$TAG_REF_HARNESS" 2>&1)"
status=$?
set -e
[[ "$status" -eq 64 ]] || fail "same-named branch satisfied exact tag validation; status=$status output=$output"

# When both names exist at different commits, validation must resolve refs/tags/v1.2.
(
    cd -- "$TAG_REPOSITORY"
    git -c user.name='SwitchTab Test' -c user.email='switchtab@example.invalid' \
        -c commit.gpgsign=false commit --allow-empty -q -m 'tag target'
    git tag v1.2
)
TAG_COMMIT="$(cd -- "$TAG_REPOSITORY" && git rev-parse 'refs/tags/v1.2^{commit}')"
[[ "$TAG_COMMIT" != "$BRANCH_COMMIT" ]] || fail "tag/branch ambiguity fixture did not use distinct commits"
output="$(cd -- "$TAG_REPOSITORY" && RELEASE_TAG='v1.2' /bin/bash "$TAG_REF_HARNESS")"
[[ "$output" == "$TAG_COMMIT" ]] || fail "exact tag validation resolved the branch instead of the tag: $output"

# The non-secret preparation creates a random private directory and exports only its safe paths.
RUNNER_FIXTURE="$TEMP_ROOT/runner"
GITHUB_ENV_FIXTURE="$TEMP_ROOT/github-env"
mkdir -p "$RUNNER_FIXTURE"
: > "$GITHUB_ENV_FIXTURE"
RUNNER_TEMP="$RUNNER_FIXTURE" GITHUB_ENV="$GITHUB_ENV_FIXTURE" /bin/bash -u "$PREPARE_HARNESS"
[[ "$(/usr/bin/wc -l < "$GITHUB_ENV_FIXTURE" | tr -d '[:space:]')" == 2 ]] || \
    fail "signing preparation exported unexpected environment entries: $(<"$GITHUB_ENV_FIXTURE")"
SIGNING_FIXTURE="$(/usr/bin/sed -n 's/^SIGNING_TEMP_DIR=//p' "$GITHUB_ENV_FIXTURE")"
PREPARED_KEYCHAIN="$(/usr/bin/sed -n 's/^NOTARYTOOL_KEYCHAIN_PATH=//p' "$GITHUB_ENV_FIXTURE")"
[[ "$SIGNING_FIXTURE" =~ ^$RUNNER_FIXTURE/switchtab-release[.][A-Za-z0-9]{6}$ ]] || \
    fail "signing preparation did not use the random RUNNER_TEMP template: $SIGNING_FIXTURE"
[[ -d "$SIGNING_FIXTURE" && ! -L "$SIGNING_FIXTURE" ]] || fail "prepared signing directory is missing or unsafe"
[[ "$PREPARED_KEYCHAIN" == "$SIGNING_FIXTURE/switchtab-release.keychain-db" ]] || \
    fail "prepared Keychain path escaped the random signing directory"

# Cleanup must be a no-op under bash -u if preparation never exported its paths.
/usr/bin/env -u SIGNING_TEMP_DIR -u NOTARYTOOL_KEYCHAIN_PATH \
    RUNNER_TEMP="$RUNNER_FIXTURE" /bin/bash -u "$CLEANUP_HARNESS"

# Cleanup removes exact credential files and the random directory without requiring a Keychain to exist.
: > "$SIGNING_FIXTURE/switchtab-release-certificate.p12"
: > "$SIGNING_FIXTURE/switchtab-notary-auth-key.p8"
RUNNER_TEMP="$RUNNER_FIXTURE" \
SIGNING_TEMP_DIR="$SIGNING_FIXTURE" \
NOTARYTOOL_KEYCHAIN_PATH="$PREPARED_KEYCHAIN" \
/bin/bash -u "$CLEANUP_HARNESS"
if [[ -e "$SIGNING_FIXTURE" ]]; then
    /bin/ls -la "$SIGNING_FIXTURE" >&2
    fail "cleanup did not remove the empty random signing directory"
fi

# An out-of-prefix path must remain untouched.
UNSAFE_FIXTURE="$TEMP_ROOT/outside-signing"
mkdir -p "$UNSAFE_FIXTURE"
: > "$UNSAFE_FIXTURE/switchtab-release-certificate.p12"
RUNNER_TEMP="$RUNNER_FIXTURE" \
SIGNING_TEMP_DIR="$UNSAFE_FIXTURE" \
NOTARYTOOL_KEYCHAIN_PATH="$UNSAFE_FIXTURE/switchtab-release.keychain-db" \
/bin/bash -u "$CLEANUP_HARNESS"
[[ -f "$UNSAFE_FIXTURE/switchtab-release-certificate.p12" ]] || fail "cleanup touched an out-of-prefix path"

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
