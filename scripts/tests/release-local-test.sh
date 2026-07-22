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
    "git push origin v" \
    "updates.switchtab.app/appcast.xml" \
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

def validate_release_operations!(readme)
  local = markdown_section(readme, "Local signing and publishing")
  local_release_commands = fenced_blocks(local).flat_map(&:lines).map(&:strip).select do |line|
    line.match?(%r{\Ascripts/(?:generate-appcast|generate-release-manifest|publish-release)[.]sh(?:[[:space:]]|\z)})
  end
  assert_documented(
    local_release_commands == [
      "scripts/generate-appcast.sh",
      "scripts/generate-release-manifest.sh v1.2.3",
      "scripts/publish-release.sh v1.2.3"
    ],
    "local release commands must order appcast, manifest, then publication exactly once: #{local_release_commands.inspect}"
  )

  app_setup = markdown_section(readme, "Protected release environment and tap integration")
  app_setup_text = normalized(app_setup)
  assert_documented(app_setup_text.include?("required reviewer protection"), "release Environment must require a reviewer")
  assert_documented(app_setup_text.include?("Both the `release` and `notify` jobs request approval"), "both protected jobs must document approval")
  assert_documented(app_setup_text.include?("A notify-only rerun can request approval again"), "notify rerun approval must be explicit")
  assert_documented(app_setup_text.include?("installed only on `sonim1/homebrew-tap`"), "GitHub App installation scope must be tap-only")
  ["`Administration: Read`", "`Contents: Read & write`", "`Pull requests: Read & write`"].each do |permission|
    assert_documented(app_setup.include?(permission), "missing unified GitHub App permission: #{permission}")
  end
  assert_documented(app_setup_text.include?("SwitchTab `notify` token uses only the dispatch/contents capability"), "source notify token scope must be explained")
  assert_documented(app_setup_text.include?("tap receiver token requests all three permissions"), "tap receiver token scope must be explained")
  assert_documented(app_setup_text.include?("Environment secrets are available to both jobs after approval"), "shared Environment secret availability must be truthful")
  assert_documented(app_setup_text.include?("workflow YAML references and injects Apple, Sparkle, and R2 secrets only into `release` steps"), "release secret references must be documented")
  assert_documented(app_setup_text.include?("references and injects the tap App private key only into `notify`"), "notify secret references must be documented")
  assert_documented(app_setup_text.include?("true secret-availability isolation requires separate Environments"), "separate Environment isolation boundary must be documented")

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
  transport_contract = "`homebrew_release` dispatch payload consists only of `repository` and `tag`."
  assert_documented(execution_text.include?(transport_contract), "dispatch payload must contain only repository and tag")
  assert_documented(execution_text.include?("downloads `release-manifest.json` from the public GitHub Release"), "tap manifest download transport must be documented")
  assert_documented(execution_text.include?("shared by the Sparkle appcast, GitHub Release, and Homebrew Cask"), "canonical DMG reuse must be documented")

  recovery = markdown_section(readme, "Recovery and immutability")
  recovery_text = normalized(recovery)
  assert_documented(recovery_text.include?("rerun only the failed `notify` job"), "notify-only rerun must be documented")
  assert_documented(recovery_text.include?("does not rebuild, sign, notarize, or replace public assets"), "notify rerun non-publication boundary must be documented")
  assert_documented(recovery_text.include?("Do not delete or recreate the tag"), "tag recovery rule must be documented")
  assert_documented(recovery_text.include?('read -r -s -p "Temporary tap dispatch token: " TAP_GH_TOKEN'), "manual narrow dispatch fallback must avoid shell history")

  whole_text = normalized(readme)
  assert_documented(!whole_text.match?(/secrets are available only to/i), "README falsely claims shared Environment secrets are job-isolated")
  assert_documented(!whole_text.match?(/(?:manifest|release-manifest[.]json).{0,120}\b(?:sent|carried|included)\b.{0,80}\b(?:event|dispatch|payload)\b/i), "README falsely claims the manifest is sent in dispatch")
  assert_documented(!whole_text.match?(/\b(?:event|dispatch|payload)\b.{0,80}\b(?:sends|carries|includes|contains)\b.{0,120}(?:manifest|release-manifest[.]json)/i), "README falsely claims dispatch contains the manifest")
  assert_documented(!recovery_text.match?(/`?notify`? fails.{0,160}(?:rerun|re-run) (?:the )?full (?:release|workflow)/i), "README tells operators to rerun the full release after notify failure")
end

readme_path = ARGV.fetch(0)
readme = File.read(readme_path)
validate_release_operations!(readme)

def assert_mutation_rejected(label, original, mutated)
  raise "FAIL: mutation did not change README: #{label}" if mutated == original

  begin
    validate_release_operations!(mutated)
  rescue DocumentationContractError
    return
  end
  raise "FAIL: documentation validator accepted mutation: #{label}"
end

ordered_commands = "scripts/generate-appcast.sh\nscripts/generate-release-manifest.sh v1.2.3"
assert_mutation_rejected(
  "reversed appcast and manifest commands",
  readme,
  readme.sub(ordered_commands, "scripts/generate-release-manifest.sh v1.2.3\nscripts/generate-appcast.sh")
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
assert_mutation_rejected(
  "manifest included in dispatch payload",
  readme,
  readme.sub(
    /The `homebrew_release` dispatch payload[[:space:]]+consists only of `repository` and `tag`[.]/,
    "The `homebrew_release` dispatch payload includes `repository`, `tag`, and `release-manifest.json`."
  )
)
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

user_specific_path='/Users/'"kendrick"
if grep -Fq "$user_specific_path" "${DOCUMENTATION_FILES[@]}"; then
    fail "documentation contains a user-specific local path"
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
