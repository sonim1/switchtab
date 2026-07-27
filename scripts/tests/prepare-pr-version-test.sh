#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/prepare-pr-version.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-prepare-pr-version.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

REPOSITORY="$TEMP_ROOT/repository"
mkdir -p "$REPOSITORY/SwitchTab.xcodeproj" "$REPOSITORY/SwitchTab"
git -C "$REPOSITORY" init -q
git -C "$REPOSITORY" config user.name 'SwitchTab Test'
git -C "$REPOSITORY" config user.email 'switchtab@example.invalid'

write_project() {
    local marketing_version="$1"
    local build_version="$2"
    local second_marketing_version="${3:-$marketing_version}"
    local second_build_version="${4:-$build_version}"

    cat > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj" <<EOF
// MARKETING_VERSION = 99.99.99; CURRENT_PROJECT_VERSION = 999;
{
    quoted = "MARKETING_VERSION = 88.88.88; CURRENT_PROJECT_VERSION = 888;";
    debug = {
        CURRENT_PROJECT_VERSION = $build_version;
        MARKETING_VERSION = $marketing_version;
    };
    release = {
        CURRENT_PROJECT_VERSION = $second_build_version;
        MARKETING_VERSION = $second_marketing_version;
    };
}
EOF
}

commit_all() {
    local message="$1"
    git -C "$REPOSITORY" add -A
    git -C "$REPOSITORY" commit --quiet -m "$message"
    git -C "$REPOSITORY" rev-parse HEAD
}

write_project '1.0.4' '5'
printf 'import Foundation\n' > "$REPOSITORY/SwitchTab/App.swift"
printf '# SwitchTab\n' > "$REPOSITORY/README.md"
BASE_COMMIT="$(commit_all 'base')"

checkout_base() {
    git -C "$REPOSITORY" reset --hard --quiet
    git -C "$REPOSITORY" checkout --quiet --detach "$BASE_COMMIT"
}

run_prepare() {
    set +e
    PREPARE_OUTPUT="$(
        cd -- "$REPOSITORY"
        "$SCRIPT_SOURCE" "$@" 2>&1
    )"
    PREPARE_STATUS=$?
    set -e
}

assert_status() {
    local expected="$1"
    [[ "$PREPARE_STATUS" -eq "$expected" ]] || \
        fail "expected status $expected, got $PREPARE_STATUS: $PREPARE_OUTPUT"
}

assert_output_contains() {
    local expected="$1"
    [[ "$PREPARE_OUTPUT" == *"$expected"* ]] || \
        fail "output did not contain <$expected>: $PREPARE_OUTPUT"
}

assert_project_versions() {
    local expected_marketing="$1"
    local expected_build="$2"
    local project
    project="$(<"$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj")"

    [[ "$(grep -Ec "^[[:space:]]*MARKETING_VERSION = $expected_marketing;$" <<< "$project")" -eq 2 ]] || \
        fail "expected both active marketing versions to be $expected_marketing"
    [[ "$(grep -Ec "^[[:space:]]*CURRENT_PROJECT_VERSION = $expected_build;$" <<< "$project")" -eq 2 ]] || \
        fail "expected both active build versions to be $expected_build"
    [[ "$project" == *'MARKETING_VERSION = 99.99.99; CURRENT_PROJECT_VERSION = 999;'* ]] || \
        fail 'commented declarations were changed'
    [[ "$project" == *'MARKETING_VERSION = 88.88.88; CURRENT_PROJECT_VERSION = 888;'* ]] || \
        fail 'quoted declarations were changed'
}

create_relevant_head() {
    local name="$1"
    local marketing_version="${2:-1.0.4}"
    local build_version="${3:-5}"

    checkout_base
    write_project "$marketing_version" "$build_version"
    printf 'func %s() {}\n' "$name" >> "$REPOSITORY/SwitchTab/App.swift"
    commit_all "$name"
}

# Invalid invocation and bump kinds fail without mutating the project.
run_prepare
assert_status 64

INVALID_HEAD="$(create_relevant_head invalid_kind)"
run_prepare "$BASE_COMMIT" "$INVALID_HEAD" banana
assert_status 65
assert_output_contains 'release kind'

# Patch is the default policy result and replaces manual head values exactly.
PATCH_HEAD="$(create_relevant_head patch_manual 9.9.9 99)"
run_prepare "$BASE_COMMIT" "$PATCH_HEAD" patch
assert_status 0
assert_output_contains 'release=true'
assert_output_contains 'changed=true'
assert_output_contains 'ready=false'
assert_output_contains 'version=1.0.5'
assert_output_contains 'build=6'
assert_project_versions '1.0.5' '6'
[[ "$(git -C "$REPOSITORY" diff --name-only)" == 'SwitchTab.xcodeproj/project.pbxproj' ]] || \
    fail 'version preparation changed an unexpected file'

# Re-running against the same working tree is idempotent and ready to verify.
run_prepare "$BASE_COMMIT" "$PATCH_HEAD" patch
assert_status 0
assert_output_contains 'changed=false'
assert_output_contains 'ready=true'
assert_project_versions '1.0.5' '6'

MINOR_HEAD="$(create_relevant_head minor)"
run_prepare "$BASE_COMMIT" "$MINOR_HEAD" minor
assert_status 0
assert_output_contains 'version=1.1.0'
assert_output_contains 'build=6'
assert_project_versions '1.1.0' '6'

MAJOR_HEAD="$(create_relevant_head major)"
run_prepare "$BASE_COMMIT" "$MAJOR_HEAD" major
assert_status 0
assert_output_contains 'version=2.0.0'
assert_output_contains 'build=6'
assert_project_versions '2.0.0' '6'

# Documentation-only changes never alter the project or emit a release.
checkout_base
printf '\nDocs only.\n' >> "$REPOSITORY/README.md"
DOCS_HEAD="$(commit_all 'docs only')"
PROJECT_BEFORE="$(<"$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj")"
run_prepare "$BASE_COMMIT" "$DOCS_HEAD" major
assert_status 0
[[ "$PREPARE_OUTPUT" == $'release=false\nchanged=false\nready=true' ]] || \
    fail "unexpected docs-only output: $PREPARE_OUTPUT"
[[ "$(<"$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj")" == "$PROJECT_BEFORE" ]] || \
    fail 'docs-only preparation changed the project'

# Output files contain the same machine-readable result.
OUTPUT_FILE="$TEMP_ROOT/output.env"
run_prepare "$BASE_COMMIT" "$DOCS_HEAD" patch "$OUTPUT_FILE"
assert_status 0
[[ -f "$OUTPUT_FILE" && "$(<"$OUTPUT_FILE")" == "$PREPARE_OUTPUT" ]] || \
    fail 'output file did not match stdout'

# The base version is trusted input and must be consistent and well formed.
checkout_base
write_project '1.0.4' '5' '1.0.5' '5'
BAD_BASE="$(commit_all 'inconsistent base')"
printf 'func badBase() {}\n' >> "$REPOSITORY/SwitchTab/App.swift"
BAD_HEAD="$(commit_all 'head from inconsistent base')"
run_prepare "$BAD_BASE" "$BAD_HEAD" patch
assert_status 65
assert_output_contains 'inconsistent'

checkout_base
write_project '1.0.4' '5.1'
BAD_BUILD_BASE="$(commit_all 'dotted build base')"
printf 'func badBuild() {}\n' >> "$REPOSITORY/SwitchTab/App.swift"
BAD_BUILD_HEAD="$(commit_all 'head from dotted build base')"
run_prepare "$BAD_BUILD_BASE" "$BAD_BUILD_HEAD" patch
assert_status 65
assert_output_contains 'integer'

# Missing head declarations fail instead of producing a partial edit.
checkout_base
printf '{ objects = {}; }\n' > "$REPOSITORY/SwitchTab.xcodeproj/project.pbxproj"
printf 'func missing() {}\n' >> "$REPOSITORY/SwitchTab/App.swift"
MISSING_HEAD="$(commit_all 'missing head declarations')"
run_prepare "$BASE_COMMIT" "$MISSING_HEAD" patch
assert_status 65
assert_output_contains 'missing'

echo 'prepare-pr-version-test: PASS'
