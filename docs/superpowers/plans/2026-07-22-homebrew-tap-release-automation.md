# Homebrew Tap Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `sonim1/homebrew-tap` securely consume allowlisted release manifests from SwitchTab and UpdateBar, validate public artifacts, update Formula/Cask files, and auto-merge a tested PR.

**Architecture:** A repository-local Ruby command receives only a source repository and tag, downloads the public manifest and allowlisted sources, verifies SHA-256, and renders four ERB templates. A `repository_dispatch` workflow uses a short-lived GitHub App token to create a deterministic PR and enable auto-merge; a separate PR workflow runs Homebrew validation.

**Tech Stack:** Ruby standard library (`JSON`, `ERB`, `Digest`, `Open3`, `Tempfile`), Bash, Homebrew, GitHub Actions, GitHub CLI, GitHub App installation tokens.

---

## File Map

- Create `homebrew-tap/scripts/update-release.rb`: validate the event/manifest, fetch sources, verify hashes, and render allowlisted destinations.
- Create `homebrew-tap/test/update-release-test.rb`: fixture-based unit and command tests with no network access.
- Create `homebrew-tap/Templates/Formula/updatebar.rb.erb`: canonical UpdateBar CLI Formula.
- Create `homebrew-tap/Templates/Formula/updatebar-tui.rb.erb`: canonical UpdateBar TUI Formula.
- Create `homebrew-tap/Templates/Casks/updatebar-app.rb.erb`: canonical UpdateBar app Cask using a DMG.
- Create `homebrew-tap/Templates/Casks/switchtab.rb.erb`: canonical SwitchTab Cask.
- Create `homebrew-tap/scripts/test-changed-packages.sh`: audit, install, and smoke-test only changed package definitions.
- Create `homebrew-tap/test/test-changed-packages-test.sh`: contract-test changed-file routing with a fake `brew`.
- Create `homebrew-tap/.github/workflows/ci.yml`: run unit tests and Homebrew package checks on PRs.
- Create `homebrew-tap/.github/workflows/update-package.yml`: handle typed dispatches and open/auto-merge deterministic PRs.
- Create `homebrew-tap/README.md`: document supported tokens, GitHub App configuration, and recovery.

### Task 1: Add strict manifest validation and allowlisted rendering

**Files:**
- Create: `scripts/update-release.rb`
- Create: `test/update-release-test.rb`
- Create: `Templates/Formula/updatebar.rb.erb`
- Create: `Templates/Formula/updatebar-tui.rb.erb`
- Create: `Templates/Casks/updatebar-app.rb.erb`
- Create: `Templates/Casks/switchtab.rb.erb`

- [ ] **Step 1: Write the failing validator tests**

Create `test/update-release-test.rb` with Minitest fixtures for the two accepted repositories. The test helper writes a manifest and fake executables to a temporary directory, then invokes the command through `Open3.capture3`:

```ruby
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class UpdateReleaseTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "scripts/update-release.rb")

  def manifest(repository:, tag:, packages:)
    {
      "schemaVersion" => 1,
      "repository" => repository,
      "tag" => tag,
      "version" => tag.delete_prefix("v"),
      "commit" => "a" * 40,
      "packages" => packages,
    }
  end

  def release_asset(token, name, sha256, type: "formula")
    {
      "type" => type,
      "token" => token,
      "source" => {"kind" => "release-asset", "name" => name, "sha256" => sha256},
    }
  end

  def run_command(repository:, tag:, document:)
    Dir.mktmpdir("tap-release-test") do |directory|
      manifest_path = File.join(directory, "release-manifest.json")
      File.write(manifest_path, JSON.generate(document))
      Open3.capture3(
        {"TAP_MANIFEST_FILE" => manifest_path, "TAP_VERIFY_ONLY" => "1"},
        "ruby", SCRIPT, "--repository", repository, "--tag", tag,
        chdir: ROOT,
      )
    end
  end

  def test_accepts_switchtab_cask
    package = release_asset("switchtab", "SwitchTab-1.0.0-1.dmg", "1" * 64, type: "cask")
    _, error, status = run_command(
      repository: "sonim1/switchtab",
      tag: "v1.0.0",
      document: manifest(repository: "sonim1/switchtab", tag: "v1.0.0", packages: [package]),
    )
    assert status.success?, error
  end

  def test_rejects_unknown_repository
    _, error, status = run_command(
      repository: "attacker/repo",
      tag: "v1.0.0",
      document: manifest(repository: "attacker/repo", tag: "v1.0.0", packages: []),
    )
    refute status.success?
    assert_includes error, "repository is not allowlisted"
  end

  def test_rejects_path_asset_and_unknown_token
    package = release_asset("../../workflow", "../payload.dmg", "2" * 64, type: "cask")
    _, error, status = run_command(
      repository: "sonim1/switchtab",
      tag: "v1.0.0",
      document: manifest(repository: "sonim1/switchtab", tag: "v1.0.0", packages: [package]),
    )
    refute status.success?
    assert_match(/token|asset name/, error)
  end
end
```

Use a table-driven helper for structural rejections so every named boundary has
an explicit expected message:

```ruby
[
  ["unsupported schema", ->(doc) { doc["schemaVersion"] = 2 }],
  ["repository mismatch", ->(doc) { doc["repository"] = "sonim1/UpdateBar" }],
  ["tag mismatch", ->(doc) { doc["tag"] = "v9.0.0" }],
  ["version mismatch", ->(doc) { doc["version"] = "9.0.0" }],
  ["invalid commit", ->(doc) { doc["commit"] = "abc" }],
  ["invalid checksum", ->(doc) { doc["packages"][0]["source"]["sha256"] = "abc" }],
].each do |message, mutation|
  document = manifest(
    repository: "sonim1/switchtab", tag: "v1.0.0",
    packages: [release_asset("switchtab", "SwitchTab-1.0.0-1.dmg", "1" * 64, type: "cask")],
  )
  mutation.call(document)
  _, error, status = run_command(repository: "sonim1/switchtab", tag: "v1.0.0", document: document)
  refute status.success?
  assert_includes error, message
end
```

Add separate named methods for malformed JSON, duplicate token, invalid package
type, UpdateBar's three exact token/source-kind combinations, checksum mismatch,
and downgrade refusal because those cases need distinct fixtures.

- [ ] **Step 2: Run the validator tests and verify they fail**

Run: `rtk test ruby test/update-release-test.rb`

Expected: FAIL because `scripts/update-release.rb` does not exist.

- [ ] **Step 3: Implement the allowlist and validation boundary**

Create `scripts/update-release.rb` around these exact immutable mappings:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "erb"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tmpdir"

ROOT = Pathname.new(__dir__).join("..").expand_path
RULES = {
  ["sonim1/switchtab", "switchtab"] => {
    type: "cask", kind: "release-asset",
    template: "Templates/Casks/switchtab.rb.erb", destination: "Casks/switchtab.rb",
  },
  ["sonim1/UpdateBar", "updatebar"] => {
    type: "formula", kind: "release-asset",
    template: "Templates/Formula/updatebar.rb.erb", destination: "Formula/updatebar.rb",
  },
  ["sonim1/UpdateBar", "updatebar-app"] => {
    type: "cask", kind: "release-asset",
    template: "Templates/Casks/updatebar-app.rb.erb", destination: "Casks/updatebar-app.rb",
  },
  ["sonim1/UpdateBar", "updatebar-tui"] => {
    type: "formula", kind: "github-tag-archive",
    template: "Templates/Formula/updatebar-tui.rb.erb", destination: "Formula/updatebar-tui.rb",
  },
}.freeze

def fail!(message)
  warn("update-release: #{message}")
  exit 64
end

options = {}
OptionParser.new do |parser|
  parser.on("--repository VALUE") { |value| options[:repository] = value }
  parser.on("--tag VALUE") { |value| options[:tag] = value }
end.parse!

repository = options.fetch(:repository) { fail!("--repository is required") }
tag = options.fetch(:tag) { fail!("--tag is required") }
fail!("repository is not allowlisted") unless RULES.keys.any? { |key| key.first == repository }
fail!("tag must match v<version>") unless tag.match?(/\Av\d+(?:\.\d+)*\z/)

manifest_path = ENV["TAP_MANIFEST_FILE"]
fail!("TAP_MANIFEST_FILE is required") if manifest_path.to_s.empty?
document = JSON.parse(File.read(manifest_path))
fail!("unsupported schema") unless document["schemaVersion"] == 1
fail!("repository mismatch") unless document["repository"] == repository
fail!("tag mismatch") unless document["tag"] == tag
fail!("version mismatch") unless document["version"] == tag.delete_prefix("v")
fail!("invalid commit") unless document["commit"].to_s.match?(/\A[0-9a-f]{40}\z/)
packages = document["packages"]
fail!("packages must be a non-empty array") unless packages.is_a?(Array) && !packages.empty?

seen = {}
packages.each do |package|
  token = package["token"].to_s
  fail!("duplicate token: #{token}") if seen[token]
  seen[token] = true
  rule = RULES[[repository, token]] || fail!("token is not allowlisted: #{token}")
  fail!("package type mismatch: #{token}") unless package["type"] == rule[:type]
  source = package["source"]
  fail!("source must be an object: #{token}") unless source.is_a?(Hash)
  fail!("source kind mismatch: #{token}") unless source["kind"] == rule[:kind]
  fail!("invalid checksum: #{token}") unless source["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
  if rule[:kind] == "release-asset"
    name = source["name"].to_s
    fail!("invalid asset name: #{token}") unless File.basename(name) == name && name.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
  elsif source.key?("name")
    fail!("tag archives cannot provide an asset name")
  end
end

exit 0 if ENV["TAP_VERIFY_ONLY"] == "1"
```

Append these download, checksum, downgrade, and atomic-render helpers and invoke
them for each validated package:

```ruby
def run!(*command, env: {})
  output, error, status = Open3.capture3(env, *command)
  fail!("command failed: #{command.first}: #{error.strip}") unless status.success?
  output
end

def version_parts(value)
  value.split(".").map { |part| Integer(part, 10) }
rescue ArgumentError
  fail!("destination contains an invalid version")
end

def current_version(path)
  return nil unless path.file?
  match = path.read.match(/^\s*version\s+["']([^"']+)["']/)
  match && match[1]
end

def atomic_write(path, content)
  FileUtils.mkdir_p(path.dirname)
  Tempfile.create([path.basename.to_s, ".tmp"], path.dirname.to_s) do |file|
    file.write(content)
    file.flush
    file.fsync
    File.rename(file.path, path)
  end
end

gh = ENV.fetch("GH_BIN", "gh")
curl = ENV.fetch("CURL_BIN", "curl")
version = document.fetch("version")

Dir.mktmpdir("tap-release") do |directory|
  packages.each do |package|
    token = package.fetch("token")
    source = package.fetch("source")
    rule = RULES.fetch([repository, token])
    local_path = File.join(directory, source.fetch("name", "#{token}-#{tag}.tar.gz"))

    url = if source.fetch("kind") == "release-asset"
      run!(
        gh, "release", "download", tag, "--repo", repository,
        "--pattern", source.fetch("name"), "--dir", directory,
        env: {"GH_TOKEN" => ENV.fetch("GH_TOKEN", "")},
      )
      "https://github.com/#{repository}/releases/download/#{tag}/#{source.fetch("name")}"
    else
      archive_url = "https://github.com/#{repository}/archive/refs/tags/#{tag}.tar.gz"
      run!(curl, "--fail", "--location", "--silent", "--show-error", "--output", local_path, archive_url)
      archive_url
    end

    actual = Digest::SHA256.file(local_path).hexdigest
    fail!("checksum mismatch: #{token}") unless actual == source.fetch("sha256")

    destination = ROOT.join(rule.fetch(:destination))
    installed = current_version(destination)
    if installed && (version_parts(installed) <=> version_parts(version)) == 1
      fail!("refusing package downgrade: #{token}")
    end

    template = ERB.new(ROOT.join(rule.fetch(:template)).read, trim_mode: "-")
    sha256 = actual
    rendered = template.result(binding)
    atomic_write(destination, rendered.end_with?("\n") ? rendered : "#{rendered}\n")
  end
end
```

`GH_BIN` and `CURL_BIN` default to `gh` and `curl`; tests override them with
fixture executables. The only constructed URLs use an allowlisted repository,
validated tag, and validated basename.

- [ ] **Step 4: Add canonical templates**

Move the current UpdateBar Formula content into ERB templates and replace only version-dependent fields. The UpdateBar app template changes its URL suffix to `.dmg`. Add this new SwitchTab template:

```erb
# frozen_string_literal: true

cask "switchtab" do
  version "<%= version %>"
  sha256 "<%= sha256 %>"

  url "<%= url %>"
  name "SwitchTab"
  desc "Fast macOS application switcher"
  homepage "https://github.com/sonim1/switchtab"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "SwitchTab.app"
end
```

Each template receives only `version`, `sha256`, and the updater-constructed `url`. It must not evaluate keys or code supplied by the manifest.

- [ ] **Step 5: Complete and run fixture coverage**

Extend `test/update-release-test.rb` with fake `gh` and `curl` commands that copy known bytes, then assert exact rendered files for all four tokens, SHA mismatch rejection, no writes on validation failure, and a byte-identical second run.

Run: `rtk test ruby test/update-release-test.rb`

Expected: all tests pass with zero failures.

- [ ] **Step 6: Commit the manifest boundary**

```bash
rtk git add scripts/update-release.rb test/update-release-test.rb Templates Formula Casks
rtk git diff --cached --check
rtk git commit -m "feat: render packages from release manifests"
```

### Task 2: Test changed Homebrew definitions

**Files:**
- Create: `scripts/test-changed-packages.sh`
- Create: `test/test-changed-packages-test.sh`

- [ ] **Step 1: Write the failing routing contract**

Create a fake `brew` that records arguments and test that Formula changes run `brew audit --strict`, `brew install --formula`, and `brew test`, while Cask changes run `brew audit --cask --strict`, `brew install --cask`, and verify the expected app bundle under a configurable test Applications directory. Unknown changed paths are ignored; unknown files inside `Formula/` or `Casks/` fail.

Run: `rtk test bash test/test-changed-packages-test.sh`

Expected: FAIL because `scripts/test-changed-packages.sh` is missing.

- [ ] **Step 2: Implement exact changed-file routing**

Create `scripts/test-changed-packages.sh` with this interface:

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_REF="${1:?usage: scripts/test-changed-packages.sh <base-ref>}"
BREW_BIN="${BREW_BIN:-brew}"
APPLICATIONS_DIR="${APPLICATIONS_DIR:-/Applications}"

while IFS= read -r path; do
  case "$path" in
    Formula/updatebar.rb|Formula/updatebar-tui.rb)
      token="$(basename "$path" .rb)"
      "$BREW_BIN" audit --strict "$path"
      "$BREW_BIN" install --formula "./$path"
      "$BREW_BIN" test "$token"
      ;;
    Casks/switchtab.rb|Casks/updatebar-app.rb)
      token="$(basename "$path" .rb)"
      "$BREW_BIN" audit --cask --strict "$path"
      "$BREW_BIN" install --cask "./$path"
      case "$token" in
        switchtab) test -d "$APPLICATIONS_DIR/SwitchTab.app" ;;
        updatebar-app) test -d "$APPLICATIONS_DIR/UpdateBar.app" ;;
      esac
      ;;
    Formula/*|Casks/*)
      echo "unsupported package definition: $path" >&2
      exit 64
      ;;
  esac
done < <(git diff --name-only "$BASE_REF"...HEAD)
```

- [ ] **Step 3: Run the routing test and syntax checks**

Run: `rtk test bash test/test-changed-packages-test.sh`

Expected: all routing cases pass.

Run: `rtk proxy bash -n scripts/test-changed-packages.sh test/test-changed-packages-test.sh`

Expected: no output and exit 0.

- [ ] **Step 4: Commit package verification**

```bash
rtk git add scripts/test-changed-packages.sh test/test-changed-packages-test.sh
rtk git diff --cached --check
rtk git commit -m "test: verify changed Homebrew packages"
```

### Task 3: Add PR CI

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a workflow contract assertion**

Extend `test/update-release-test.rb` to parse `.github/workflows/ci.yml` with `YAML.safe_load` and assert `pull_request`, `contents: read`, pinned checkout, Ruby tests, the Bash routing test, and a macOS package job invoking `scripts/test-changed-packages.sh origin/main`.

Run: `rtk test ruby test/update-release-test.rb`

Expected: FAIL because the CI workflow is missing.

- [ ] **Step 2: Create the CI workflow**

Create `.github/workflows/ci.yml` with two jobs: `contracts` on `ubuntu-latest` for Ruby/Bash tests, and `homebrew` on `macos-15` for changed package verification. Checkout uses full history and `persist-credentials: false`; workflow permissions are `contents: read`. The Homebrew job fetches `origin/main` explicitly before running the script.

```yaml
name: CI
on:
  pull_request:
permissions:
  contents: read
jobs:
  contracts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          persist-credentials: false
      - run: ruby test/update-release-test.rb
      - run: bash test/test-changed-packages-test.sh
  homebrew:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          fetch-depth: 0
          persist-credentials: false
      - run: git fetch --no-tags origin main:refs/remotes/origin/main
      - run: scripts/test-changed-packages.sh origin/main
```

- [ ] **Step 3: Verify and commit CI**

Run: `rtk test ruby test/update-release-test.rb`

Expected: all tests pass.

```bash
rtk git add .github/workflows/ci.yml test/update-release-test.rb
rtk git diff --cached --check
rtk git commit -m "ci: validate Homebrew update pull requests"
```

### Task 4: Receive releases and create auto-merge PRs

**Files:**
- Create: `.github/workflows/update-package.yml`
- Modify: `test/update-release-test.rb`

- [ ] **Step 1: Write the dispatch workflow contract**

Assert the workflow accepts only `repository_dispatch` type `homebrew_release`, has a repository-wide concurrency group, mints a GitHub App token for `homebrew-tap`, runs `scripts/update-release.rb`, creates branch `release/<product>-<version>`, pushes with the App token, creates or reuses one PR, and invokes `gh pr merge --auto --squash`.

Run: `rtk test ruby test/update-release-test.rb`

Expected: FAIL because `.github/workflows/update-package.yml` is missing.

- [ ] **Step 2: Create the dispatch workflow**

Use top-level `contents: read`; the job receives `contents: write` and `pull-requests: write`. Mint the token with the GitHub-maintained `actions/create-github-app-token` action pinned to a reviewed full commit SHA, passing `${{ vars.TAP_GITHUB_APP_ID }}`, `${{ secrets.TAP_GITHUB_APP_PRIVATE_KEY }}`, owner `sonim1`, and repository `homebrew-tap`.

The update step validates payload strings before use:

```bash
repository='${{ github.event.client_payload.repository }}'
tag='${{ github.event.client_payload.tag }}'
case "$repository" in sonim1/switchtab|sonim1/UpdateBar) ;; *) exit 64 ;; esac
[[ "$tag" =~ ^v[0-9]+([.][0-9]+)*$ ]] || exit 64
TAP_MANIFEST_FILE="$RUNNER_TEMP/release-manifest.json" \
GH_TOKEN='${{ steps.app-token.outputs.token }}' \
  gh release download "$tag" --repo "$repository" \
    --pattern release-manifest.json --dir "$RUNNER_TEMP"
TAP_MANIFEST_FILE="$RUNNER_TEMP/release-manifest.json" \
GH_TOKEN='${{ steps.app-token.outputs.token }}' \
  ruby scripts/update-release.rb --repository "$repository" --tag "$tag"
```

After a non-empty diff, derive the branch only from the allowlisted repository basename and validated version, configure the GitHub App as author, create/reset that remote release branch, commit only `Formula/` and `Casks/`, and push with `--force-with-lease`. Create or reuse the PR by `--head`, then enable squash auto-merge. A byte-identical rerun exits successfully without a new commit.

- [ ] **Step 3: Verify workflow contracts**

Run: `rtk test ruby test/update-release-test.rb`

Expected: all manifest, renderer, and workflow assertions pass.

Run: `rtk git diff --check`

Expected: no output.

- [ ] **Step 4: Commit dispatch automation**

```bash
rtk git add .github/workflows/update-package.yml test/update-release-test.rb
rtk git diff --cached --check
rtk git commit -m "ci: automate Homebrew release updates"
```

### Task 5: Document setup and run the tap baseline

**Files:**
- Create: `README.md`

- [ ] **Step 1: Document the operator contract**

Document the four allowlisted tokens, `TAP_GITHUB_APP_ID`, `TAP_GITHUB_APP_PRIVATE_KEY`, the `homebrew_release` payload, required `main` rules/checks, repository auto-merge setting, deterministic retry behavior, and the rule that public releases are never rolled back by tap automation.

- [ ] **Step 2: Run all local checks**

```bash
rtk test ruby test/update-release-test.rb
rtk test bash test/test-changed-packages-test.sh
rtk proxy bash -n scripts/test-changed-packages.sh test/test-changed-packages-test.sh
rtk git diff --check
```

Expected: all tests pass and syntax/whitespace checks are silent.

- [ ] **Step 3: Commit documentation**

```bash
rtk git add README.md
rtk git diff --cached --check
rtk git commit -m "docs: explain automated tap updates"
```

## Live Configuration Handoff

After the code is merged, a maintainer must enable repository auto-merge, require the `contracts` and `homebrew` checks on `main`, install the dedicated GitHub App on the three allowlisted repositories, and add the App ID/private key to their documented variables/secrets. Do not send a live dispatch until the SwitchTab manifest producer is merged.
