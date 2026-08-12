#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_PATH="$PROJECT_ROOT/.github/workflows/landing-deploy.yml"

[[ -f "$WORKFLOW_PATH" ]] || {
  echo 'FAIL: missing .github/workflows/landing-deploy.yml' >&2
  exit 1
}

/usr/bin/ruby - "$WORKFLOW_PATH" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)

def assert(condition, message)
  raise "FAIL: #{message}" unless condition
end

assert(workflow["name"] == "Deploy landing page", "workflow name must identify landing deployment")
assert(workflow.fetch("on") == {
  "push" => {
    "branches" => ["main"],
    "paths" => ["docs/**"],
  },
}, "deployment must run only for docs changes pushed to main")
assert(workflow["permissions"] == {"contents" => "read"}, "workflow permissions must be read-only")
assert(workflow.fetch("concurrency") == {
  "group" => "switchtab-landing-${{ github.ref }}",
  "cancel-in-progress" => true,
}, "deployment concurrency must cancel stale runs")

job = workflow.fetch("jobs").fetch("deploy")
assert(job["runs-on"] == "ubuntu-latest", "deployment must use ubuntu-latest")
assert(job["timeout-minutes"] == 10, "deployment timeout must be bounded")
steps = job.fetch("steps")
checkout = steps.find { |step| step["uses"]&.start_with?("actions/checkout@") }
node = steps.find { |step| step["uses"]&.start_with?("actions/setup-node@") }
deploy = steps.find { |step| step["name"] == "Deploy to Cloudflare Pages" }
assert(checkout && checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "checkout must use the pinned project version")
assert(node && node["uses"] == "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020", "setup-node must use the pinned project version")
assert(node.fetch("with")["node-version"] == "24.18.0", "Node version must be pinned")
assert(deploy, "deployment step must exist")
assert(deploy.fetch("env")["CLOUDFLARE_API_TOKEN"] == "${{ secrets.CLOUDFLARE_API_TOKEN }}", "Cloudflare token must come from a GitHub secret")
assert(deploy.fetch("env")["CLOUDFLARE_ACCOUNT_ID"] == "${{ vars.CLOUDFLARE_ACCOUNT_ID }}", "Cloudflare account must be passed explicitly: a Pages-scoped token cannot enumerate accounts")
command = deploy.fetch("run")
assert(command.include?("npx wrangler pages deploy docs"), "deployment must publish docs")
assert(command.include?("--project-name switchtab-landing"), "deployment must target switchtab-landing")
assert(command.include?("--commit-hash \"$GITHUB_SHA\""), "deployment must attach the triggering commit")
assert(!command.include?("--commit-dirty"), "CI deployment must not allow dirty files")
puts "landing deploy workflow contract passed"
RUBY
