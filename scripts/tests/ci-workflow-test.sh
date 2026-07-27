#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_PATH="$PROJECT_ROOT/.github/workflows/ci.yml"

[[ -f "$WORKFLOW_PATH" ]] || {
    echo 'FAIL: missing .github/workflows/ci.yml' >&2
    exit 1
}

/usr/bin/ruby - "$WORKFLOW_PATH" <<'RUBY'
require "yaml"

path = ARGV.fetch(0)
source = File.read(path)
workflow = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)

CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
SETUP_NODE_ACTION = "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020"
APP_TOKEN_ACTION = "actions/create-github-app-token@67018539274d69449ef7c02e8e71183d1719ab42"

def assert(condition, message)
  raise "FAIL: #{message}" unless condition
end

def steps_by_name(job)
  steps = job.fetch("steps")
  grouped = steps.group_by { |step| step["name"] }
  assert(grouped.values.all? { |entries| entries.length == 1 }, "step names must be unique")
  grouped.transform_values(&:first)
end

assert(workflow["name"] == "CI", "workflow name must remain CI")
assert(workflow.fetch("on") == {
  "pull_request" => { "types" => %w[opened reopened synchronize labeled unlabeled] },
}, "pull_request activity types must be exact")
assert(workflow["permissions"] == { "contents" => "read" }, "workflow permissions must default to contents: read")
assert(workflow["concurrency"] == {
  "group" => "switchtab-ci-${{ github.event.pull_request.number }}",
  "cancel-in-progress" => true,
}, "CI concurrency must serialize each pull request")
assert(workflow.fetch("jobs").keys == %w[policy version verify], "CI jobs and ordering must be exact")

policy = workflow.fetch("jobs").fetch("policy")
assert(policy["runs-on"] == "ubuntu-latest", "policy must run on ubuntu-latest")
assert(policy["permissions"] == { "contents" => "read" }, "policy must be read-only")
assert(policy["timeout-minutes"].is_a?(Integer) && policy["timeout-minutes"].between?(1, 5), "policy timeout must be bounded")
assert(policy["outputs"] == {
  "trusted" => "${{ steps.policy.outputs.trusted }}",
  "release_kind" => "${{ steps.policy.outputs.release_kind }}",
}, "policy outputs must be exact")
assert(policy.fetch("steps").length == 1, "policy must not check out pull-request code")
policy_step = policy.fetch("steps").first
assert(policy_step["name"] == "Evaluate versioning policy", "policy step name must be exact")
assert(policy_step["id"] == "policy", "policy step must expose outputs")
assert(policy_step["shell"] == "bash", "policy step must use bash")
assert(policy_step["env"] == {
  "BASE_REF" => "${{ github.event.pull_request.base.ref }}",
  "BASE_REPOSITORY" => "${{ github.event.pull_request.base.repo.full_name }}",
  "HEAD_REPOSITORY" => "${{ github.event.pull_request.head.repo.full_name }}",
  "AUTHOR_ASSOCIATION" => "${{ github.event.pull_request.author_association }}",
  "LABELS_JSON" => "${{ toJSON(github.event.pull_request.labels.*.name) }}",
}, "policy metadata inputs must be exact")
policy_source = policy_step.fetch("run")
assert(policy_source.include?("set -euo pipefail"), "policy must fail closed")
assert(policy_source.include?('[[ "$BASE_REF" == "main" ]]'), "policy must require main as the base")
assert(policy_source.include?('[[ "$HEAD_REPOSITORY" == "$BASE_REPOSITORY" ]]'), "policy must require a same-repository head")
assert(policy_source.include?("OWNER|MEMBER|COLLABORATOR"), "policy must enumerate trusted associations")
assert(policy_source.include?("release:minor") && policy_source.include?("release:major"), "policy must inspect both release labels")
assert(policy_source.include?("Conflicting release labels"), "policy must reject conflicting labels explicitly")
assert(!policy_source.include?("git "), "policy must not execute repository code or git commands")

version = workflow.fetch("jobs").fetch("version")
assert(version["needs"] == "policy", "version job must depend on policy")
assert(version["if"] == "${{ needs.policy.outputs.trusted == 'true' }}", "version job trust gate must be exact")
assert(version["runs-on"] == "ubuntu-latest", "version preparation must run on ubuntu-latest")
assert(version["permissions"] == { "contents" => "read" }, "version job GITHUB_TOKEN must remain read-only")
assert(version["timeout-minutes"].is_a?(Integer) && version["timeout-minutes"].between?(1, 10), "version timeout must be bounded")
assert(version["outputs"] == {
  "ready" => "${{ steps.prepare.outputs.ready }}",
  "release" => "${{ steps.prepare.outputs.release }}",
  "version" => "${{ steps.prepare.outputs.version }}",
  "build" => "${{ steps.prepare.outputs.build }}",
}, "version job outputs must be exact")

version_steps = steps_by_name(version)
assert(version_steps.keys == [
  "Create version GitHub App token",
  "Checkout exact pull request head",
  "Verify exact pull request head",
  "Prepare pull request version",
  "Commit prepared version",
], "version step list must be exact")
app_token = version_steps.fetch("Create version GitHub App token")
assert(app_token["id"] == "app-token", "GitHub App token step must expose its token")
assert(app_token["uses"] == APP_TOKEN_ACTION, "GitHub App token action must use the reviewed SHA")
assert(app_token["with"] == {
  "app-id" => "${{ vars.VERSION_GITHUB_APP_ID }}",
  "private-key" => "${{ secrets.VERSION_GITHUB_APP_PRIVATE_KEY }}",
  "owner" => "sonim1",
  "repositories" => "switchtab",
  "permission-contents" => "write",
}, "version app token must be repository-scoped and contents-only")
checkout = version_steps.fetch("Checkout exact pull request head")
assert(checkout["uses"] == CHECKOUT_ACTION, "version checkout action must use the reviewed SHA")
assert(checkout["with"] == {
  "ref" => "${{ github.event.pull_request.head.sha }}",
  "fetch-depth" => 0,
  "persist-credentials" => true,
  "token" => "${{ steps.app-token.outputs.token }}",
}, "version checkout must retain only the short-lived app token for the exact head")

head_check = version_steps.fetch("Verify exact pull request head")
assert(head_check["shell"] == "bash", "head verification must use bash")
assert(head_check["env"] == { "EXPECTED_HEAD_SHA" => "${{ github.event.pull_request.head.sha }}" }, "head verification input must be exact")
assert(head_check.fetch("run").include?('[[ "$(git rev-parse HEAD)" == "$EXPECTED_HEAD_SHA" ]]'), "version job must verify the checked-out SHA")

prepare = version_steps.fetch("Prepare pull request version")
assert(prepare["id"] == "prepare", "prepare step must expose outputs")
assert(prepare["shell"] == "bash", "prepare step must use bash")
assert(prepare["env"] == {
  "BASE_SHA" => "${{ github.event.pull_request.base.sha }}",
  "HEAD_SHA" => "${{ github.event.pull_request.head.sha }}",
  "RELEASE_KIND" => "${{ needs.policy.outputs.release_kind }}",
}, "prepare inputs must be exact")
assert(prepare["run"] == 'scripts/prepare-pr-version.sh "$BASE_SHA" "$HEAD_SHA" "$RELEASE_KIND" "$GITHUB_OUTPUT"', "prepare command must be exact")

commit = version_steps.fetch("Commit prepared version")
assert(commit["if"] == "${{ steps.prepare.outputs.changed == 'true' }}", "commit must run only after a real edit")
assert(commit["shell"] == "bash", "commit step must use bash")
assert(commit["env"] == {
  "HEAD_REF" => "${{ github.event.pull_request.head.ref }}",
  "VERSION" => "${{ steps.prepare.outputs.version }}",
  "BUILD" => "${{ steps.prepare.outputs.build }}",
}, "commit inputs must be exact")
commit_source = commit.fetch("run")
assert(commit_source.include?("set -euo pipefail"), "commit must fail closed")
assert(commit_source.include?('git add -- SwitchTab.xcodeproj/project.pbxproj'), "commit must stage only the project")
assert(commit_source.include?("git config user.name 'github-actions[bot]'"), "bot name must be fixed")
assert(commit_source.include?("git config user.email '41898282+github-actions[bot]@users.noreply.github.com'"), "bot email must be fixed")
assert(commit_source.include?('git commit -m "chore: bump version to $VERSION ($BUILD)"'), "commit message must record the target versions")
assert(commit_source.include?('git push origin "HEAD:refs/heads/$HEAD_REF"'), "version commit must push only the PR branch")
assert(!commit_source.match?(/--force(?:-with-lease)?/), "version commits must never force-push")
assert(!commit_source.match?(/git add (?:-A|\.)/), "version commits must never stage the whole worktree")

verify = workflow.fetch("jobs").fetch("verify")
assert(verify["needs"] == "version", "verify must wait for version preparation")
assert(verify["if"] == "${{ needs.version.outputs.ready == 'true' }}", "verify must run only on a ready head")
assert(verify["permissions"] == { "contents" => "read" }, "verify must remain read-only")
assert(verify["runs-on"] == "macos-26", "verify must remain on macos-26")
verify_steps = steps_by_name(verify)
assert(verify_steps.keys == [
  "Checkout pull request head",
  "Validate release plan",
  "Setup Node.js",
  "Install release tooling",
  "Run release contract tests",
  "Run Swift tests",
  "Build unsigned Debug app",
], "verify semantic steps must remain exact")

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
contract_source = verify_steps.fetch("Run release contract tests").fetch("run")
assert(contract_source.scan(%r{scripts/tests/[a-z0-9-]+-test\.sh}) == expected_contract_tests, "verify must run the exact release contract suite")

actions = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
  .map { |step| step["uses"] }.compact
assert(actions == [APP_TOKEN_ACTION, CHECKOUT_ACTION, CHECKOUT_ACTION, SETUP_NODE_ACTION], "CI action list must be exact")
actions.each { |action| assert(action.match?(%r{\A[^@]+@[0-9a-f]{40}\z}), "all actions must be SHA pinned") }
assert(source.scan(/secrets\.([A-Z0-9_]+)/).flatten.uniq == ["VERSION_GITHUB_APP_PRIVATE_KEY"], "CI may read only the scoped version app key")
assert(!source.include?("TAP_GITHUB_APP_PRIVATE_KEY"), "CI must not read the release-environment tap key")
assert(source.scan(/permissions:\s*\n\s+contents: write/).empty?, "no job GITHUB_TOKEN may receive write permission")
RUBY

echo 'ci-workflow-test: PASS'
