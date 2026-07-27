#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

PROJECT_FILE='SwitchTab.xcodeproj/project.pbxproj'

usage() {
    echo 'Usage: scripts/prepare-pr-version.sh <base-commit> <head-commit> <patch|minor|major> [output-file]' >&2
}

reject() {
    echo "prepare PR version rejected: $1" >&2
    exit 65
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
    usage
    exit 64
fi

BASE_INPUT="$1"
HEAD_INPUT="$2"
RELEASE_KIND="$3"
OUTPUT_FILE="${4:-}"

case "$RELEASE_KIND" in
    patch|minor|major) ;;
    *) reject "release kind must be patch, minor, or major: $RELEASE_KIND" ;;
esac

REPOSITORY_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || \
    reject 'current directory is not a git repository'
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
CURRENT_HEAD="$(git rev-parse --verify HEAD 2>/dev/null)" || reject 'could not resolve the checked-out HEAD'
[[ "$CURRENT_HEAD" == "$HEAD_COMMIT" ]] || \
    reject "checked-out HEAD does not match requested head commit: $CURRENT_HEAD"

for revision in "$BASE_COMMIT" "$HEAD_COMMIT"; do
    object_type="$(git cat-file -t "$revision:$PROJECT_FILE" 2>/dev/null || true)"
    [[ "$object_type" == 'blob' ]] || reject "$PROJECT_FILE is missing at $revision"
done
[[ -f "$PROJECT_FILE" && ! -L "$PROJECT_FILE" ]] || reject "$PROJECT_FILE is not a regular file"

emit() {
    local result="$1"

    if [[ -n "$OUTPUT_FILE" ]]; then
        printf '%s\n' "$result" > "$OUTPUT_FILE"
    fi
    printf '%s\n' "$result"
}

DOCS_ONLY=1
while IFS= read -r -d '' changed_path; do
    case "$changed_path" in
        *.md|*.markdown|docs/*|specs/*) ;;
        *) DOCS_ONLY=0 ;;
    esac
done < <(git diff --name-only -z --no-renames "$BASE_COMMIT" "$HEAD_COMMIT")

if [[ "$DOCS_ONLY" -eq 1 ]]; then
    emit $'release=false\nchanged=false\nready=true'
    exit 0
fi

set +e
PREPARE_RESULT="$(
    /usr/bin/ruby - "$BASE_COMMIT" "$PROJECT_FILE" "$RELEASE_KIND" <<'RUBY'
require "open3"

class PreparationError < StandardError; end

def sanitized(source)
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
      elsif character == '"' || character == "'"
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

  text
end

def declarations(source, variable)
  scrubbed = sanitized(source)
  pattern = /(?:\A|[^A-Za-z0-9_])#{Regexp.escape(variable)}[[:space:]]*=[[:space:]]*([^;[:space:]]+)/
  matches = []
  offset = 0

  while (match = pattern.match(scrubbed, offset))
    matches << [match[1], match.begin(1), match.end(1)]
    offset = match.end(0)
  end
  matches
end

def one_base_value(source, variable, pattern, description)
  values = declarations(source, variable).map(&:first)
  raise PreparationError, "#{variable} is missing from the base commit" if values.empty?

  invalid = values.find { |value| !pattern.match?(value) }
  raise PreparationError, "#{variable} base value must be #{description}: #{invalid}" if invalid

  unique = values.uniq
  if unique.length != 1
    raise PreparationError, "#{variable} declarations in the base commit are inconsistent: #{unique.join(' and ')}"
  end
  unique.first
end

begin
base_commit, project_file, release_kind = ARGV
base_source, status = Open3.capture2e("git", "show", "#{base_commit}:#{project_file}")
raise PreparationError, "could not read #{project_file} from the base commit" unless status.success?

marketing = one_base_value(
  base_source,
  "MARKETING_VERSION",
  /\A[0-9]+(?:\.[0-9]+){0,2}\z/,
  "one to three numeric components",
)
build = one_base_value(
  base_source,
  "CURRENT_PROJECT_VERSION",
  /\A[0-9]+\z/,
  "a non-negative integer",
)

components = marketing.split(".").map { |component| Integer(component, 10) }
components.fill(0, components.length...3)
case release_kind
when "patch"
  components[2] += 1
when "minor"
  components[1] += 1
  components[2] = 0
when "major"
  components[0] += 1
  components[1] = 0
  components[2] = 0
else
  raise PreparationError, "unsupported release kind: #{release_kind}"
end
target_marketing = components.join(".")
target_build = (Integer(build, 10) + 1).to_s

head_source = File.binread(project_file)
replacements = []
{
  "MARKETING_VERSION" => target_marketing,
  "CURRENT_PROJECT_VERSION" => target_build,
}.each do |variable, target|
  matches = declarations(head_source, variable)
  raise PreparationError, "#{variable} is missing from the pull-request head" if matches.empty?

  matches.each do |_value, start_index, end_index|
    replacements << [start_index, end_index, target]
  end
end

updated = head_source.dup
replacements.sort_by { |_start_index, end_index, _target| -end_index }.each do |start_index, end_index, target|
  updated[start_index...end_index] = target
end
changed = updated != head_source
File.binwrite(project_file, updated) if changed

puts "release=true"
puts "changed=#{changed}"
puts "ready=#{!changed}"
puts "version=#{target_marketing}"
puts "build=#{target_build}"
rescue PreparationError, Errno::EACCES, Errno::ENOENT, Errno::EISDIR => error
  warn "prepare PR version rejected: #{error.message}"
  exit 65
end
RUBY
)"
PREPARE_STATUS=$?
set -e

if [[ "$PREPARE_STATUS" -ne 0 ]]; then
    exit "$PREPARE_STATUS"
fi

emit "$PREPARE_RESULT"
