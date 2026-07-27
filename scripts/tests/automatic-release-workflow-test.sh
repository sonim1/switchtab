#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CI_WORKFLOW_PATH="$PROJECT_ROOT/.github/workflows/ci.yml"
AUTOMATIC_WORKFLOW_PATH="$PROJECT_ROOT/.github/workflows/automatic-release.yml"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

missing_workflows=()
[[ -f "$CI_WORKFLOW_PATH" ]] || missing_workflows+=(".github/workflows/ci.yml")
[[ -f "$AUTOMATIC_WORKFLOW_PATH" ]] || missing_workflows+=(".github/workflows/automatic-release.yml")
[[ "${#missing_workflows[@]}" -eq 0 ]] || fail "missing workflows: ${missing_workflows[*]}"

/usr/bin/ruby - "$CI_WORKFLOW_PATH" "$AUTOMATIC_WORKFLOW_PATH" <<'RUBY'
require "yaml"

ci_path, automatic_path = ARGV
ci_source = File.read(ci_path)
automatic_source = File.read(automatic_path)
ci = YAML.safe_load(ci_source, permitted_classes: [], permitted_symbols: [], aliases: false)
automatic = YAML.safe_load(automatic_source, permitted_classes: [], permitted_symbols: [], aliases: false)

CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
SETUP_NODE_ACTION = "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020"
RELEASE_CONDITION = "${{ steps.release-plan.outputs.release == 'true' }}"

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

def assert_sha_pinned_actions(workflow, expected, label)
  actions = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
    .map { |step| step["uses"] }.compact
  assert(actions == expected, "#{label} action list must be exact")
  actions.each do |action|
    assert(action.match?(%r{\A[^@]+@[0-9a-f]{40}\z}), "#{label} actions must use reviewed full SHAs")
  end
end

def assert_no_release_secrets(source, label)
  assert(source.scan(/secrets\.([A-Z0-9_]+)/).empty?, "#{label} must not read repository secrets")
  forbidden = %w[
    APPLE_CERTIFICATE_P12_BASE64
    APPLE_CERTIFICATE_PASSWORD
    APPLE_NOTARY_KEY_P8_BASE64
    APPLE_NOTARY_KEY_ID
    APPLE_NOTARY_ISSUER_ID
    SPARKLE_PRIVATE_ED_KEY
    R2_ACCESS_KEY_ID
    R2_SECRET_ACCESS_KEY
    TAP_GITHUB_APP_PRIVATE_KEY
  ]
  referenced = forbidden.select { |name| source.include?(name) }
  assert(referenced.empty?, "#{label} contains release credential names: #{referenced.join(', ')}")
end

assert(ci["name"] == "CI", "PR workflow name must be CI")
assert(ci.fetch("on") == {
  "pull_request" => { "types" => %w[opened reopened synchronize labeled unlabeled] },
}, "CI must run only for the supported pull_request activity types")
assert(ci["permissions"] == { "contents" => "read" }, "CI workflow permissions must be exactly contents: read")
assert(ci.fetch("jobs").keys == %w[policy version verify], "CI must contain policy, version, and verify jobs")

ci_job = ci.fetch("jobs").fetch("verify")
assert(ci_job["runs-on"] == "macos-26", "CI must run on macos-26")
assert(ci_job["permissions"] == { "contents" => "read" }, "CI job permissions must be exactly contents: read")
assert(ci_job["timeout-minutes"].is_a?(Integer) && ci_job["timeout-minutes"].between?(1, 45), "CI timeout must be bounded")

ci_names = ci_job.fetch("steps").map { |step| step["name"] }
assert(ci_names == [
  "Checkout pull request head",
  "Validate release plan",
  "Setup Node.js",
  "Install release tooling",
  "Run release contract tests",
  "Run Swift tests",
  "Build unsigned Debug app"
], "CI semantic step list must be exact")
ci_steps = steps_by_name(ci_job, "CI")

ci_checkout = ci_steps.fetch("Checkout pull request head")
assert(ci_checkout["uses"] == CHECKOUT_ACTION, "CI checkout must use the existing reviewed SHA")
assert(ci_checkout["with"] == {
  "ref" => "${{ github.event.pull_request.head.sha }}",
  "fetch-depth" => 0,
  "persist-credentials" => false
}, "CI checkout must use the exact PR head with full history and no retained credentials")

ci_plan = ci_steps.fetch("Validate release plan")
assert(ci_plan["id"] == "release-plan", "CI planner must expose release-plan outputs")
assert(ci_plan["shell"] == "bash", "CI planner must explicitly use bash")
assert(ci_plan["env"] == {
  "BASE_SHA" => "${{ github.event.pull_request.base.sha }}",
  "HEAD_SHA" => "${{ github.event.pull_request.head.sha }}"
}, "CI planner must receive exact PR base and head SHAs")
assert(ci_plan["run"] == 'scripts/plan-release.sh "$BASE_SHA" "$HEAD_SHA" "$GITHUB_OUTPUT"', "CI planner must write directly to GITHUB_OUTPUT")

ci_node = ci_steps.fetch("Setup Node.js")
assert(ci_node["uses"] == SETUP_NODE_ACTION, "CI setup-node must use the existing reviewed SHA")
assert(ci_node["with"] == { "node-version" => "24.18.0" }, "CI Node.js version must match release verification")

ci_install = ci_steps.fetch("Install release tooling")
assert(ci_install["shell"] == "bash", "CI tooling install must explicitly use bash")
assert(ci_install["run"] == "npm ci --ignore-scripts", "CI tooling install command must be exact")

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
  scripts/tests/prepare-pr-version-test.sh
  scripts/tests/ci-workflow-test.sh
  scripts/tests/automatic-release-workflow-test.sh
]
ci_contracts = ci_steps.fetch("Run release contract tests")
assert(ci_contracts["shell"] == "bash", "CI contract tests must explicitly use bash")
contract_source = ci_contracts.fetch("run")
assert(contract_source.include?("set -euo pipefail"), "CI contract loop must fail closed")
assert(contract_source.scan(%r{scripts/tests/[a-z0-9-]+-test\.sh}) == expected_contract_tests, "CI must run the exact thirteen release contract tests")
assert(contract_source.include?('bash "$test_script"'), "CI must execute every listed contract test with bash")

swift_test = ci_steps.fetch("Run Swift tests")
assert(swift_test == { "name" => "Run Swift tests", "shell" => "bash", "run" => "swift test" }, "CI Swift test command must be exact")

build = ci_steps.fetch("Build unsigned Debug app")
assert(build["shell"] == "bash", "CI build must explicitly use bash")
build_source = build.fetch("run")
assert(build_source.include?("set -euo pipefail"), "CI build must fail closed")
assert(build_source.include?("xcodebuild"), "CI build must invoke xcodebuild")
assert(build_source.include?("-project SwitchTab.xcodeproj"), "CI build must use SwitchTab.xcodeproj")
assert(build_source.include?("-scheme SwitchTab"), "CI build must use the SwitchTab scheme")
assert(build_source.include?("-configuration Debug"), "CI build must use Debug configuration")
assert(build_source.include?("-destination 'platform=macOS,arch=arm64'"), "CI build must target macOS arm64")
assert(build_source.include?("CODE_SIGNING_ALLOWED=NO"), "CI build must disable code signing")

assert_sha_pinned_actions(ci, [CHECKOUT_ACTION, CHECKOUT_ACTION, SETUP_NODE_ACTION], "CI")
assert_no_release_secrets(ci_source, "CI")

assert(automatic["name"] == "Automatic Release", "main workflow name must be Automatic Release")
assert(automatic.fetch("on") == { "push" => { "branches" => ["main"] } }, "automatic release must run only for pushes to main")
expected_permissions = { "contents" => "write", "actions" => "write" }
assert(automatic["permissions"] == expected_permissions, "automatic release permissions must be exactly contents: write and actions: write")
assert(automatic["concurrency"] == {
  "group" => "switchtab-automatic-release",
  "cancel-in-progress" => false,
  "queue" => "max"
}, "automatic release must use a fixed serialized, non-cancelling max queue")
assert(automatic.fetch("jobs").keys == ["release"], "automatic release must contain only the release job")

automatic_job = automatic.fetch("jobs").fetch("release")
assert(automatic_job["runs-on"] == "ubuntu-latest", "automatic release must use ubuntu-latest")
assert(automatic_job["permissions"] == expected_permissions, "automatic release job permissions must be exact")
assert(automatic_job["timeout-minutes"].is_a?(Integer) && automatic_job["timeout-minutes"].between?(1, 15), "automatic release timeout must be bounded")

automatic_names = automatic_job.fetch("steps").map { |step| step["name"] }
assert(automatic_names == [
  "Checkout pushed commit",
  "Verify pushed commit",
  "Plan release",
  "Fetch tags",
  "Create or verify annotated release tag",
  "Dispatch release workflow"
], "automatic release semantic step list must be exact")
automatic_steps = steps_by_name(automatic_job, "automatic release")

automatic_checkout = automatic_steps.fetch("Checkout pushed commit")
assert(automatic_checkout["uses"] == CHECKOUT_ACTION, "automatic release checkout must use the existing reviewed SHA")
assert(automatic_checkout["with"] == {
  "ref" => "${{ github.sha }}",
  "fetch-depth" => 0,
  "persist-credentials" => true,
  "token" => "${{ github.token }}"
}, "automatic release checkout must retain repository GITHUB_TOKEN credentials for the exact pushed commit")

verify = automatic_steps.fetch("Verify pushed commit")
assert(verify["shell"] == "bash", "pushed-commit verification must explicitly use bash")
assert(verify["env"] == { "EXPECTED_SHA" => "${{ github.sha }}" }, "pushed-commit verification must receive github.sha")
verify_source = verify.fetch("run")
assert(verify_source.include?('head_commit="$(git rev-parse HEAD)"'), "pushed-commit verification must resolve HEAD")
assert(verify_source.include?('[[ "$head_commit" != "$EXPECTED_SHA" ]]'), "pushed-commit verification must fail closed on mismatch")

automatic_plan = automatic_steps.fetch("Plan release")
assert(automatic_plan["id"] == "release-plan", "automatic planner must expose release-plan outputs")
assert(automatic_plan["shell"] == "bash", "automatic planner must explicitly use bash")
assert(automatic_plan["env"] == {
  "BASE_SHA" => "${{ github.event.before }}",
  "HEAD_SHA" => "${{ github.sha }}"
}, "automatic planner must receive the push before and head SHAs")
assert(automatic_plan["run"] == 'scripts/plan-release.sh "$BASE_SHA" "$HEAD_SHA" "$GITHUB_OUTPUT"', "automatic planner must write directly to GITHUB_OUTPUT")

%w[Fetch\ tags Create\ or\ verify\ annotated\ release\ tag Dispatch\ release\ workflow].each do |step_name|
  step = automatic_steps.fetch(step_name)
  assert(step["if"] == RELEASE_CONDITION, "#{step_name} must run only for release=true")
  assert(!step.key?("continue-on-error"), "#{step_name} must fail the job on error")
end

fetch_tags = automatic_steps.fetch("Fetch tags")
assert(fetch_tags["shell"] == "bash", "tag fetch must explicitly use bash")
assert(fetch_tags["run"] == "git fetch --force --tags origin", "automatic release must fetch tags before validation")

tag_step = automatic_steps.fetch("Create or verify annotated release tag")
assert(tag_step["shell"] == "bash", "tag step must explicitly use bash")
assert(tag_step["env"] == {
  "RELEASE_TAG" => "${{ steps.release-plan.outputs.tag }}",
  "EXPECTED_SHA" => "${{ github.sha }}"
}, "tag step must use only the planned tag and exact pushed SHA")
tag_source = tag_step.fetch("run")
assert(tag_source.include?("set -euo pipefail"), "tag handling must fail closed")
assert(tag_source.include?('tag_ref="refs/tags/$RELEASE_TAG"'), "tag handling must use an exact tag ref")
assert(tag_source.include?('git show-ref --verify --quiet "$tag_ref"'), "existing tag detection must use the exact ref")
assert(tag_source.include?('tag_object_type="$(git cat-file -t "$tag_ref")"'), "existing tag validation must inspect the Git object type")
assert(tag_source.include?('[[ "$tag_object_type" != \'tag\' ]]'), "existing lightweight tags must be rejected")
assert(tag_source.include?('tag_commit="$(git rev-parse "$tag_ref^{commit}")"'), "existing annotated tags must be peeled to a commit")
assert(tag_source.include?('[[ "$tag_commit" != "$EXPECTED_SHA" ]]'), "existing tags on another commit must be rejected")
assert(tag_source.include?("git config user.name 'github-actions[bot]'"), "tagger name must be fixed")
assert(tag_source.include?("git config user.email '41898282+github-actions[bot]@users.noreply.github.com'"), "tagger email must be fixed")
assert(tag_source.include?('git tag --annotate "$RELEASE_TAG" "$EXPECTED_SHA" --message "Release $RELEASE_TAG"'), "new tags must be annotated on the exact pushed SHA")
push_lines = tag_source.lines.map(&:strip).select { |line| line.start_with?("git push ") }
assert(push_lines == ['git push origin "$tag_ref:$tag_ref"'], "tag publication must push only the exact tag ref without force")

dispatch = automatic_steps.fetch("Dispatch release workflow")
assert(dispatch["shell"] == "bash", "release dispatch must explicitly use bash")
assert(dispatch["env"] == {
  "GH_TOKEN" => "${{ github.token }}",
  "RELEASE_TAG" => "${{ steps.release-plan.outputs.tag }}"
}, "release dispatch must use only github.token and the planned tag")
assert(dispatch["run"] == 'gh workflow run release.yml --ref main -f tag="$RELEASE_TAG"', "release dispatch command must be exact")

assert_sha_pinned_actions(automatic, [CHECKOUT_ACTION], "automatic release")
assert_no_release_secrets(automatic_source, "automatic release")
assert(!automatic_source.include?("refs/heads/main:refs/tags"), "automatic release must not turn the main branch into a tag ref")
RUBY

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-automatic-release-workflow.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
TAG_HARNESS="$TEMP_ROOT/tag-step.sh"

/usr/bin/ruby - "$AUTOMATIC_WORKFLOW_PATH" > "$TAG_HARNESS" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
step = workflow.fetch("jobs").fetch("release").fetch("steps")
  .find { |entry| entry["name"] == "Create or verify annotated release tag" }
raise "missing tag step" unless step

puts "#!/usr/bin/env bash"
puts step.fetch("run")
RUBY
chmod +x "$TAG_HARNESS"

REMOTE_REPOSITORY="$TEMP_ROOT/remote.git"
TAG_REPOSITORY="$TEMP_ROOT/repository"
git init --quiet --bare "$REMOTE_REPOSITORY"
git init --quiet "$TAG_REPOSITORY"
(
    cd -- "$TAG_REPOSITORY"
    git config user.name 'SwitchTab Test'
    git config user.email 'switchtab@example.invalid'
    git commit --allow-empty --quiet -m 'release target'
    git branch -M main
    git remote add origin "$REMOTE_REPOSITORY"
    git push --quiet --set-upstream origin main
)
EXPECTED_COMMIT="$(git -C "$TAG_REPOSITORY" rev-parse HEAD)"

# A missing target is created as an annotated tag on the exact commit and only that ref is pushed.
(
    cd -- "$TAG_REPOSITORY"
    RELEASE_TAG='v1.0.1' EXPECTED_SHA="$EXPECTED_COMMIT" /bin/bash "$TAG_HARNESS"
)
[[ "$(git --git-dir="$REMOTE_REPOSITORY" cat-file -t refs/tags/v1.0.1)" == 'tag' ]] || \
    fail 'new release tag was not annotated'
[[ "$(git --git-dir="$REMOTE_REPOSITORY" rev-parse 'refs/tags/v1.0.1^{commit}')" == "$EXPECTED_COMMIT" ]] || \
    fail 'new release tag did not resolve to the exact pushed commit'

# A rerun accepts the same annotated tag without replacing its tag object.
ORIGINAL_TAG_OBJECT="$(git -C "$TAG_REPOSITORY" rev-parse refs/tags/v1.0.1)"
(
    cd -- "$TAG_REPOSITORY"
    RELEASE_TAG='v1.0.1' EXPECTED_SHA="$EXPECTED_COMMIT" /bin/bash "$TAG_HARNESS"
)
[[ "$(git -C "$TAG_REPOSITORY" rev-parse refs/tags/v1.0.1)" == "$ORIGINAL_TAG_OBJECT" ]] || \
    fail 'rerun replaced an existing annotated tag'

# A lightweight tag must fail closed even when it resolves to the expected commit.
git -C "$TAG_REPOSITORY" tag v1.0.1-lightweight "$EXPECTED_COMMIT"
set +e
output="$(cd -- "$TAG_REPOSITORY" && RELEASE_TAG='v1.0.1-lightweight' EXPECTED_SHA="$EXPECTED_COMMIT" /bin/bash "$TAG_HARNESS" 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail 'lightweight release tag was accepted'
[[ "$output" == *'not an annotated tag'* ]] || fail "lightweight tag failure was not explicit: $output"

# An annotated tag that peels to another commit must fail closed.
(
    cd -- "$TAG_REPOSITORY"
    git commit --allow-empty --quiet -m 'conflicting target'
    git tag --annotate v1.0.1-conflict HEAD --message 'conflicting tag'
)
set +e
output="$(cd -- "$TAG_REPOSITORY" && RELEASE_TAG='v1.0.1-conflict' EXPECTED_SHA="$EXPECTED_COMMIT" /bin/bash "$TAG_HARNESS" 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail 'conflicting annotated release tag was accepted'
[[ "$output" == *'does not match the pushed commit'* ]] || fail "conflicting tag failure was not explicit: $output"

bash -n "$0"
echo 'automatic release workflow contract tests passed'
