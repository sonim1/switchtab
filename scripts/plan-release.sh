#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

PROJECT_FILE='SwitchTab.xcodeproj/project.pbxproj'

usage() {
    echo "Usage: scripts/plan-release.sh <base-commit> <head-commit> [output-file]" >&2
}

reject() {
    echo "release plan rejected: $1" >&2
    exit 65
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage
    exit 64
fi

BASE_INPUT="$1"
HEAD_INPUT="$2"
OUTPUT_FILE="${3:-}"

REPOSITORY_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || reject 'current directory is not a git repository'
cd -- "$REPOSITORY_ROOT"

resolve_commit() {
    local input="$1"
    local resolved

    if ! resolved="$(git rev-parse --verify --quiet --end-of-options "$input^{commit}" 2>/dev/null)"; then
        reject "commit does not exist: $input"
    fi
    [[ -n "$resolved" ]] || reject "commit does not exist: $input"
    printf '%s\n' "$resolved"
}

BASE_COMMIT="$(resolve_commit "$BASE_INPUT")"
HEAD_COMMIT="$(resolve_commit "$HEAD_INPUT")"

require_project_file() {
    local revision="$1"
    local object_type

    object_type="$(git cat-file -t "$revision:$PROJECT_FILE" 2>/dev/null || true)"
    [[ "$object_type" == 'blob' ]] || reject "$PROJECT_FILE is missing at $revision"
}

require_project_file "$BASE_COMMIT"
require_project_file "$HEAD_COMMIT"

is_numeric_dotted() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)*$ ]]
}

extract_version() {
    local revision="$1"
    local variable="$2"
    local project_contents
    local declarations
    local value
    local first_value=''
    local found=0

    if ! project_contents="$(git show "$revision:$PROJECT_FILE" 2>/dev/null)"; then
        reject "could not read $PROJECT_FILE at $revision"
    fi

    if ! declarations="$(
        PROJECT_VARIABLE="$variable" /usr/bin/ruby -e '
            variable = ENV.fetch("PROJECT_VARIABLE")
            source = STDIN.read
            text = +""
            state = :normal
            quote = nil
            index = 0

            while index < source.length
                character = source[index, 1]
                pair = source[index, 2]

                case state
                when :normal
                    if pair == "//"
                        text << "  "
                        state = :line_comment
                        index += 2
                    elsif pair == "/*"
                        text << "  "
                        state = :block_comment
                        index += 2
                    elsif character == 34.chr || character == 39.chr
                        text << " "
                        quote = character
                        state = :quoted
                        index += 1
                    else
                        text << character
                        index += 1
                    end
                when :quoted
                    if character == "\\"
                        escaped = source[index + 1, 1]
                        text << (escaped == "\n" ? " \n" : "  ")
                        index += escaped.nil? ? 1 : 2
                    elsif character == quote
                        text << " "
                        quote = nil
                        state = :normal
                        index += 1
                    elsif character == "\n"
                        text << "\n"
                        index += 1
                    else
                        text << " "
                        index += 1
                    end
                when :line_comment
                    if character == "\n"
                        text << "\n"
                        state = :normal
                    else
                        text << " "
                    end
                    index += 1
                when :block_comment
                    if pair == "*/"
                        text << "  "
                        state = :normal
                        index += 2
                    elsif character == "\n"
                        text << "\n"
                        index += 1
                    else
                        text << " "
                        index += 1
                    end
                end
            end

            pattern = /(?:\A|[^A-Za-z0-9_])#{Regexp.escape(variable)}[[:space:]]*=[[:space:]]*([^;[:space:]]+)/
            while (match = pattern.match(text))
                puts match[1]
                text = text[match.end(0)..] || ""
            end
        ' <<< "$project_contents"
    )"; then
        reject "could not parse $variable at $revision"
    fi

    while IFS= read -r value; do

        if ! is_numeric_dotted "$value"; then
            reject "$variable at $revision must be numeric and dotted: $value"
        fi

        if [[ "$found" -eq 0 ]]; then
            first_value="$value"
            found=1
        elif [[ "$value" != "$first_value" ]]; then
            reject "$variable declarations at $revision are inconsistent: $first_value and $value"
        fi
    done <<< "$declarations"

    [[ "$found" -eq 1 ]] || reject "$variable is missing at $revision"
    printf '%s\n' "$first_value"
}

BASE_MARKETING_VERSION="$(extract_version "$BASE_COMMIT" MARKETING_VERSION)"
HEAD_MARKETING_VERSION="$(extract_version "$HEAD_COMMIT" MARKETING_VERSION)"
BASE_BUILD_VERSION="$(extract_version "$BASE_COMMIT" CURRENT_PROJECT_VERSION)"
HEAD_BUILD_VERSION="$(extract_version "$HEAD_COMMIT" CURRENT_PROJECT_VERSION)"

DOCS_ONLY=1
while IFS= read -r -d '' changed_path; do
    case "$changed_path" in
        *.md|*.markdown|docs/*|specs/*)
            ;;
        *)
            DOCS_ONLY=0
            ;;
    esac
done < <(git diff --name-only -z --no-renames "$BASE_COMMIT" "$HEAD_COMMIT")

emit() {
    local result="$1"

    if [[ -n "$OUTPUT_FILE" ]]; then
        printf '%s\n' "$result" > "$OUTPUT_FILE"
    fi
    printf '%s\n' "$result"
}

if [[ "$DOCS_ONLY" -eq 1 ]]; then
    emit 'release=false'
    exit 0
fi

normalize_component() {
    local component="$1"

    while [[ ${#component} -gt 1 && "${component:0:1}" == '0' ]]; do
        component="${component:1}"
    done
    printf '%s' "$component"
}

version_greater() {
    local left="$1"
    local right="$2"
    local -a left_components=()
    local -a right_components=()
    local max_components
    local index=0
    local left_component
    local right_component

    IFS='.' read -r -a left_components <<< "$left"
    IFS='.' read -r -a right_components <<< "$right"

    max_components="${#left_components[@]}"
    if [[ "${#right_components[@]}" -gt "$max_components" ]]; then
        max_components="${#right_components[@]}"
    fi

    while [[ "$index" -lt "$max_components" ]]; do
        left_component="$(normalize_component "${left_components[$index]:-0}")"
        right_component="$(normalize_component "${right_components[$index]:-0}")"

        if [[ "${#left_component}" -gt "${#right_component}" ]]; then
            return 0
        fi
        if [[ "${#left_component}" -lt "${#right_component}" ]]; then
            return 1
        fi
        if [[ "$left_component" != "$right_component" ]]; then
            [[ "$left_component" > "$right_component" ]]
            return $?
        fi
        index=$((index + 1))
    done

    return 1
}

if ! version_greater "$HEAD_MARKETING_VERSION" "$BASE_MARKETING_VERSION"; then
    reject "MARKETING_VERSION must strictly increase from $BASE_MARKETING_VERSION to $HEAD_MARKETING_VERSION"
fi

if ! version_greater "$HEAD_BUILD_VERSION" "$BASE_BUILD_VERSION"; then
    reject "CURRENT_PROJECT_VERSION must strictly increase from $BASE_BUILD_VERSION to $HEAD_BUILD_VERSION"
fi

emit "release=true
tag=v$HEAD_MARKETING_VERSION
version=$HEAD_MARKETING_VERSION
build=$HEAD_BUILD_VERSION"
