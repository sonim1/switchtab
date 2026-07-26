#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/plan-release.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-plan-release.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

REPOSITORY="$TEMP_ROOT/repository"
mkdir -p "$REPOSITORY"
(
    cd -- "$REPOSITORY"
    git init -q
    git config user.name 'SwitchTab Test'
    git config user.email 'switchtab@example.invalid'
)

write_project() {
    local marketing_version="$1"
    local build_version="$2"
    local second_marketing_version="${3:-$marketing_version}"
    local second_build_version="${4:-$build_version}"

    mkdir -p "$REPOSITORY/SwitchTab.xcodeproj" "$REPOSITORY/SwitchTab"
    cat > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj" <<EOF
// OpenStep project fixture
{
    objects = {
        DEBUG_CONFIG = {
            buildSettings = {
                CURRENT_PROJECT_VERSION = $build_version;
                MARKETING_VERSION = $marketing_version;
            };
        };
        RELEASE_CONFIG = {
            buildSettings = {
                CURRENT_PROJECT_VERSION = $second_build_version;
                MARKETING_VERSION = $second_marketing_version;
            };
        };
    };
}
EOF
}

commit_fixture() {
    local message="$1"

    (
        cd -- "$REPOSITORY"
        git add -A
        git commit --quiet -m "$message"
        git rev-parse HEAD
    )
}

write_project '1.0' '1'
printf 'import Foundation\n' > "$REPOSITORY/SwitchTab/App.swift"
printf '# SwitchTab\n' > "$REPOSITORY/README.md"
BASE_COMMIT="$(commit_fixture 'base project')"

run_plan() {
    set +e
    PLAN_OUTPUT="$(
        cd -- "$REPOSITORY"
        "$SCRIPT_SOURCE" "$@" 2>&1
    )"
    PLAN_STATUS=$?
    set -e
}

assert_status() {
    local expected="$1"
    [[ "$PLAN_STATUS" -eq "$expected" ]] || \
        fail "expected status $expected, got $PLAN_STATUS; output: $PLAN_OUTPUT"
}

assert_output() {
    local expected="$1"
    [[ "$PLAN_OUTPUT" == "$expected" ]] || \
        fail "unexpected output; expected <$expected>, got <$PLAN_OUTPUT>"
}

assert_output_contains() {
    local expected="$1"
    [[ "$PLAN_OUTPUT" == *"$expected"* ]] || \
        fail "output did not contain <$expected>: $PLAN_OUTPUT"
}

assert_plan_failure() {
    local base_commit="$1"
    local head_commit="$2"

    run_plan "$base_commit" "$head_commit"
    [[ "$PLAN_STATUS" -ne 0 ]] || fail 'invalid release plan unexpectedly succeeded'
    assert_output_contains 'release plan rejected'
}

# The interface requires two real commits and the project file at both revisions.
run_plan 'not-a-commit' "$BASE_COMMIT"
[[ "$PLAN_STATUS" -ne 0 ]] || fail 'missing base commit unexpectedly succeeded'
assert_output_contains 'commit'

git -C "$REPOSITORY" rm --quiet SwitchTab.xcodeproj/project.pbxproj
MISSING_PROJECT_COMMIT="$(commit_fixture 'remove project file')"
assert_plan_failure "$BASE_COMMIT" "$MISSING_PROJECT_COMMIT"

git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT" -- SwitchTab.xcodeproj/project.pbxproj
commit_fixture 'restore project file' >/dev/null

# Markdown-only changes are explicitly skipped and must not produce a tag.
printf '\nDocumentation update.\n' >> "$REPOSITORY/README.md"
DOCS_ONLY_COMMIT="$(commit_fixture 'docs only')"
run_plan "$BASE_COMMIT" "$DOCS_ONLY_COMMIT"
assert_status 0
assert_output 'release=false'
[[ "$PLAN_OUTPUT" != *'tag='* ]] || fail 'docs-only plan emitted a release tag'

# Any source change is relevant and requires both versions to increase.
printf 'func changed() {}\n' >> "$REPOSITORY/SwitchTab/App.swift"
SOURCE_WITHOUT_BUMP_COMMIT="$(commit_fixture 'source without bump')"
assert_plan_failure "$BASE_COMMIT" "$SOURCE_WITHOUT_BUMP_COMMIT"

# A marketing-only or build-only bump is not a valid release.
write_project '1.0.1' '1'
MARKETING_ONLY_COMMIT="$(commit_fixture 'marketing only')"
assert_plan_failure "$BASE_COMMIT" "$MARKETING_ONLY_COMMIT"

write_project '1.0' '2'
BUILD_ONLY_COMMIT="$(commit_fixture 'build only')"
assert_plan_failure "$BASE_COMMIT" "$BUILD_ONLY_COMMIT"

# Equal and decreasing dotted versions are rejected for relevant changes.
write_project '1.0' '1'
printf 'equal versions still need a release bump\n' >> "$REPOSITORY/SwitchTab/App.swift"
EQUAL_COMMIT="$(commit_fixture 'equal versions')"
assert_plan_failure "$BASE_COMMIT" "$EQUAL_COMMIT"

write_project '0.9' '0'
printf 'decreasing versions are invalid\n' >> "$REPOSITORY/SwitchTab/App.swift"
DECREASING_COMMIT="$(commit_fixture 'decreasing versions')"
assert_plan_failure "$BASE_COMMIT" "$DECREASING_COMMIT"

# A valid source release must increase both dotted versions numerically.
write_project '1.0.1' '2'
printf 'func released() {}\n' >> "$REPOSITORY/SwitchTab/App.swift"
VALID_COMMIT="$(commit_fixture 'valid release')"
run_plan "$BASE_COMMIT" "$VALID_COMMIT"
assert_status 0
assert_output $'release=true\ntag=v1.0.1\nversion=1.0.1\nbuild=2'

OUTPUT_FILE="$TEMP_ROOT/release-plan.env"
run_plan "$BASE_COMMIT" "$VALID_COMMIT" "$OUTPUT_FILE"
assert_status 0
[[ -f "$OUTPUT_FILE" ]] || fail 'output file was not created'
[[ "$(<"$OUTPUT_FILE")" == "$PLAN_OUTPUT" ]] || fail 'output file did not match stdout'

# The release workflow permits only one to three build-version components.
git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT"
write_project '1.0.1' '2.0.0.1'
FOUR_COMPONENT_BUILD_COMMIT="$(commit_fixture 'four component build version')"
assert_plan_failure "$BASE_COMMIT" "$FOUR_COMPONENT_BUILD_COMMIT"

# Inline OpenStep declarations must not hide a conflicting second value.
git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT"
cat > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj" <<'EOF'
// Inline OpenStep project fixture
{
    settings = {
        MARKETING_VERSION = 1.0.1; MARKETING_VERSION = 1.0.2;
        CURRENT_PROJECT_VERSION = 2; CURRENT_PROJECT_VERSION = 2;
    };
}
EOF
INLINE_CONFLICT_COMMIT="$(commit_fixture 'inline declaration conflict')"
assert_plan_failure "$BASE_COMMIT" "$INLINE_CONFLICT_COMMIT"

# Commented-out declarations must not count as real project settings.
git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT"
cat > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj" <<'EOF'
// Comment filtering project fixture
{
    settings = {
        MARKETING_VERSION = 1.0.1;
        CURRENT_PROJECT_VERSION = 2;
    };
    /* MARKETING_VERSION = 9.9; CURRENT_PROJECT_VERSION = 99; */
    // MARKETING_VERSION = 8.8; CURRENT_PROJECT_VERSION = 88;
}
EOF
COMMENT_SAFE_COMMIT="$(commit_fixture 'commented declarations')"
run_plan "$BASE_COMMIT" "$COMMENT_SAFE_COMMIT"
assert_status 0
assert_output $'release=true\ntag=v1.0.1\nversion=1.0.1\nbuild=2'

# An unmatched quote inside a block comment must not hide a later conflict.
git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT"
cat > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj" <<'EOF'
// Unmatched quote comment project fixture
{
    settings = {
        MARKETING_VERSION = 1.0.1;
        CURRENT_PROJECT_VERSION = 2;
    };
    /* comment contains an unmatched " quote
     */
    MARKETING_VERSION = 1.0.2; CURRENT_PROJECT_VERSION = 2;
    "
}
EOF
UNMATCHED_QUOTE_COMMIT="$(commit_fixture 'unmatched quote comment')"
assert_plan_failure "$BASE_COMMIT" "$UNMATCHED_QUOTE_COMMIT"

# A quoted URL containing // must not hide a later real conflict.
git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT"
cat > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj" <<'EOF'
// Quoted URL project fixture
{
    settings = {
        MARKETING_VERSION = 1.0.1;
        CURRENT_PROJECT_VERSION = 2;
        UPDATE_URL = "https://updates.invalid/app"; MARKETING_VERSION = 1.0.2; CURRENT_PROJECT_VERSION = 2;
    };
}
EOF
QUOTED_URL_CONFLICT_COMMIT="$(commit_fixture 'quoted URL conflict')"
assert_plan_failure "$BASE_COMMIT" "$QUOTED_URL_CONFLICT_COMMIT"

# Every declaration at a revision must agree on one numeric value.
write_project '1.0.1' '2' '1.0.2' '2'
printf 'inconsistent marketing declarations\n' >> "$REPOSITORY/SwitchTab/App.swift"
INCONSISTENT_MARKETING_COMMIT="$(commit_fixture 'inconsistent marketing declarations')"
assert_plan_failure "$BASE_COMMIT" "$INCONSISTENT_MARKETING_COMMIT"

write_project '1.0.1' '2' '1.0.1' '3'
INCONSISTENT_BUILD_COMMIT="$(commit_fixture 'inconsistent build declarations')"
assert_plan_failure "$BASE_COMMIT" "$INCONSISTENT_BUILD_COMMIT"

# Docs/spec metadata includes files below docs/ and specs/, but workflows and scripts remain relevant.
git -C "$REPOSITORY" checkout --quiet "$BASE_COMMIT"
rm -rf "$REPOSITORY/docs" "$REPOSITORY/specs" "$REPOSITORY/.github" "$REPOSITORY/scripts"
mkdir -p "$REPOSITORY/docs" "$REPOSITORY/specs" "$REPOSITORY/.github/workflows" "$REPOSITORY/scripts"
printf 'design note\n' > "$REPOSITORY/docs/design.txt"
printf 'spec metadata\n' > "$REPOSITORY/specs/metadata.json"
DOC_METADATA_COMMIT="$(commit_fixture 'docs metadata only')"
run_plan "$BASE_COMMIT" "$DOC_METADATA_COMMIT"
assert_status 0
assert_output 'release=false'

printf 'name: CI\n' > "$REPOSITORY/.github/workflows/check.yml"
WORKFLOW_COMMIT="$(commit_fixture 'workflow change')"
assert_plan_failure "$BASE_COMMIT" "$WORKFLOW_COMMIT"

printf '#!/usr/bin/env bash\n' > "$REPOSITORY/scripts/check.sh"
SCRIPT_CHANGE_COMMIT="$(commit_fixture 'script change')"
assert_plan_failure "$BASE_COMMIT" "$SCRIPT_CHANGE_COMMIT"

bash -n "$SCRIPT_SOURCE"
bash -n "$0"

echo 'plan-release contract tests passed'
