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

def steps_by_name(job, label)
  steps = job.fetch("steps")
  grouped = steps.group_by { |step| step["name"] }
  duplicates = grouped.select { |_name, entries| entries.length != 1 }.keys
  assert(duplicates.empty?, "#{label} step names must be unique: #{duplicates.join(', ')}")
  grouped.transform_values(&:first)
end

def assert_default_success_guard(step, label)
  assert(!step.key?("continue-on-error"), "#{label} must fail the job on error")
  assert(!step.key?("if"), "#{label} must use the default success condition")
end

def validate_publication_and_notification(release, notify)
  release_names = release.fetch("steps").map { |step| step["name"] }
  expected_release_names = [
    "Checkout verified release commit",
    "Verify release commit",
    "Prepare signing workspace",
    "Install Apple credentials",
    "Build notarized DMG",
    "Generate signed appcast",
    "Generate release manifest",
    "Publish release",
    "Cleanup Apple credentials"
  ]
  assert(release_names == expected_release_names, "release semantic step list must be exact")
  release_steps = steps_by_name(release, "release")
  publish = release_steps.fetch("Publish release")
  assert_default_success_guard(publish, "Publish release")
  assert(publish["shell"] == "bash", "Publish release must explicitly use bash")
  assert(publish["run"] == 'scripts/publish-release.sh "$RELEASE_TAG"', "Publish release command must be exact")
  assert(publish["env"] == {
    "GH_TOKEN" => "${{ github.token }}",
    "CLOUDFLARE_ACCOUNT_ID" => "${{ vars.CLOUDFLARE_ACCOUNT_ID }}",
    "R2_ACCESS_KEY_ID" => "${{ secrets.R2_ACCESS_KEY_ID }}",
    "R2_SECRET_ACCESS_KEY" => "${{ secrets.R2_SECRET_ACCESS_KEY }}",
    "R2_BUCKET_NAME" => "switchtab",
    "UPDATE_DOMAIN" => "updates.switchtab.royjen.com"
  }, "Publish release environment must be exact")
  assert(!release.to_s.include?("create-github-app-token"), "release must not mint the tap token")
  assert(!release.to_s.include?("dispatch-homebrew-update.sh"), "release must not dispatch to the tap")

  notify_names = notify.fetch("steps").map { |step| step["name"] }
  expected_notify_names = [
    "Checkout verified release commit",
    "Verify release commit",
    "Create tap GitHub App token",
    "Notify Homebrew tap"
  ]
  assert(notify_names == expected_notify_names, "notify semantic step list must be exact")
  notify_steps = steps_by_name(notify, "notify")
  token = notify_steps.fetch("Create tap GitHub App token")
  assert_default_success_guard(token, "Create tap GitHub App token")
  assert(token["id"] == "tap-token", "tap token step must use the stable tap-token id")
  assert(token["uses"] == "actions/create-github-app-token@67018539274d69449ef7c02e8e71183d1719ab42", "GitHub App token action must use the reviewed SHA")
  assert(token["with"] == {
    "app-id" => "${{ vars.TAP_GITHUB_APP_ID }}",
    "private-key" => "${{ secrets.TAP_GITHUB_APP_PRIVATE_KEY }}",
    "owner" => "sonim1",
    "repositories" => "homebrew-tap",
    "permission-contents" => "write"
  }, "tap token must be scoped only to contents: write on homebrew-tap")
  dispatch = notify_steps.fetch("Notify Homebrew tap")
  assert_default_success_guard(dispatch, "Notify Homebrew tap")
  assert(dispatch["shell"] == "bash", "tap notification must explicitly use bash")
  assert(dispatch["env"] == { "TAP_GH_TOKEN" => "${{ steps.tap-token.outputs.token }}" }, "tap notification may receive only the installation token")
  assert(dispatch["run"] == 'scripts/dispatch-homebrew-update.sh "$RELEASE_TAG"', "tap notification command must be exact")
  %w[
    build-direct-distribution.sh
    generate-appcast.sh
    generate-release-manifest.sh
    publish-update.sh
    publish-release.sh
    APPLE_CERTIFICATE
    APPLE_NOTARY
    SPARKLE_PRIVATE
    R2_ACCESS
    CLOUDFLARE
  ].each do |forbidden|
    assert(!notify.to_s.include?(forbidden), "notify must not build, sign, notarize, or publish: #{forbidden}")
  end
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def insert_after_named_step(job, existing_name, new_step)
  steps = job.fetch("steps")
  position = steps.index { |step| step["name"] == existing_name }
  assert(!position.nil?, "cannot mutate missing step: #{existing_name}")
  steps.insert(position + 1, new_step)
end

def swap_named_steps(job, first_name, second_name)
  steps = job.fetch("steps")
  first_position = steps.index { |step| step["name"] == first_name }
  second_position = steps.index { |step| step["name"] == second_name }
  assert(!first_position.nil? && !second_position.nil?, "cannot reorder missing critical steps")
  steps[first_position], steps[second_position] = steps[second_position], steps[first_position]
end

def assert_rejects_mutation(label)
  yield
rescue RuntimeError => error
  raise unless error.message.start_with?("FAIL:")
else
  raise "FAIL: workflow contract accepted adversarial mutation: #{label}"
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

assert(workflow["permissions"] == { "contents" => "read" }, "workflow must default to contents: read")
assert(workflow["concurrency"] == {
  "group" => "switchtab-release",
  "cancel-in-progress" => false,
  "queue" => "max"
}, "release concurrency must serialize and preserve all three rapid dispatches with a non-cancelling max queue")

jobs = workflow.fetch("jobs")
assert(jobs.keys == %w[verify release notify], "workflow must contain verify, release, and notify jobs")
verify = jobs.fetch("verify")
release = jobs.fetch("release")
notify_job = jobs.fetch("notify")

assert(verify["runs-on"] == "macos-26", "verify job must run on macos-26")
assert(verify["timeout-minutes"].is_a?(Integer) && verify["timeout-minutes"].between?(1, 60), "verify timeout must be bounded")
assert(verify["permissions"] == { "contents" => "read" }, "verify must receive only contents: read")
assert(!verify.key?("environment"), "verify must not use a protected production environment")
assert(verify.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "verify RELEASE_TAG must resolve push and manual tags")
assert(verify.dig("outputs", "release_commit") == "${{ steps.provenance.outputs.release_commit }}", "verify must expose the provenance commit exactly")
assert(!verify.to_s.include?("secrets."), "verify must not receive production secrets")
%w[
  APPLE_CERTIFICATE
  APPLE_NOTARY
  SPARKLE_PRIVATE
  R2_ACCESS
  CLOUDFLARE
  create-github-app-token
  build-direct-distribution.sh
  generate-appcast.sh
  publish-update.sh
  publish-release.sh
].each do |forbidden|
  assert(!verify.to_s.include?(forbidden), "verify must not activate production operation #{forbidden}")
end

verify_steps = verify.fetch("steps")
verify_names = verify_steps.map { |step| step["name"] }
verify_order = [
  "Checkout release tag",
  "Validate release tag and provenance",
  "Setup Node.js",
  "Install release tooling",
  "Run release contract tests",
  "Run Swift tests",
  "Build unsigned Debug app"
]
verify_positions = verify_order.map { |name| verify_names.index(name) }
assert(verify_positions.none?(&:nil?) && verify_positions == verify_positions.sort, "verify steps are missing or out of order")

verify_checkout = verify_steps.fetch(verify_names.index("Checkout release tag"))
assert(verify_checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "verify checkout must use the approved full SHA")
assert(verify_checkout.dig("with", "ref") == "refs/tags/${{ env.RELEASE_TAG }}", "verify checkout must use the fully qualified release tag ref")
assert(verify_checkout.dig("with", "fetch-depth") == 0, "verify checkout must fetch complete history")
assert(verify_checkout.dig("with", "persist-credentials") == false, "verify checkout credentials must not persist")

provenance_step = verify_steps.fetch(verify_names.index("Validate release tag and provenance"))
assert(provenance_step["id"] == "provenance", "provenance step must have the stable provenance id")
validation = provenance_step.fetch("run")
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
assert(validation.include?("CURRENT_PROJECT_VERSION"), "project build version validation is missing")
assert(validation.include?('build_version = $3; found = 1'), "project build version extraction is missing")
assert(validation.include?('^([0-9]+)([.][0-9]+){0,2}$'), "project build version must use one to three numeric components")
assert(!validation.include?("print $3; exit"), "MARKETING_VERSION extraction must consume xcodebuild output under pipefail")
assert(validation.include?("if ! git rev-parse --verify origin/main"), "origin/main must be checked before any fallback fetch")
assert(validation.include?("git fetch --no-tags origin"), "unauthenticated origin/main fallback fetch is missing")
assert(validation.include?("refs/heads/main:refs/remotes/origin/main"), "origin/main fallback fetch must update only the main remote-tracking ref")
assert(validation.include?("git merge-base --is-ancestor HEAD origin/main"), "main ancestry validation is missing")
assert(validation.include?('"$tag_commit" =~ ^[0-9a-f]{40}$'), "provenance commit must be exact lowercase 40-hex")
assert(validation.include?("printf 'release_commit=%s\\n' \"$tag_commit\" >> \"$GITHUB_OUTPUT\""), "provenance must emit the exact tag commit")

setup_node = verify_steps.fetch(verify_names.index("Setup Node.js"))
assert(setup_node["uses"] == "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020", "setup-node must use the approved full SHA")
assert(setup_node.dig("with", "node-version") == "24.18.0", "setup-node must pin the current Node 24 LTS patch")
tooling = verify_steps.fetch(verify_names.index("Install release tooling")).fetch("run")
assert(tooling.include?("npm ci --ignore-scripts"), "release tooling must use npm ci --ignore-scripts")
contracts = verify_steps.fetch(verify_names.index("Run release contract tests")).fetch("run")
expected_contract_tests = %w[
  scripts/tests/release-tooling-test.sh
  scripts/tests/release-local-test.sh
  scripts/tests/generate-appcast-test.sh
  scripts/tests/generate-release-manifest-test.sh
  scripts/tests/setup-update-hosting-test.sh
  scripts/tests/publish-update-test.sh
  scripts/tests/publish-release-test.sh
  scripts/tests/dispatch-homebrew-update-test.sh
  scripts/tests/release-workflow-test.sh
  scripts/tests/plan-release-test.sh
  scripts/tests/automatic-release-workflow-test.sh
]
assert(contracts.scan(%r{scripts/tests/[a-z0-9-]+-test\.sh}) == expected_contract_tests, "release verify must run the exact eleven release contract tests")
assert(verify_steps.fetch(verify_names.index("Run Swift tests")).fetch("run").include?("swift test"), "Swift tests are missing")
unsigned_build = verify_steps.fetch(verify_names.index("Build unsigned Debug app")).fetch("run")
%w[xcodebuild SwitchTab.xcodeproj SwitchTab Debug arm64 CODE_SIGNING_ALLOWED=NO].each do |token|
  assert(unsigned_build.include?(token), "unsigned Xcode build is missing #{token}")
end
assert(unsigned_build.include?("DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"), "unsigned build must select Xcode.app")

assert(release["needs"] == "verify", "release must depend only on verify")
assert(release["environment"] == "release", "release must use the protected release environment")
assert(release["permissions"] == { "contents" => "write" }, "release must receive only contents: write")
assert(release["runs-on"] == "macos-26", "release job must run on macos-26")
assert(release["timeout-minutes"].is_a?(Integer) && release["timeout-minutes"].between?(1, 90), "release timeout must be bounded")
assert(release.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "release RELEASE_TAG must resolve push and manual tags")
assert(release.dig("env", "NOTARYTOOL_KEYCHAIN_PROFILE") == "switchtab-ci-notary", "CI notary profile must be fixed")

steps = release.fetch("steps")
names = steps.map { |step| step["name"] }
expected_release_steps = [
  "Checkout verified release commit",
  "Verify release commit",
  "Prepare signing workspace",
  "Install Apple credentials",
  "Build notarized DMG",
  "Generate signed appcast",
  "Generate release manifest",
  "Publish release",
  "Cleanup Apple credentials"
]
assert(names == expected_release_steps, "protected release semantic step list must be exact")

release_checkout = steps.fetch(names.index("Checkout verified release commit"))
assert(release_checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "release checkout must use the approved full SHA")
assert(release_checkout.dig("with", "ref") == "${{ needs.verify.outputs.release_commit }}", "release checkout must use only the verified commit")
assert(release_checkout.dig("with", "fetch-depth") == 0, "release checkout must fetch complete history")
assert(release_checkout.dig("with", "persist-credentials") == false, "release checkout credentials must not persist")
assert(!release_checkout.dig("with", "ref").include?("tags"), "protected release must not check out a mutable tag ref")

commit_check = steps.fetch(names.index("Verify release commit"))
assert(commit_check.dig("env", "VERIFIED_RELEASE_COMMIT") == "${{ needs.verify.outputs.release_commit }}", "release commit check must receive the verified output")
commit_check_run = commit_check.fetch("run")
assert(commit_check_run.include?('"$VERIFIED_RELEASE_COMMIT" =~ ^[0-9a-f]{40}$'), "release commit check must reject malformed provenance")
assert(commit_check_run.include?('head_commit="$(git rev-parse HEAD)"'), "release commit check must resolve HEAD")
assert(commit_check_run.include?('[[ "$head_commit" != "$VERIFIED_RELEASE_COMMIT" ]]'), "release commit check must fail closed on mismatch")

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
assert(appcast.dig("env", "UPDATE_DOMAIN") == "updates.switchtab.royjen.com", "appcast generation must use the production update domain")

manifest = steps.fetch(names.index("Generate release manifest"))
assert(manifest.fetch("shell") == "bash", "manifest generation must explicitly use bash")
assert(manifest.fetch("run") == 'scripts/generate-release-manifest.sh "$RELEASE_TAG"', "manifest generation must receive the validated tag")

publish = steps.fetch(names.index("Publish release"))
assert(publish.fetch("run") == "scripts/publish-release.sh \"$RELEASE_TAG\"", "release publisher command must be exact")
publish_env = publish.fetch("env")
expected_publish_env = {
  "GH_TOKEN" => "${{ github.token }}",
  "CLOUDFLARE_ACCOUNT_ID" => "${{ vars.CLOUDFLARE_ACCOUNT_ID }}",
  "R2_ACCESS_KEY_ID" => "${{ secrets.R2_ACCESS_KEY_ID }}",
  "R2_SECRET_ACCESS_KEY" => "${{ secrets.R2_SECRET_ACCESS_KEY }}",
  "R2_BUCKET_NAME" => "switchtab",
  "UPDATE_DOMAIN" => "updates.switchtab.royjen.com"
}
assert(publish_env == expected_publish_env, "publish step environment is incomplete or overprivileged")
assert(!workflow_source.include?("CLOUDFLARE_ZONE_ID"), "release workflow must not receive zone credentials")

assert(notify_job["needs"] == %w[verify release], "notify must depend on both verified provenance and public release success")
assert(notify_job["if"] == "${{ vars.ENABLE_HOMEBREW_NOTIFY == 'true' }}", "notify must be explicitly enabled by a repository variable")
assert(notify_job["environment"] == "release", "notify must use the protected release environment")
assert(notify_job["permissions"] == { "contents" => "read" }, "notify must receive only contents: read")
assert(notify_job["runs-on"] == "ubuntu-latest", "notify job must use the narrow Linux runner")
assert(notify_job["timeout-minutes"].is_a?(Integer) && notify_job["timeout-minutes"].between?(1, 15), "notify timeout must be bounded")
assert(notify_job.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "notify RELEASE_TAG must resolve push and manual tags")

notify_steps = notify_job.fetch("steps")
notify_names = notify_steps.map { |step| step["name"] }
assert(notify_names == [
  "Checkout verified release commit",
  "Verify release commit",
  "Create tap GitHub App token",
  "Notify Homebrew tap"
], "notify semantic step list must be exact")
notify_checkout = steps_by_name(notify_job, "notify").fetch("Checkout verified release commit")
assert(notify_checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "notify checkout must use the approved full SHA")
assert(notify_checkout.dig("with", "ref") == "${{ needs.verify.outputs.release_commit }}", "notify checkout must use only the verified commit")
assert(notify_checkout.dig("with", "persist-credentials") == false, "notify checkout credentials must not persist")
notify_commit_check = steps_by_name(notify_job, "notify").fetch("Verify release commit")
assert(notify_commit_check.dig("env", "VERIFIED_RELEASE_COMMIT") == "${{ needs.verify.outputs.release_commit }}", "notify commit check must receive the verified output")
notify_commit_check_run = notify_commit_check.fetch("run")
assert(notify_commit_check_run.include?('"$VERIFIED_RELEASE_COMMIT" =~ ^[0-9a-f]{40}$'), "notify commit check must reject malformed provenance")
assert(notify_commit_check_run.include?('head_commit="$(git rev-parse HEAD)"'), "notify commit check must resolve HEAD")
assert(notify_commit_check_run.include?('[[ "$head_commit" != "$VERIFIED_RELEASE_COMMIT" ]]'), "notify commit check must fail closed on mismatch")

validate_publication_and_notification(release, notify_job)

mutation = deep_copy(jobs)
steps_by_name(mutation.fetch("release"), "mutated release").fetch("Publish release")["run"] = ":"
assert_rejects_mutation("no-op publish command") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }

%w[Publish\ release].each do |step_name|
  %w[continue-on-error if].each do |bypass|
    mutation = deep_copy(jobs)
    steps_by_name(mutation.fetch("release"), "mutated release").fetch(step_name)[bypass] = bypass == "if" ? "always()" : true
    assert_rejects_mutation("#{step_name} #{bypass}") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }
  end
end
%w[Create\ tap\ GitHub\ App\ token Notify\ Homebrew\ tap].each do |step_name|
  %w[continue-on-error if].each do |bypass|
    mutation = deep_copy(jobs)
    steps_by_name(mutation.fetch("notify"), "mutated notify").fetch(step_name)[bypass] = bypass == "if" ? "always()" : true
    assert_rejects_mutation("#{step_name} #{bypass}") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }
  end
end

mutation = deep_copy(jobs)
insert_after_named_step(mutation.fetch("release"), "Publish release", { "name" => "Unpublish release", "run" => "gh release delete \"$RELEASE_TAG\"" })
assert_rejects_mutation("release edit after publication") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }

mutation = deep_copy(jobs)
insert_after_named_step(mutation.fetch("notify"), "Create tap GitHub App token", { "name" => "Redraft release", "run" => "gh release edit --draft \"$RELEASE_TAG\"" })
assert_rejects_mutation("release edit between token and dispatch") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }

[
  ["release", "Publish release"],
  ["notify", "Create tap GitHub App token"],
  ["notify", "Notify Homebrew tap"]
].each do |job_name, step_name|
  mutation = deep_copy(jobs)
  duplicate = deep_copy(steps_by_name(mutation.fetch(job_name), "mutated #{job_name}").fetch(step_name))
  mutation.fetch(job_name).fetch("steps") << duplicate
  assert_rejects_mutation("duplicate #{step_name}") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }
end

mutation = deep_copy(jobs)
swap_named_steps(mutation.fetch("release"), "Generate release manifest", "Publish release")
assert_rejects_mutation("reordered publication") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }

mutation = deep_copy(jobs)
swap_named_steps(mutation.fetch("notify"), "Create tap GitHub App token", "Notify Homebrew tap")
assert_rejects_mutation("reordered token and dispatch") { validate_publication_and_notification(mutation.fetch("release"), mutation.fetch("notify")) }

all_uses_steps = (verify_steps + steps + notify_steps).select { |step| step.key?("uses") }
assert(all_uses_steps.length == 5, "only verify/release/notify checkout, setup-node, and GitHub App token actions are allowed")
all_uses_steps.each do |step|
  assert(step["uses"].match?(%r{\A[^@]+@[0-9a-f]{40}\z}), "all actions must be SHA-pinned")
end

all_secret_references = workflow_source.scan(/secrets\.([A-Z0-9_]+)/).flatten.uniq.sort
expected_secret_references = (apple_secrets + %w[
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  SPARKLE_PRIVATE_ED_KEY
  TAP_GITHUB_APP_PRIVATE_KEY
]).sort
assert(all_secret_references == expected_secret_references, "workflow secret set is incomplete or overprivileged")
assert(!release.to_s.include?("TAP_GITHUB_APP_PRIVATE_KEY"), "tap private key must not be available to release")
assert(notify_job.to_s.scan(/secrets\.([A-Z0-9_]+)/).flatten == ["TAP_GITHUB_APP_PRIVATE_KEY"], "notify may receive only the tap private key secret")
release_secret_names = release.to_s.scan(/secrets\.([A-Z0-9_]+)/).flatten.uniq.sort
assert(release_secret_names == (expected_secret_references - ["TAP_GITHUB_APP_PRIVATE_KEY"]).sort, "Apple, Sparkle, and R2 secrets must stay in release")

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
RELEASE_COMMIT_CHECK_HARNESS="$TEMP_ROOT/verify-release-commit.sh"
NOTIFY_COMMIT_CHECK_HARNESS="$TEMP_ROOT/verify-notify-commit.sh"
mkdir -p "$FAKE_BIN"

extract_workflow_step() {
    local job_name="$1"
    local step_name="$2"
    local destination="$3"

    /usr/bin/ruby - "$WORKFLOW_PATH" "$job_name" "$step_name" > "$destination" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
job_name = ARGV.fetch(1)
step_name = ARGV.fetch(2)
step = workflow.fetch("jobs").fetch(job_name).fetch("steps").find { |entry| entry["name"] == step_name }
raise "missing workflow step: #{step_name}" unless step

puts "#!/usr/bin/env bash"
puts step.fetch("run")
RUBY
    chmod +x "$destination"
}

extract_workflow_step release "Prepare signing workspace" "$PREPARE_HARNESS"
extract_workflow_step release "Cleanup Apple credentials" "$CLEANUP_HARNESS"
extract_workflow_step verify "Validate release tag and provenance" "$VALIDATION_SOURCE"
extract_workflow_step release "Verify release commit" "$RELEASE_COMMIT_CHECK_HARNESS"
extract_workflow_step notify "Verify release commit" "$NOTIFY_COMMIT_CHECK_HARNESS"

{
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    /usr/bin/awk '
        /tag_ref="refs\/tags\/\$RELEASE_TAG"/ { capture = 1 }
        capture { print }
        capture && /tag_commit=.*git rev-parse/ { exit }
    ' "$VALIDATION_SOURCE"
    # shellcheck disable=SC2016 # Writes literal shell source into the harness.
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

# Both protected jobs must accept only the exact verified commit and fail closed otherwise.
commit_check_harnesses=("$RELEASE_COMMIT_CHECK_HARNESS" "$NOTIFY_COMMIT_CHECK_HARNESS")
for commit_check_harness in "${commit_check_harnesses[@]}"; do
    (
        cd -- "$TAG_REPOSITORY"
        VERIFIED_RELEASE_COMMIT="$TAG_COMMIT" /bin/bash "$commit_check_harness"
    )
    set +e
    output="$(cd -- "$TAG_REPOSITORY" && VERIFIED_RELEASE_COMMIT="$BRANCH_COMMIT" /bin/bash "$commit_check_harness" 2>&1)"
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || fail "protected job accepted a mismatched verified commit"
    set +e
    output="$(cd -- "$TAG_REPOSITORY" && VERIFIED_RELEASE_COMMIT='refs/tags/v1.2' /bin/bash "$commit_check_harness" 2>&1)"
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || fail "protected job accepted non-commit provenance"
done

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

# Actual builds must repair every nested Sparkle signature with the required
# trusted identity. Local signing must explicitly disable timestamps, while
# the release path must keep its Developer ID identity and trusted timestamp.
SIGNING_FIXTURE_ROOT="$TEMP_ROOT/direct-signing"
SIGNING_BIN="$SIGNING_FIXTURE_ROOT/bin"
SIGNING_LOG="$SIGNING_FIXTURE_ROOT/codesign.log"
mkdir -p "$SIGNING_BIN"

cat > "$SIGNING_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CODESIGN_LOG"
EOF
chmod +x "$SIGNING_BIN/codesign"

cat > "$SIGNING_BIN/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${XCODEBUILD_LOG:-}" ]]; then
    printf 'invoked\n' >> "$XCODEBUILD_LOG"
fi

derived_data_path=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        -derivedDataPath)
            derived_data_path="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

[[ -n "$derived_data_path" ]]
app_path="$derived_data_path/Build/Products/Release/SwitchTab.app"
sparkle_current="$app_path/Contents/Frameworks/Sparkle.framework/Versions/Current"
mkdir -p "$sparkle_current/XPCServices" "$sparkle_current/Updater.app"
touch \
    "$sparkle_current/Autoupdate" \
    "$sparkle_current/XPCServices/Downloader.xpc" \
    "$sparkle_current/XPCServices/Installer.xpc"
EOF
chmod +x "$SIGNING_BIN/xcodebuild"

MISSING_IDENTITY_BUILD_ROOT="$SIGNING_FIXTURE_ROOT/missing-identity"
MISSING_IDENTITY_XCODEBUILD_LOG="$SIGNING_FIXTURE_ROOT/missing-identity-xcodebuild.log"
set +e
missing_identity_output="$(
    CODESIGN_BIN="$SIGNING_BIN/codesign" \
    CODESIGN_LOG="$SIGNING_LOG" \
    DIRECT_BUILD_ROOT="$MISSING_IDENTITY_BUILD_ROOT" \
    SPARKLE_PUBLIC_ED_KEY='fixture-public-key' \
    DEVELOPER_ID_APPLICATION='' \
    XCODEBUILD_LOG="$MISSING_IDENTITY_XCODEBUILD_LOG" \
    PATH="$SIGNING_BIN:$PATH" \
    CONFIGURATION=Release \
    bash "$BUILDER_PATH" 2>&1
)"
missing_identity_status=$?
set -e
[[ "$missing_identity_status" -eq 64 ]] || \
    fail "actual local build without Developer ID was not rejected: status=$missing_identity_status output=$missing_identity_output"
[[ "$missing_identity_output" == *"DEVELOPER_ID_APPLICATION is required"* ]] || \
    fail "missing Developer ID rejection did not identify the required variable: $missing_identity_output"
[[ ! -e "$MISSING_IDENTITY_XCODEBUILD_LOG" ]] || \
    fail "missing Developer ID was discovered only after xcodebuild started"

PREPARE_ONLY_ROOT="$SIGNING_FIXTURE_ROOT/prepare-only"
PREPARE_ONLY_OUTPUT="$(
    CODESIGN_BIN="$SIGNING_BIN/codesign" \
    CODESIGN_LOG="$SIGNING_LOG" \
    DIRECT_BUILD_ROOT="$PREPARE_ONLY_ROOT" \
    SPARKLE_PUBLIC_ED_KEY='fixture-public-key' \
    DEVELOPER_ID_APPLICATION='' \
    XCODEBUILD_LOG="$SIGNING_FIXTURE_ROOT/prepare-only-xcodebuild.log" \
    PATH="$SIGNING_BIN:$PATH" \
    CONFIGURATION=Release \
    bash "$BUILDER_PATH" --prepare-only
)"
[[ "$PREPARE_ONLY_OUTPUT" == *"Prepared direct distribution workspace:"* ]] || \
    fail "prepare-only unexpectedly required a Developer ID identity: $PREPARE_ONLY_OUTPUT"

LOCAL_BUILD_ROOT="$SIGNING_FIXTURE_ROOT/local-build"
: > "$SIGNING_LOG"
CODESIGN_BIN="$SIGNING_BIN/codesign" \
CODESIGN_LOG="$SIGNING_LOG" \
DIRECT_BUILD_ROOT="$LOCAL_BUILD_ROOT" \
SPARKLE_PUBLIC_ED_KEY='fixture-public-key' \
DEVELOPER_ID_APPLICATION='Developer ID Application: Fixture (TEAM)' \
PATH="$SIGNING_BIN:$PATH" \
CONFIGURATION=Release \
bash "$BUILDER_PATH"

LOCAL_APP_PATH="$LOCAL_BUILD_ROOT/DerivedData/Build/Products/Release/SwitchTab.app"
LOCAL_SPARKLE_CURRENT="$LOCAL_APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/Current"
expected_local_signing=$(cat <<EOF
--force --options runtime --timestamp=none --sign Developer ID Application: Fixture (TEAM) $LOCAL_SPARKLE_CURRENT/Autoupdate
--force --options runtime --timestamp=none --sign Developer ID Application: Fixture (TEAM) $LOCAL_SPARKLE_CURRENT/Updater.app
--force --options runtime --timestamp=none --sign Developer ID Application: Fixture (TEAM) $LOCAL_SPARKLE_CURRENT/XPCServices/Downloader.xpc
--force --options runtime --timestamp=none --sign Developer ID Application: Fixture (TEAM) $LOCAL_SPARKLE_CURRENT/XPCServices/Installer.xpc
--force --options runtime --timestamp=none --sign Developer ID Application: Fixture (TEAM) $LOCAL_APP_PATH/Contents/Frameworks/Sparkle.framework
--force --options runtime --timestamp=none --sign Developer ID Application: Fixture (TEAM) $LOCAL_APP_PATH
--verify --deep --strict --verbose=2 $LOCAL_APP_PATH
EOF
)
[[ "$(<"$SIGNING_LOG")" == "$expected_local_signing" ]] || \
    fail "local direct build did not re-sign Sparkle in order: $(<"$SIGNING_LOG")"
[[ "$(<"$SIGNING_LOG")" != *"--timestamp --sign"* ]] || \
    fail "local direct build requested a trusted signing timestamp"

SIGNING_FUNCTION_HARNESS="$TEMP_ROOT/signing-functions.sh"
{
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' 'RELEASE="${RELEASE:-0}"' 'DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"' 'CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"'
    /usr/bin/awk '
        /^sign_code\(\)/ { capture = 1 }
        capture && /^while \[\[/ { exit }
        capture { print }
    ' "$BUILDER_PATH"
    printf '%s\n' 'sign_app_bundle "$APP_PATH"'
} > "$SIGNING_FUNCTION_HARNESS"
chmod +x "$SIGNING_FUNCTION_HARNESS"

RELEASE_APP_PATH="$SIGNING_FIXTURE_ROOT/release/SwitchTab.app"
RELEASE_SPARKLE_CURRENT="$RELEASE_APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/Current"
mkdir -p "$RELEASE_SPARKLE_CURRENT/XPCServices" "$RELEASE_SPARKLE_CURRENT/Updater.app"
touch \
    "$RELEASE_SPARKLE_CURRENT/Autoupdate" \
    "$RELEASE_SPARKLE_CURRENT/XPCServices/Downloader.xpc" \
    "$RELEASE_SPARKLE_CURRENT/XPCServices/Installer.xpc"
: > "$SIGNING_LOG"
APP_PATH="$RELEASE_APP_PATH" \
RELEASE=1 \
DEVELOPER_ID_APPLICATION='Developer ID Application: Fixture (TEAM)' \
CODESIGN_BIN="$SIGNING_BIN/codesign" \
CODESIGN_LOG="$SIGNING_LOG" \
bash "$SIGNING_FUNCTION_HARNESS"

expected_release_signing=$(cat <<EOF
--force --options runtime --timestamp --sign Developer ID Application: Fixture (TEAM) $RELEASE_SPARKLE_CURRENT/Autoupdate
--force --options runtime --timestamp --sign Developer ID Application: Fixture (TEAM) $RELEASE_SPARKLE_CURRENT/Updater.app
--force --options runtime --timestamp --sign Developer ID Application: Fixture (TEAM) $RELEASE_SPARKLE_CURRENT/XPCServices/Downloader.xpc
--force --options runtime --timestamp --sign Developer ID Application: Fixture (TEAM) $RELEASE_SPARKLE_CURRENT/XPCServices/Installer.xpc
--force --options runtime --timestamp --sign Developer ID Application: Fixture (TEAM) $RELEASE_APP_PATH/Contents/Frameworks/Sparkle.framework
--force --options runtime --timestamp --sign Developer ID Application: Fixture (TEAM) $RELEASE_APP_PATH
--verify --deep --strict --verbose=2 $RELEASE_APP_PATH
EOF
)
[[ "$(<"$SIGNING_LOG")" == "$expected_release_signing" ]] || \
    fail "release signing no longer preserves Developer ID/timestamp behavior: $(<"$SIGNING_LOG")"

/usr/bin/ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)' "$WORKFLOW_PATH"
bash -n "$BUILDER_PATH"
bash -n "$0"

echo "release workflow contract tests passed"
