#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$PROJECT_ROOT/scripts/release-local.sh"
EXAMPLE="$PROJECT_ROOT/.env.release.local.example"
README="$PROJECT_ROOT/README.md"
DOCUMENTATION_FILES=(
    "$README"
    "$EXAMPLE"
    "$PROJECT_ROOT/BLOCKERS.md"
    "$PROJECT_ROOT/docs/repository-maintenance.md"
    "$PROJECT_ROOT/review-result.md"
    "$PROJECT_ROOT/CLAUDE.md"
)

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_status() {
    local expected="$1"

    if [[ "$status" -ne "$expected" ]]; then
        fail "expected status $expected, got $status; output: $output"
    fi
}

assert_output_contains() {
    local expected="$1"

    if [[ "$output" != *"$expected"* ]]; then
        fail "expected output to contain '$expected'; output: $output"
    fi
}

[[ -x "$WRAPPER" ]] || fail "scripts/release-local.sh is missing or not executable"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-release-local.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FIXTURE_ROOT="$TEMP_ROOT/project"
FIXTURE_WRAPPER="$FIXTURE_ROOT/scripts/release-local.sh"
RECORD_PATH="$TEMP_ROOT/delegation.txt"
mkdir -p "$FIXTURE_ROOT/scripts"
cp "$WRAPPER" "$FIXTURE_WRAPPER"

cat > "$FIXTURE_ROOT/scripts/build-direct-distribution.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'SPARKLE_PUBLIC_ED_KEY=%s\n' "$SPARKLE_PUBLIC_ED_KEY"
    printf 'DEVELOPER_ID_APPLICATION=%s\n' "$DEVELOPER_ID_APPLICATION"
    printf 'NOTARYTOOL_KEYCHAIN_PROFILE=%s\n' "$NOTARYTOOL_KEYCHAIN_PROFILE"
    printf 'R2_SECRET_EXPORTED=%s\n' "${R2_SECRET_ACCESS_KEY+x}"
    printf 'ARG=%s\n' "$@"
} > "$RECORD_PATH"

exit "${FAKE_EXIT_STATUS:-0}"
EOF
chmod +x "$FIXTURE_ROOT/scripts/build-direct-distribution.sh"

invoke_wrapper() {
    local fake_exit_status="$1"
    shift

    set +e
    output="$(
        cd /
        RECORD_PATH="$RECORD_PATH" \
            FAKE_EXIT_STATUS="$fake_exit_status" \
            "$FIXTURE_WRAPPER" "$@" 2>&1
    )"
    status=$?
    set -e
}

rm -f "$RECORD_PATH"
invoke_wrapper 0
assert_status 66
assert_output_contains ".env.release.local.example"
[[ ! -e "$RECORD_PATH" ]] || fail "missing config delegated to the release script"

cat > "$FIXTURE_ROOT/.env.release.local" <<'EOF'
DEVELOPER_ID_APPLICATION='Developer ID Application: Test User (TESTTEAM)'
NOTARYTOOL_KEYCHAIN_PROFILE='test-notary'
EOF

rm -f "$RECORD_PATH"
invoke_wrapper 0
assert_status 64
assert_output_contains "SPARKLE_PUBLIC_ED_KEY"
[[ ! -e "$RECORD_PATH" ]] || fail "missing variable delegated to the release script"

cat > "$FIXTURE_ROOT/.env.release.local" <<'EOF'
SPARKLE_PUBLIC_ED_KEY='public-key-value'
DEVELOPER_ID_APPLICATION='Developer ID Application: Test User (TESTTEAM)'
NOTARYTOOL_KEYCHAIN_PROFILE='test-notary'
EOF

rm -f "$RECORD_PATH"
invoke_wrapper 0
assert_status 0
grep -Fxq "SPARKLE_PUBLIC_ED_KEY=public-key-value" "$RECORD_PATH" || fail "Sparkle public key was not forwarded"
grep -Fxq "DEVELOPER_ID_APPLICATION=Developer ID Application: Test User (TESTTEAM)" "$RECORD_PATH" || fail "Developer ID identity was not preserved"
grep -Fxq "NOTARYTOOL_KEYCHAIN_PROFILE=test-notary" "$RECORD_PATH" || fail "notary profile was not forwarded"
grep -Fxq "ARG=--release" "$RECORD_PATH" || fail "--release was not forwarded"
[[ "$(grep -c '^ARG=' "$RECORD_PATH")" -eq 1 ]] || fail "wrapper forwarded unexpected arguments"

trace_secret='trace-r2-secret-value'
printf "R2_SECRET_ACCESS_KEY='%s'\n" "$trace_secret" >> "$FIXTURE_ROOT/.env.release.local"
set +e
output="$(
    cd /
    RECORD_PATH="$RECORD_PATH" FAKE_EXIT_STATUS=0 \
        bash -x "$FIXTURE_WRAPPER" 2>&1
)"
status=$?
set -e
assert_status 0
[[ "$output" != *"$trace_secret"* ]] || fail "inherited xtrace exposed release credentials"
grep -Fxq 'R2_SECRET_EXPORTED=' "$RECORD_PATH" || fail "release credentials leaked into the build subprocess"

rm -f "$RECORD_PATH"
invoke_wrapper 37
assert_status 37
[[ -e "$RECORD_PATH" ]] || fail "delegated failure did not execute the release script"

rm -f "$RECORD_PATH"
invoke_wrapper 0 --unexpected
assert_status 64
assert_output_contains "Usage: scripts/release-local.sh"
[[ ! -e "$RECORD_PATH" ]] || fail "invalid arguments delegated to the release script"

git -C "$PROJECT_ROOT" check-ignore -q .env.release.local || fail ".env.release.local is not ignored"
if git -C "$PROJECT_ROOT" check-ignore -q .env.release.local.example; then
    fail ".env.release.local.example is unexpectedly ignored"
fi

for name in \
    SPARKLE_PUBLIC_ED_KEY \
    DEVELOPER_ID_APPLICATION \
    NOTARYTOOL_KEYCHAIN_PROFILE \
    SPARKLE_KEY_ACCOUNT \
    R2_BUCKET_NAME \
    UPDATE_DOMAIN \
    CLOUDFLARE_ACCOUNT_ID \
    CLOUDFLARE_ZONE_ID; do
    grep -q "^${name}=" "$EXAMPLE" || fail "$EXAMPLE is missing $name"
done

for text in \
    "npm ci --ignore-scripts" \
    "setup-update-hosting.sh" \
    "release-local.sh" \
    "generate-appcast.sh" \
    "publish-release.sh" \
    "CLOUDFLARE_API_TOKEN" \
    "R2_ACCESS_KEY_ID" \
    "R2_SECRET_ACCESS_KEY" \
    "SPARKLE_PRIVATE_ED_KEY" \
    "APPLE_CERTIFICATE_P12_BASE64" \
    "APPLE_CERTIFICATE_PASSWORD" \
    "APPLE_NOTARY_KEY_P8_BASE64" \
    "APPLE_NOTARY_KEY_ID" \
    "APPLE_NOTARY_ISSUER_ID" \
    "updates.switchtab.royjen.com/appcast.xml" \
    "refs/tags/" \
    "https://developers.cloudflare.com/r2/api/tokens/" \
    "https://developers.cloudflare.com/r2/api/s3/api/#conditional-operations" \
    "--account ed25519" \
    "If-None-Match: *" \
    'ETag-guarded `If-Match`' \
    'strictly increase `CURRENT_PROJECT_VERSION`' \
    'calls `publish-update.sh` internally' \
    "Choose one publisher for a tag" \
    "Never race local and CI publication" \
    "Do not rebuild or re-tag" \
    "Do not automatically delete objects" \
    "both publishing-" \
    "uncomment and fill in only" \
    "setup management token" \
    "not used by publication" \
    "The draft is created or reused first, exact assets are staged" \
    "Base64" \
    "Recovery"; do
    grep -Fq -- "$text" "$README" || fail "$README is missing '$text'"
done

for repository_variable in \
    SPARKLE_PUBLIC_ED_KEY \
    DEVELOPER_ID_APPLICATION \
    CLOUDFLARE_ACCOUNT_ID; do
    grep -Fq -- "$repository_variable" "$README" || \
        fail "$README is missing repository variable $repository_variable"
done

/usr/bin/ruby - "$README" <<'RUBY'
class DocumentationContractError < StandardError; end

def assert_documented(condition, message)
  raise DocumentationContractError, message unless condition
end

def markdown_section(markdown, title)
  lines = markdown.lines
  start_index = nil
  heading_level = nil

  lines.each_with_index do |line, index|
    match = line.match(/\A(#+)[[:space:]]+#{Regexp.escape(title)}[[:space:]]*\z/)
    next unless match

    start_index = index
    heading_level = match[1].length
    break
  end
  assert_documented(start_index, "missing README section: #{title}")

  finish_index = lines.length
  inside_fence = false
  lines.each_with_index do |line, index|
    next if index <= start_index

    if line.match?(/\A```/)
      inside_fence = !inside_fence
      next
    end
    next if inside_fence

    match = line.match(/\A(#+)[[:space:]]+/)
    if match && match[1].length <= heading_level
      finish_index = index
      break
    end
  end
  lines[(start_index + 1)...finish_index].join
end

def fenced_blocks(section)
  section.scan(/```(?:bash|sh|text)?[[:space:]]*\n(.*?)```/m).flatten
end

def normalized(markdown)
  markdown.gsub(/[[:space:]]+/, " ").strip
end

def visible_markdown(markdown)
  markdown.gsub("\r\n", "\n").gsub("\r", "\n").gsub(/<!--.*?-->/m, "")
end

def local_release_steps(section)
  fenced_blocks(section).flat_map(&:lines).each_with_object([]) do |raw_line, steps|
    line = raw_line.strip
    step = case line
    when "set -euo pipefail"
      :strict_shell
    when /\Arelease_tag=v[0-9]+(?:[.][0-9]+)*\z/
      :release_tag
    when /\Agit fetch .*refs\/heads\/main:refs\/remotes\/origin\/main/
      :fetch_main
    when /\Agit fetch .*--tags .*origin\z/
      :fetch_tags
    when /\Atest -z .*git status --porcelain=v1 --untracked-files=all/
      :clean
    when /\Atest .*git rev-parse HEAD.*git rev-parse origin\/main/
      :head_matches_main
    when /\Agit tag -a /
      :annotated_tag
    when /\Agit show-ref --verify --quiet "refs\/tags\/\$release_tag"\z/
      :exact_tag_ref
    when /\Atest .*git rev-parse "refs\/tags\/\$release_tag\^\{commit\}".*release_commit/
      :tag_matches_recorded_head
    when /\Agit push origin .*refs\/tags\/\$release_tag:refs\/tags\/\$release_tag/
      :push_exact_tag
    when /\Atest .*git rev-parse "refs\/tags\/\$release_tag\^\{commit\}".*git rev-parse HEAD/
      :tag_matches_head
    when "scripts/release-local.sh"
      :release_local
    when "scripts/generate-appcast.sh"
      :generate_appcast
    when /\Ascripts\/generate-release-manifest[.]sh "\$release_tag"\z/
      :generate_manifest
    when /\Ascripts\/publish-release[.]sh "\$release_tag"\z/
      :publish_release
    when /\Aread -r -s -p .* TAP_GH_TOKEN\z/
      :read_tap_token
    when "export TAP_GH_TOKEN"
      :export_tap_token
    when /\Ascripts\/dispatch-homebrew-update[.]sh "\$release_tag"\z/
      :dispatch_tap
    when "unset TAP_GH_TOKEN"
      :unset_tap_token
    end
    steps << step if step
  end
end

def recovery_dispatch_steps(section)
  block = fenced_blocks(section).find { |candidate| candidate.include?("dispatch-homebrew-update.sh") }
  assert_documented(block, "recovery dispatch command block is missing")

  steps = block.lines.each_with_object([]) do |raw_line, result|
    line = raw_line.strip
    step = case line
    when "("
      :subshell_open
    when "set -euo pipefail"
      :strict_shell
    when /\Arelease_tag=v[0-9]+(?:[.][0-9]+)*\z/
      :release_tag
    when /\Atrap 'unset TAP_GH_TOKEN' EXIT HUP INT TERM\z/
      :cleanup_trap
    when /\Aread -r -s -p .* TAP_GH_TOKEN\z/
      :secure_read
    when "export TAP_GH_TOKEN"
      :export_token
    when "set +e"
      :capture_mode
    when /\Ascripts\/dispatch-homebrew-update[.]sh "\$release_tag"\z/
      :dispatch
    when 'dispatch_status=$?'
      :capture_status
    when "set -e"
      :restore_strict_mode
    when "unset TAP_GH_TOKEN"
      :explicit_cleanup
    when "trap - EXIT HUP INT TERM"
      :clear_trap
    when 'exit "$dispatch_status"'
      :propagate_status
    when ")"
      :subshell_close
    end
    result << step if step
  end
  assert_documented(!block.match?(/(?:echo|printf).*TAP_GH_TOKEN/), "recovery must never print the tap token")
  steps
end

def validate_release_operations!(readme)
  readme = visible_markdown(readme)
  local = markdown_section(readme, "Local signing and publishing")
  local_steps = local_release_steps(local)
  assert_documented(
    local_steps == [
      :strict_shell,
      :release_tag,
      :fetch_main,
      :fetch_tags,
      :clean,
      :head_matches_main,
      :annotated_tag,
      :exact_tag_ref,
      :tag_matches_recorded_head,
      :push_exact_tag,
      :strict_shell,
      :release_tag,
      :fetch_main,
      :fetch_tags,
      :clean,
      :head_matches_main,
      :exact_tag_ref,
      :tag_matches_head,
      :release_local,
      :generate_appcast,
      :generate_manifest,
      :publish_release,
      :read_tap_token,
      :export_tap_token,
      :dispatch_tap,
      :unset_tap_token
    ],
    "local release provenance and fallback steps are missing or out of order: #{local_steps.inspect}"
  )
  local_text = normalized(local)
  assert_documented(local_text.match?(/normal.*CI.*(?:owns|builds|publishes).*release/i), "normal tag path must stop for CI ownership")
  assert_documented(local_text.match?(/fallback.*(?:disabled|cancelled).*CI/i), "local fallback must require disabled or cancelled CI")
  assert_documented(local_text.match?(/ignored artifacts.*(?:do not|does not).*source provenance/i), "ignored artifact provenance must be explained")
  assert_documented(local_text.match?(/never race.*CI/i), "local fallback must not race CI")
  assert_documented(local_text.match?(/short-lived.*tap.*token.*(?:shell )?history/i), "fallback token must be short-lived and kept out of history")
  assert_documented(local_text.match?(/dispatch fails.*same.*dispatch.*(?:without|do not).*rebuild/i), "dispatch recovery must reuse the narrow command without rebuilding")
  assert_documented(local_text.match?(/dispatch.*only.*repository.*tag.*downloads.*release-manifest.*public GitHub Release/i), "local dispatch transport must remain repository/tag plus public manifest download")

  app_setup = markdown_section(readme, "Protected release environment and tap integration")
  app_setup_text = normalized(app_setup)
  assert_documented(app_setup_text.match?(/release.*Environment.*required reviewer/i), "release Environment must require a reviewer")
  assert_documented(app_setup_text.match?(/both.*`release`.*`notify`.*(?:request|require).*approval/i), "both protected jobs must document approval")
  assert_documented(app_setup_text.match?(/notify-only rerun.*approval again/i), "notify rerun approval must be explicit")
  assert_documented(app_setup_text.match?(/installed only on `sonim1\/homebrew-tap`/i), "GitHub App installation scope must be tap-only")
  ["`Administration: Read`", "`Contents: Read & write`", "`Pull requests: Read & write`"].each do |permission|
    assert_documented(app_setup.include?(permission), "missing unified GitHub App permission: #{permission}")
  end
  assert_documented(app_setup_text.match?(/SwitchTab `notify` token.*dispatch\/contents capability/i), "source notify token scope must be explained")
  assert_documented(app_setup_text.match?(/tap receiver token.*all three permissions/i), "tap receiver token scope must be explained")
  assert_documented(app_setup_text.match?(/Environment secrets.*available to both jobs.*after approval/i), "shared Environment secret availability must be truthful")
  assert_documented(app_setup_text.match?(/workflow YAML.*references and injects Apple.*Sparkle.*R2.*`release` steps/i), "release secret references must be documented")
  assert_documented(app_setup_text.match?(/references and injects.*tap App private key.*`notify`/i), "notify secret references must be documented")
  assert_documented(app_setup_text.match?(/secret-availability isolation.*separate Environments/i), "separate Environment isolation boundary must be documented")

  app_commands = fenced_blocks(app_setup).join("\n")
  required_app_commands = [
    'gh variable set --env release TAP_GITHUB_APP_ID --body "your-github-app-id"',
    'gh secret set --env release TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem',
    'gh variable set --repo sonim1/homebrew-tap TAP_GITHUB_APP_ID --body "your-github-app-id"',
    'gh secret set --repo sonim1/homebrew-tap TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem'
  ]
  required_app_commands.each do |command|
    assert_documented(app_commands.lines.map(&:strip).include?(command), "missing scoped GitHub App setup command: #{command}")
  end

  execution = markdown_section(readme, "Tags and release execution")
  flow_line = execution.lines.map(&:strip).find { |line| line.start_with?("tag push ->") }
  assert_documented(flow_line, "release flow line is missing")
  flow = flow_line.split("->").map { |step| step.strip.delete("`") }
  assert_documented(
    flow == [
      "tag push",
      "secret-free verify",
      "protected signed release",
      "public GitHub/Sparkle publication",
      "protected notify",
      "tap PR/CI/auto-merge"
    ],
    "release flow order is incorrect"
  )
  execution_text = normalized(execution)
  outside_authoritative_release_block = readme.sub(local, "")
  unsafe_tag_commands = outside_authoritative_release_block.lines.map(&:strip).select do |line|
    line.match?(/\A(?:git tag -a|git push origin)(?:[[:space:]]|\z)/)
  end
  assert_documented(unsafe_tag_commands.empty?, "release instructions outside the guarded block must not offer tag shortcuts: #{unsafe_tag_commands.inspect}")
  assert_documented(execution_text.match?(/guarded normal CI block.*Local signing and publishing.*fully qualified ref/i), "Tags section must point operators to the guarded fully qualified tag flow")
  assert_documented(execution_text.match?(/`homebrew_release`.*dispatch payload.*only.*`repository`.*`tag`/i), "dispatch payload must contain only repository and tag")
  assert_documented(execution_text.match?(/downloads.*`release-manifest[.]json`.*public GitHub Release/i), "tap manifest download transport must be documented")
  assert_documented(execution_text.match?(/shared by.*Sparkle appcast.*GitHub Release.*Homebrew Cask/i), "canonical DMG reuse must be documented")

  recovery = markdown_section(readme, "Recovery and immutability")
  recovery_text = normalized(recovery)
  recovery_steps = recovery_dispatch_steps(recovery)
  assert_documented(
    recovery_steps == [
      :subshell_open,
      :strict_shell,
      :release_tag,
      :cleanup_trap,
      :secure_read,
      :export_token,
      :capture_mode,
      :dispatch,
      :capture_status,
      :restore_strict_mode,
      :explicit_cleanup,
      :clear_trap,
      :propagate_status,
      :subshell_close
    ],
    "recovery dispatch token lifecycle is unsafe or out of order: #{recovery_steps.inspect}"
  )
  assert_documented(recovery_text.match?(/rerun only.*failed `notify` job/i), "notify-only rerun must be documented")
  assert_documented(recovery_text.match?(/does not rebuild.*sign.*notarize.*replace public assets/i), "notify rerun non-publication boundary must be documented")
  assert_documented(recovery_text.match?(/do not delete or recreate.*tag/i), "tag recovery rule must be documented")
  assert_documented(recovery_text.include?('read -r -s -p "Temporary tap dispatch token: " TAP_GH_TOKEN'), "manual narrow dispatch fallback must avoid shell history")

  whole_text = normalized(readme)
  assert_documented(!whole_text.match?(/secrets are available only to/i), "README falsely claims shared Environment secrets are job-isolated")
  assert_documented(!whole_text.match?(/(?:manifest|release-manifest[.]json).{0,120}\b(?:sent|carried|included)\b.{0,80}\b(?:event|dispatch|payload)\b/i), "README falsely claims the manifest is sent in dispatch")
  assert_documented(!whole_text.match?(/\b(?:event|dispatch) payload\b.{0,80}\b(?:sends|carries|includes|contains)\b.{0,80}(?:manifest|release-manifest[.]json)/i), "README falsely claims dispatch contains the manifest")
  assert_documented(!recovery_text.match?(/`?notify`? fails.{0,160}(?:rerun|re-run) (?:the )?full (?:release|workflow)/i), "README tells operators to rerun the full release after notify failure")
end

readme_path = ARGV.fetch(0)
readme = File.binread(readme_path)
validate_release_operations!(readme)
validate_release_operations!(readme.gsub("\n", "\r\n"))

def assert_mutation_rejected(label, original, mutated)
  raise "FAIL: mutation did not change README: #{label}" if mutated == original

  begin
    validate_release_operations!(mutated)
  rescue DocumentationContractError
    return
  end
  raise "FAIL: documentation validator accepted mutation: #{label}"
end

ordered_commands = "scripts/generate-appcast.sh\nscripts/generate-release-manifest.sh \"$release_tag\""
assert_mutation_rejected(
  "reversed appcast and manifest commands",
  readme,
  readme.sub(ordered_commands, "scripts/generate-release-manifest.sh \"$release_tag\"\nscripts/generate-appcast.sh")
)
assert_mutation_rejected(
  "missing release-local build",
  readme,
  readme.sub(/^scripts\/release-local[.]sh\n/, "")
)
assert_mutation_rejected(
  "release-local moved after appcast",
  readme,
  readme.sub(
    "scripts/release-local.sh\nscripts/generate-appcast.sh",
    "scripts/generate-appcast.sh\nscripts/release-local.sh"
  )
)
assert_mutation_rejected(
  "missing clean and HEAD provenance checks",
  readme,
  readme
    .gsub(/^test -z .*git status --porcelain=v1 --untracked-files=all.*\n/, "")
    .gsub(/^test .*git rev-parse HEAD.*git rev-parse origin\/main.*\n/, "")
)
assert_mutation_rejected(
  "missing tap dispatch",
  readme,
  readme.sub(/^scripts\/dispatch-homebrew-update[.]sh "\$release_tag"\n/, "")
)
fallback_start = readme.index("Use the local fallback")
fallback_finish = readme.index("### Cloudflare publishing credentials")
raise "FAIL: local fallback mutation bounds are missing" unless fallback_start && fallback_finish
fallback = readme[fallback_start...fallback_finish]
ambiguous_fallback = fallback.gsub('refs/tags/$release_tag', '$release_tag')
assert_mutation_rejected(
  "ambiguous bare local release tag",
  readme,
  readme[0...fallback_start] + ambiguous_fallback + readme[fallback_finish..-1]
)
unsafe_tag_shortcut = <<'MARKDOWN'

```bash
git tag -a v1.2.3 -m "SwitchTab 1.2.3"
git push origin v1.2.3
```
MARKDOWN
assert_mutation_rejected(
  "unsafe duplicate tag shortcut",
  readme,
  readme.sub(
    "### Tags and release execution\n",
    "### Tags and release execution\n#{unsafe_tag_shortcut}"
  )
)
recovery_start = readme.index("### Recovery and immutability")
raise "FAIL: recovery mutation section is missing" unless recovery_start
recovery_prefix = readme[0...recovery_start]
recovery_section = readme[recovery_start..-1]
recovery_without_trap = recovery_section.sub(/^trap 'unset TAP_GH_TOKEN' EXIT HUP INT TERM\n/, "")
assert_mutation_rejected(
  "recovery token cleanup trap removed",
  readme,
  recovery_prefix + recovery_without_trap
)
assert_mutation_rejected(
  "missing Administration read permission",
  readme,
  readme.sub(/^.*`Administration: Read`.*\n/, "")
)
assert_mutation_rejected(
  "false Environment secret isolation",
  readme,
  readme.sub("### Protected release environment and tap integration\n", "### Protected release environment and tap integration\n\nApple secrets are available only to `release`.\n")
)
manifest_payload_mutation = readme.sub(
  /The `homebrew_release` dispatch payload[[:space:]]+consists only of `repository` and `tag`[.]/,
  '\0' + "\nThe `release-manifest.json` is sent in the dispatch payload."
)
assert_mutation_rejected("manifest included in dispatch payload", readme, manifest_payload_mutation)
RUBY

assert_exact_example_placeholder() {
    local name="$1"
    local expected_line="$2"
    local name_count exact_count

    name_count="$(grep -c "^${name}=" "$EXAMPLE" || true)"
    exact_count="$(grep -Fxc -- "$expected_line" "$EXAMPLE" || true)"
    [[ "$name_count" -eq 1 ]] || fail "$EXAMPLE must contain exactly one $name assignment"
    [[ "$exact_count" -eq 1 ]] || fail "$EXAMPLE must use the placeholder-only value for $name"
}

assert_exact_example_placeholder CLOUDFLARE_ACCOUNT_ID \
    "CLOUDFLARE_ACCOUNT_ID='your-cloudflare-account-id'"
assert_exact_example_placeholder CLOUDFLARE_ZONE_ID \
    "CLOUDFLARE_ZONE_ID='your-cloudflare-zone-id'"
assert_exact_example_placeholder SPARKLE_PUBLIC_ED_KEY \
    "SPARKLE_PUBLIC_ED_KEY='your-sparkle-public-ed-key'"
assert_exact_example_placeholder DEVELOPER_ID_APPLICATION \
    "DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'"

assert_commented_secret_placeholder() {
    local name="$1"
    local expected_line="$2"
    local assignment_count exact_count

    assignment_count="$(grep -Ec "^# ${name}=" "$EXAMPLE" || true)"
    exact_count="$(grep -Fxc -- "$expected_line" "$EXAMPLE" || true)"
    [[ "$assignment_count" -eq 1 ]] || \
        fail "$EXAMPLE must contain exactly one commented $name placeholder"
    [[ "$exact_count" -eq 1 ]] || \
        fail "$EXAMPLE must use the exact commented placeholder for $name"
    if grep -Eq "^${name}=" "$EXAMPLE"; then
        fail "$EXAMPLE must not activate the $name placeholder"
    fi
}

assert_commented_secret_placeholder CLOUDFLARE_API_TOKEN \
    "# CLOUDFLARE_API_TOKEN='your-scoped-cloudflare-api-token'"
assert_commented_secret_placeholder R2_ACCESS_KEY_ID \
    "# R2_ACCESS_KEY_ID='your-r2-access-key-id'"
assert_commented_secret_placeholder R2_SECRET_ACCESS_KEY \
    "# R2_SECRET_ACCESS_KEY='your-r2-secret-access-key'"

stale_cloudflare_auth_url='https://developers.cloudflare.com/r2/api/s3/'"tokens/"
if grep -Fq "$stale_cloudflare_auth_url" "$README"; then
    fail "$README contains the stale Cloudflare R2 authentication link"
fi

grep -Eq 'v\*.*(ruleset|protection)|(ruleset|protection).*v\*' "$README" || \
    fail "$README is missing v* tag protection guidance"

absolute_macos_user_path='/Users/[^/[:space:]]+'
if grep -Eq "$absolute_macos_user_path" "${DOCUMENTATION_FILES[@]}"; then
    fail "documentation contains an absolute macOS user path"
fi

if grep -Eq -- '-----BEGIN (OPENSSH |RSA |EC |ED25519 )?PRIVATE KEY-----' "${DOCUMENTATION_FILES[@]}"; then
    fail "documentation contains a private-key block"
fi

if grep -Eq -- '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})' "${DOCUMENTATION_FILES[@]}"; then
    fail "documentation contains an obvious secret literal"
fi

if grep -Eq '[가-힣]' "${DOCUMENTATION_FILES[@]}"; then
    fail "documentation contains Korean text"
fi

if grep -Fq 'The current release script automates only DMG and checksum generation' "${DOCUMENTATION_FILES[@]}" \
    || grep -Fq 'Public Sparkle auto-updates still require signed appcast generation' "${DOCUMENTATION_FILES[@]}"; then
    fail "documentation contains a stale release-automation claim"
fi

bash -n "$WRAPPER"
bash -n "$PROJECT_ROOT/scripts/build-direct-distribution.sh"
bash -n "$SCRIPT_DIR/release-local-test.sh"

echo "release-local contract tests passed"
