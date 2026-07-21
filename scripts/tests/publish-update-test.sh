#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/scripts/publish-update.sh"

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

assert_failed() {
    if [[ "$status" -eq 0 ]]; then
        fail "expected failure; output: $output"
    fi
}

assert_output_contains() {
    local expected="$1"

    if [[ "$output" != *"$expected"* ]]; then
        fail "expected output to contain '$expected'; output: $output"
    fi
}

assert_no_uploads() {
    if [[ -s "$WRANGLER_LOG" ]]; then
        fail "unexpected upload(s): $(<"$WRANGLER_LOG")"
    fi
}

assert_no_appcast_upload() {
    if grep -Fq '/appcast.xml ' "$WRANGLER_LOG" 2>/dev/null; then
        fail "appcast was uploaded unexpectedly"
    fi
}

[[ -f "$SCRIPT_SOURCE" ]] || fail "scripts/publish-update.sh is missing"
[[ -x "$SCRIPT_SOURCE" ]] || fail "scripts/publish-update.sh is not executable"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/switchtab-publish-update.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FIXTURE_ROOT="$TEMP_ROOT/project"
FIXTURE_SCRIPT="$FIXTURE_ROOT/scripts/publish-update.sh"
ARTIFACT_DIR="$FIXTURE_ROOT/.build/direct-distribution/updates"
PUBLIC_DIR="$TEMP_ROOT/public"
BIN_DIR="$TEMP_ROOT/bin"
WRANGLER_LOG="$TEMP_ROOT/wrangler.log"
CURL_LOG="$TEMP_ROOT/curl.log"
DMG_NAME='SwitchTab-1.2-7.dmg'
DMG_URL="https://updates.test.example/$DMG_NAME"
TRACE_SECRET='trace-cloudflare-secret'
TRACE_CONFIG="$TEMP_ROOT/release.env"

mkdir -p "$FIXTURE_ROOT/scripts" "$ARTIFACT_DIR" "$PUBLIC_DIR" "$BIN_DIR"
cp "$SCRIPT_SOURCE" "$FIXTURE_SCRIPT"
chmod +x "$FIXTURE_SCRIPT"
printf "CLOUDFLARE_API_TOKEN='%s'\n" "$TRACE_SECRET" > "$TRACE_CONFIG"

cat > "$BIN_DIR/wrangler" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$WRANGLER_LOG"
if [[ "${FAKE_WRANGLER_STATUS:-0}" -ne 0 ]]; then
    echo "fake Wrangler failure" >&2
    exit "$FAKE_WRANGLER_STATUS"
fi

[[ "${1:-}" == r2 && "${2:-}" == object && "${3:-}" == put ]] || exit 91
bucket_key="${4:-}"
shift 4
remote=''
file=''
content_type=''
cache_control=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            remote=1
            shift
            ;;
        --file)
            file="$2"
            shift 2
            ;;
        --content-type)
            content_type="$2"
            shift 2
            ;;
        --cache-control)
            cache_control="$2"
            shift 2
            ;;
        *)
            exit 92
            ;;
    esac
done
[[ -n "$remote" && -f "$file" && -n "$content_type" && -n "$cache_control" ]] || exit 93
key="${bucket_key#*/}"
[[ "$key" != "$bucket_key" && -n "$key" ]] || exit 94
mkdir -p "$(dirname -- "$PUBLIC_DIR/$key")"
cp "$file" "$PUBLIC_DIR/$key"
EOF

cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_path=''
write_out=''
url=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            output_path="$2"
            shift 2
            ;;
        --write-out)
            write_out="$2"
            shift 2
            ;;
        --silent|--show-error)
            shift
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done
printf '%s\n' "$url" >> "$CURL_LOG"

if [[ "${FAKE_CURL_TRANSPORT_STATUS:-0}" -ne 0 ]]; then
    echo "fake curl transport failure" >&2
    exit "$FAKE_CURL_TRANSPORT_STATUS"
fi

key="${url#https://updates.test.example/}"
if [[ "$key" == "$url" ]]; then
    echo "unexpected URL: $url" >&2
    exit 95
fi

if [[ -n "${FAKE_HTTP_STATUS:-}" ]]; then
    http_status="$FAKE_HTTP_STATUS"
elif [[ -f "$PUBLIC_DIR/$key" ]]; then
    http_status=200
else
    http_status=404
fi

if [[ -n "$output_path" ]]; then
    : > "$output_path"
    if [[ "$http_status" == 200 ]]; then
        if [[ "${FAKE_CORRUPT_KEY:-}" == "$key" ]]; then
            printf 'corrupt public content\n' > "$output_path"
        elif [[ "${FAKE_BAD_APPCAST:-0}" == 1 && "$key" == appcast.xml ]]; then
            cat > "$output_path" <<'EOF_XML'
<?xml version="1.0"?><rss><channel><item><enclosure url="https://evil.example/SwitchTab-1.2-7.dmg" /></item></channel></rss>
EOF_XML
        else
            cp "$PUBLIC_DIR/$key" "$output_path"
        fi
    fi
fi

if [[ -n "$write_out" ]]; then
    printf '%s' "$http_status"
fi
EOF

cat > "$BIN_DIR/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_HASH_STATUS:-0}" -ne 0 ]]; then
    echo "fake hash failure" >&2
    exit "$FAKE_HASH_STATUS"
fi
exec /usr/bin/shasum "$@"
EOF

cat > "$BIN_DIR/xmllint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_XML_STATUS:-0}" -ne 0 ]]; then
    echo "fake XML failure" >&2
    exit "$FAKE_XML_STATUS"
fi
exec /usr/bin/xmllint "$@"
EOF

chmod +x "$BIN_DIR"/*

write_appcast() {
    local enclosure_url="$1"
    local count="${2:-1}"

    if [[ "$count" == 0 ]]; then
        printf '%s\n' '<?xml version="1.0"?><rss><channel><item /></channel></rss>' > "$ARTIFACT_DIR/appcast.xml"
    elif [[ "$count" == 2 ]]; then
        cat > "$ARTIFACT_DIR/appcast.xml" <<EOF_XML
<?xml version="1.0"?><rss><channel><item><enclosure url="$enclosure_url" /><enclosure url="$enclosure_url" /></item></channel></rss>
EOF_XML
    else
        cat > "$ARTIFACT_DIR/appcast.xml" <<EOF_XML
<?xml version="1.0"?><rss><channel><item><enclosure url="$enclosure_url" /></item></channel></rss>
EOF_XML
    fi
}

reset_fixture() {
    rm -rf "$ARTIFACT_DIR" "$PUBLIC_DIR"
    mkdir -p "$ARTIFACT_DIR" "$PUBLIC_DIR"
    : > "$WRANGLER_LOG"
    : > "$CURL_LOG"
    unset FAKE_WRANGLER_STATUS FAKE_CURL_TRANSPORT_STATUS FAKE_HTTP_STATUS \
        FAKE_CORRUPT_KEY FAKE_BAD_APPCAST FAKE_HASH_STATUS FAKE_XML_STATUS \
        RELEASE_CONFIG_PATH
    printf 'fixture dmg content\n' > "$ARTIFACT_DIR/$DMG_NAME"
    (
        cd "$ARTIFACT_DIR"
        /usr/bin/shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
    )
    write_appcast "$DMG_URL"
}

invoke_script() {
    set +e
    output="$(
        cd /
        env \
            RELEASE_CONFIG_PATH="${RELEASE_CONFIG_PATH:-$TEMP_ROOT/missing.env}" \
            R2_BUCKET_NAME='switchtab-updates' \
            UPDATE_DOMAIN='updates.test.example' \
            UPDATE_ARTIFACT_DIR="$ARTIFACT_DIR" \
            WRANGLER_BIN="$BIN_DIR/wrangler" \
            CURL_BIN="$BIN_DIR/curl" \
            SHASUM_BIN="$BIN_DIR/shasum" \
            XMLLINT_BIN="$BIN_DIR/xmllint" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            CURL_LOG="$CURL_LOG" \
            PUBLIC_DIR="$PUBLIC_DIR" \
            FAKE_WRANGLER_STATUS="${FAKE_WRANGLER_STATUS:-0}" \
            FAKE_CURL_TRANSPORT_STATUS="${FAKE_CURL_TRANSPORT_STATUS:-0}" \
            FAKE_HTTP_STATUS="${FAKE_HTTP_STATUS:-}" \
            FAKE_CORRUPT_KEY="${FAKE_CORRUPT_KEY:-}" \
            FAKE_BAD_APPCAST="${FAKE_BAD_APPCAST:-0}" \
            FAKE_HASH_STATUS="${FAKE_HASH_STATUS:-0}" \
            FAKE_XML_STATUS="${FAKE_XML_STATUS:-0}" \
            "$FIXTURE_SCRIPT" "$@" 2>&1
    )"
    status=$?
    set -e
}

invoke_trace_script() {
    set +e
    output="$(
        cd /
        env \
            RELEASE_CONFIG_PATH="$TRACE_CONFIG" \
            R2_BUCKET_NAME='switchtab-updates' \
            UPDATE_DOMAIN='updates.test.example' \
            UPDATE_ARTIFACT_DIR="$ARTIFACT_DIR" \
            WRANGLER_BIN="$BIN_DIR/wrangler" \
            CURL_BIN="$BIN_DIR/curl" \
            SHASUM_BIN="$BIN_DIR/shasum" \
            XMLLINT_BIN="$BIN_DIR/xmllint" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            CURL_LOG="$CURL_LOG" \
            PUBLIC_DIR="$PUBLIC_DIR" \
            bash -x "$FIXTURE_SCRIPT" 2>&1
    )"
    status=$?
    set -e
}

# New versioned artifacts are uploaded before the mutable appcast with exact metadata.
reset_fixture
invoke_script
assert_status 0
assert_output_contains 'https://updates.test.example/appcast.xml'
expected_log="r2 object put switchtab-updates/$DMG_NAME --remote --file $ARTIFACT_DIR/$DMG_NAME --content-type application/x-apple-diskimage --cache-control public, max-age=31536000, immutable
r2 object put switchtab-updates/$DMG_NAME.sha256 --remote --file $ARTIFACT_DIR/$DMG_NAME.sha256 --content-type text/plain --cache-control public, max-age=31536000, immutable
r2 object put switchtab-updates/appcast.xml --remote --file $ARTIFACT_DIR/appcast.xml --content-type application/xml --cache-control public, max-age=60"
[[ "$(<"$WRANGLER_LOG")" == "$expected_log" ]] || fail "unexpected upload order/metadata: $(<"$WRANGLER_LOG")"

# Identical immutable public objects are skipped, while appcast still publishes last.
reset_fixture
cp "$ARTIFACT_DIR/$DMG_NAME" "$PUBLIC_DIR/$DMG_NAME"
cp "$ARTIFACT_DIR/$DMG_NAME.sha256" "$PUBLIC_DIR/$DMG_NAME.sha256"
invoke_script
assert_status 0
[[ "$(wc -l < "$WRANGLER_LOG")" -eq 1 ]] || fail "identical immutable objects were uploaded"
grep -Fq 'r2 object put switchtab-updates/appcast.xml ' "$WRANGLER_LOG" || fail "appcast was not published"

# An existing immutable DMG with different bytes is never overwritten.
reset_fixture
printf 'different remote dmg\n' > "$PUBLIC_DIR/$DMG_NAME"
invoke_script
assert_failed
assert_output_contains 'differs'
assert_no_uploads

# An existing immutable checksum with different bytes is never overwritten.
reset_fixture
cp "$ARTIFACT_DIR/$DMG_NAME" "$PUBLIC_DIR/$DMG_NAME"
printf 'different remote checksum\n' > "$PUBLIC_DIR/$DMG_NAME.sha256"
invoke_script
assert_failed
assert_output_contains 'checksum differs'
assert_no_uploads

# Transport failures preserve a distinctive status and never mean absence.
reset_fixture
FAKE_CURL_TRANSPORT_STATUS=28
invoke_script
assert_status 28
assert_no_uploads

# Non-200/404 HTTP responses fail before any mutation.
reset_fixture
FAKE_HTTP_STATUS=503
invoke_script
assert_failed
assert_output_contains '503'
assert_no_uploads

# The checksum is bound to this exact DMG and validated before probing or uploading.
reset_fixture
printf 'changed local dmg\n' > "$ARTIFACT_DIR/$DMG_NAME"
invoke_script
assert_failed
assert_output_contains 'checksum'
assert_no_uploads
[[ ! -s "$CURL_LOG" ]] || fail "checksum mismatch reached public probes"

reset_fixture
hash="$(/usr/bin/shasum -a 256 "$ARTIFACT_DIR/$DMG_NAME")"
hash="${hash%% *}"
printf '%s  unrelated.dmg\n' "$hash" > "$ARTIFACT_DIR/$DMG_NAME.sha256"
invoke_script
assert_failed
assert_output_contains 'checksum'
assert_no_uploads

# Unsafe or ambiguous enclosure URLs fail before network access.
for bad_case in missing multiple external traversal query encoded_slash nested; do
    reset_fixture
    case "$bad_case" in
        missing) write_appcast "$DMG_URL" 0 ;;
        multiple) write_appcast "$DMG_URL" 2 ;;
        external) write_appcast "https://evil.example/$DMG_NAME" ;;
        traversal) write_appcast 'https://updates.test.example/../SwitchTab-1.2-7.dmg' ;;
        query) write_appcast "$DMG_URL?download=1" ;;
        encoded_slash) write_appcast 'https://updates.test.example/SwitchTab-1.2%2F7.dmg' ;;
        nested) write_appcast "https://updates.test.example/releases/$DMG_NAME" ;;
    esac
    invoke_script
    assert_failed
    assert_no_uploads
    [[ ! -s "$CURL_LOG" ]] || fail "$bad_case enclosure reached public probes"
done

reset_fixture
printf '%s\n' '<rss><unclosed>' > "$ARTIFACT_DIR/appcast.xml"
invoke_script
assert_failed
assert_no_uploads
[[ ! -s "$CURL_LOG" ]] || fail "malformed XML reached public probes"

# Distinctive Wrangler/hash/XML failures are propagated.
reset_fixture
FAKE_WRANGLER_STATUS=73
invoke_script
assert_status 73
assert_no_appcast_upload

reset_fixture
FAKE_HASH_STATUS=42
invoke_script
assert_status 42
assert_no_uploads

reset_fixture
FAKE_XML_STATUS=54
invoke_script
assert_status 54
assert_no_uploads

# Corrupt post-upload public content prevents publishing the appcast.
reset_fixture
FAKE_CORRUPT_KEY="$DMG_NAME"
invoke_script
assert_failed
assert_no_appcast_upload

# The public appcast is validated after it is uploaded and may fail the run.
reset_fixture
FAKE_BAD_APPCAST=1
invoke_script
assert_failed
grep -Fq 'r2 object put switchtab-updates/appcast.xml ' "$WRANGLER_LOG" || fail "appcast validation ran before upload"
[[ "$(tail -n 1 "$WRANGLER_LOG")" == *'/appcast.xml '* ]] || fail "appcast was not the last upload"

# Missing required inputs/tools and unexpected arguments fail before upload.
reset_fixture
rm "$ARTIFACT_DIR/appcast.xml"
invoke_script
assert_status 66
assert_no_uploads

reset_fixture
rm "$ARTIFACT_DIR/$DMG_NAME"
invoke_script
assert_status 66
assert_no_uploads

reset_fixture
rm "$ARTIFACT_DIR/$DMG_NAME.sha256"
invoke_script
assert_status 66
assert_no_uploads

reset_fixture
set +e
output="$(
    cd /
    env RELEASE_CONFIG_PATH="$TEMP_ROOT/missing.env" UPDATE_ARTIFACT_DIR="$ARTIFACT_DIR" \
        WRANGLER_BIN="$TEMP_ROOT/missing-wrangler" CURL_BIN="$BIN_DIR/curl" \
        SHASUM_BIN="$BIN_DIR/shasum" XMLLINT_BIN="$BIN_DIR/xmllint" \
        "$FIXTURE_SCRIPT" 2>&1
)"
status=$?
set -e
assert_status 66

reset_fixture
invoke_script --unexpected
assert_status 64
assert_no_uploads

# Inherited xtrace is disabled before release config credentials are read.
reset_fixture
invoke_trace_script
assert_status 0
[[ "$output" != *"$TRACE_SECRET"* ]] || fail "xtrace exposed the release credential"
[[ "$(<"$WRANGLER_LOG")" != *"$TRACE_SECRET"* ]] || fail "release credential reached Wrangler argv"

/bin/bash -n "$SCRIPT_SOURCE"
/bin/bash -n "$SCRIPT_DIR/publish-update-test.sh"

echo "publish-update contract tests passed"
