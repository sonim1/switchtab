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
    assert_no_appcast_upload
}

assert_no_appcast_upload() {
    if grep -Fq 'conditional-put appcast.xml' "$MUTATION_LOG" 2>/dev/null; then
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
ORIGIN_DIR="$TEMP_ROOT/origin"
BIN_DIR="$TEMP_ROOT/bin"
WRANGLER_LOG="$TEMP_ROOT/wrangler.log"
CURL_LOG="$TEMP_ROOT/curl.log"
MUTATION_LOG="$TEMP_ROOT/mutation.log"
DMG_NAME='SwitchTab-1.2-7.dmg'
DMG_URL="https://updates.test.example/$DMG_NAME"
TRACE_SECRET='trace-cloudflare-secret'
TRACE_CONFIG="$TEMP_ROOT/release.env"
ACCOUNT_ID='account123'
ACCESS_KEY_ID='fixtureaccesskey'
SECRET_ACCESS_KEY='fixture-secret-value'

mkdir -p "$FIXTURE_ROOT/scripts" "$ARTIFACT_DIR" "$PUBLIC_DIR" "$ORIGIN_DIR" "$BIN_DIR"
cp "$SCRIPT_SOURCE" "$FIXTURE_SCRIPT"
chmod +x "$FIXTURE_SCRIPT"
printf "CLOUDFLARE_API_TOKEN='%s'\n" "$TRACE_SECRET" > "$TRACE_CONFIG"

cat > "$BIN_DIR/wrangler" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${R2_ACCESS_KEY_ID+x}" != x && "${R2_SECRET_ACCESS_KEY+x}" != x ]] || exit 95

printf '%s\n' "$*" >> "$WRANGLER_LOG"
printf 'wrangler %s\n' "$*" >> "$MUTATION_LOG"
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
mkdir -p "$(dirname -- "$ORIGIN_DIR/$key")"
cp "$file" "$ORIGIN_DIR/$key"
EOF

cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for curl_argument in "$@"; do
    [[ "$curl_argument" != *"$EXPECTED_R2_ACCESS_KEY_ID"* ]] || exit 100
    [[ "$curl_argument" != *"$EXPECTED_R2_SECRET_ACCESS_KEY"* ]] || exit 100
done

output_path=''
write_out=''
url=''
method='GET'
sigv4=''
config_from_stdin=''
upload_file=''
if_none_match=''
if_match=''
content_type=''
cache_control=''
header_path=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            [[ "$2" == - ]] || exit 96
            config_from_stdin=1
            shift 2
            ;;
        --aws-sigv4)
            sigv4="$2"
            shift 2
            ;;
        --request)
            method="$2"
            shift 2
            ;;
        --header)
            case "$2" in
                'If-None-Match: *') if_none_match=1 ;;
                'If-Match: '*) if_match="${2#If-Match: }" ;;
                'Content-Type: '*) content_type="${2#Content-Type: }" ;;
                'Cache-Control: '*) cache_control="${2#Cache-Control: }" ;;
            esac
            shift 2
            ;;
        --dump-header)
            header_path="$2"
            shift 2
            ;;
        --upload-file)
            upload_file="$2"
            shift 2
            ;;
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

curl_config=''
if [[ -n "$config_from_stdin" ]]; then
    curl_config="$(</dev/stdin)"
    [[ "$curl_config" == "user = \"$EXPECTED_R2_ACCESS_KEY_ID:$EXPECTED_R2_SECRET_ACCESS_KEY\"" ]] || exit 97
fi
conditional=''
if [[ -n "$if_none_match" ]]; then
    conditional='none:*'
elif [[ -n "$if_match" ]]; then
    conditional="match:$if_match"
fi
printf 'method=%s url=%s sigv4=%s conditional=%s type=%s cache=%s config-stdin=%s\n' \
    "$method" "$url" "$sigv4" "$conditional" "$content_type" "$cache_control" "$config_from_stdin" >> "$CURL_LOG"

is_origin=''
origin_prefix="https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com/$R2_BUCKET_NAME/"
if [[ "$url" == "$origin_prefix"* ]]; then
    is_origin=1
    key="${url#"$origin_prefix"}"
    [[ "$sigv4" == 'aws:amz:auto:s3' && -n "$config_from_stdin" ]] || exit 98
else
    key="${url#https://updates.test.example/}"
    if [[ "$key" == "$url" ]]; then
        echo "unexpected URL: $url" >&2
        exit 95
    fi
fi

if [[ "$method" == PUT ]]; then
    printf 'conditional-put %s\n' "$key" >> "$MUTATION_LOG"
    if [[ "${FAKE_PUT_TRANSPORT_STATUS:-0}" -ne 0 ]]; then
        echo "fake conditional PUT transport failure" >&2
        exit "$FAKE_PUT_TRANSPORT_STATUS"
    fi
    [[ -n "$is_origin" && -f "$upload_file" ]] || exit 99
    if [[ -n "${FAKE_APPCAST_RACE_FILE:-}" && "$key" == appcast.xml \
        && ! -e "$ORIGIN_DIR/.appcast-race-served" ]]; then
        cp "$FAKE_APPCAST_RACE_FILE" "$ORIGIN_DIR/appcast.xml"
        cp "$FAKE_APPCAST_RACE_FILE" "$PUBLIC_DIR/appcast.xml"
        touch "$ORIGIN_DIR/.appcast-race-served"
    fi
    if [[ -n "${FAKE_PUT_HTTP_STATUS:-}" ]]; then
        http_status="$FAKE_PUT_HTTP_STATUS"
    elif [[ -n "$if_none_match" ]]; then
        if [[ -f "$ORIGIN_DIR/$key" ]]; then
            http_status=412
        else
            http_status=200
        fi
    elif [[ -n "$if_match" ]]; then
        if [[ -f "$ORIGIN_DIR/$key" ]]; then
            current_hash="$(/usr/bin/shasum -a 256 "$ORIGIN_DIR/$key")"
            current_hash="${current_hash%% *}"
            current_etag="\"$current_hash\""
            if [[ "$if_match" == "$current_etag" ]]; then
                http_status=200
            else
                http_status=412
            fi
        else
            http_status=412
        fi
    else
        exit 99
    fi
    if [[ "$http_status" == 200 ]]; then
        mkdir -p "$(dirname -- "$ORIGIN_DIR/$key")" "$(dirname -- "$PUBLIC_DIR/$key")"
        cp "$upload_file" "$ORIGIN_DIR/$key"
        cp "$upload_file" "$PUBLIC_DIR/$key"
    fi
    [[ -z "$output_path" ]] || : > "$output_path"
    [[ -z "$write_out" ]] || printf '%s' "$http_status"
    exit 0
fi

if [[ "${FAKE_CURL_TRANSPORT_STATUS:-0}" -ne 0 ]]; then
    echo "fake curl transport failure" >&2
    exit "$FAKE_CURL_TRANSPORT_STATUS"
fi

if [[ -n "${FAKE_HTTP_STATUS:-}" ]]; then
    http_status="$FAKE_HTTP_STATUS"
elif [[ -n "$is_origin" && -f "$ORIGIN_DIR/$key" ]]; then
    http_status=200
elif [[ -n "$is_origin" ]]; then
    http_status=404
elif [[ "${FAKE_PUBLIC_STALE_ONCE_KEY:-}" == "$key" && ! -f "$PUBLIC_DIR/.stale-served-$key" ]]; then
    http_status=404
    touch "$PUBLIC_DIR/.stale-served-$key"
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
            if [[ -n "$is_origin" ]]; then
                cp "$ORIGIN_DIR/$key" "$output_path"
            else
                cp "$PUBLIC_DIR/$key" "$output_path"
            fi
        fi
    fi
fi

if [[ -n "$header_path" ]]; then
    : > "$header_path"
    if [[ "$http_status" == 200 ]]; then
        if [[ -n "$is_origin" ]]; then
            header_hash="$(/usr/bin/shasum -a 256 "$ORIGIN_DIR/$key")"
        else
            header_hash="$(/usr/bin/shasum -a 256 "$PUBLIC_DIR/$key")"
        fi
        header_hash="${header_hash%% *}"
        printf 'HTTP/1.1 200 OK\r\nETag: "%s"\r\n\r\n' "$header_hash" > "$header_path"
    else
        printf 'HTTP/1.1 %s Fixture\r\n\r\n' "$http_status" > "$header_path"
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
    local build_version="${3-7}"
    local destination="${4:-$ARTIFACT_DIR/appcast.xml}"

    if [[ "$count" == 0 ]]; then
        printf '%s\n' '<?xml version="1.0"?><rss><channel><item /></channel></rss>' > "$destination"
    elif [[ "$count" == 2 ]]; then
        cat > "$destination" <<EOF_XML
<?xml version="1.0"?><rss xmlns:sparkle="https://sparkle-project.org/xml-namespaces/sparkle"><channel><item><enclosure url="$enclosure_url" sparkle:version="$build_version" /><enclosure url="$enclosure_url" sparkle:version="$build_version" /></item></channel></rss>
EOF_XML
    else
        cat > "$destination" <<EOF_XML
<?xml version="1.0"?><rss xmlns:sparkle="https://sparkle-project.org/xml-namespaces/sparkle"><channel><item><enclosure url="$enclosure_url" sparkle:version="$build_version" /></item></channel></rss>
EOF_XML
    fi
}

reset_fixture() {
    rm -rf "$ARTIFACT_DIR" "$PUBLIC_DIR" "$ORIGIN_DIR"
    mkdir -p "$ARTIFACT_DIR" "$PUBLIC_DIR" "$ORIGIN_DIR"
    : > "$WRANGLER_LOG"
    : > "$CURL_LOG"
    : > "$MUTATION_LOG"
    unset FAKE_WRANGLER_STATUS FAKE_CURL_TRANSPORT_STATUS FAKE_HTTP_STATUS \
        FAKE_CORRUPT_KEY FAKE_BAD_APPCAST FAKE_HASH_STATUS FAKE_XML_STATUS \
        FAKE_PUT_TRANSPORT_STATUS FAKE_PUT_HTTP_STATUS FAKE_PUBLIC_STALE_ONCE_KEY \
        FAKE_APPCAST_RACE_FILE \
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
            R2_BUCKET_NAME='switchtab' \
            UPDATE_DOMAIN='updates.test.example' \
            CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID" \
            R2_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
            R2_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
            EXPECTED_R2_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
            EXPECTED_R2_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
            UPDATE_ARTIFACT_DIR="$ARTIFACT_DIR" \
            WRANGLER_BIN="$BIN_DIR/wrangler" \
            CURL_BIN="$BIN_DIR/curl" \
            SHASUM_BIN="$BIN_DIR/shasum" \
            XMLLINT_BIN="$BIN_DIR/xmllint" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            CURL_LOG="$CURL_LOG" \
            MUTATION_LOG="$MUTATION_LOG" \
            PUBLIC_DIR="$PUBLIC_DIR" \
            ORIGIN_DIR="$ORIGIN_DIR" \
            FAKE_WRANGLER_STATUS="${FAKE_WRANGLER_STATUS:-0}" \
            FAKE_CURL_TRANSPORT_STATUS="${FAKE_CURL_TRANSPORT_STATUS:-0}" \
            FAKE_HTTP_STATUS="${FAKE_HTTP_STATUS:-}" \
            FAKE_CORRUPT_KEY="${FAKE_CORRUPT_KEY:-}" \
            FAKE_BAD_APPCAST="${FAKE_BAD_APPCAST:-0}" \
            FAKE_HASH_STATUS="${FAKE_HASH_STATUS:-0}" \
            FAKE_XML_STATUS="${FAKE_XML_STATUS:-0}" \
            FAKE_PUT_TRANSPORT_STATUS="${FAKE_PUT_TRANSPORT_STATUS:-0}" \
            FAKE_PUT_HTTP_STATUS="${FAKE_PUT_HTTP_STATUS:-}" \
            FAKE_PUBLIC_STALE_ONCE_KEY="${FAKE_PUBLIC_STALE_ONCE_KEY:-}" \
            FAKE_APPCAST_RACE_FILE="${FAKE_APPCAST_RACE_FILE:-}" \
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
            R2_BUCKET_NAME='switchtab' \
            UPDATE_DOMAIN='updates.test.example' \
            CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID" \
            R2_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
            R2_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
            EXPECTED_R2_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
            EXPECTED_R2_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
            UPDATE_ARTIFACT_DIR="$ARTIFACT_DIR" \
            WRANGLER_BIN="$BIN_DIR/wrangler" \
            CURL_BIN="$BIN_DIR/curl" \
            SHASUM_BIN="$BIN_DIR/shasum" \
            XMLLINT_BIN="$BIN_DIR/xmllint" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            CURL_LOG="$CURL_LOG" \
            MUTATION_LOG="$MUTATION_LOG" \
            PUBLIC_DIR="$PUBLIC_DIR" \
            ORIGIN_DIR="$ORIGIN_DIR" \
            bash -x "$FIXTURE_SCRIPT" 2>&1
    )"
    status=$?
    set -e
}

invoke_with_missing_r2_credential() {
    local missing="$1"
    local credential_env=()

    case "$missing" in
        account)
            credential_env=("R2_ACCESS_KEY_ID=$ACCESS_KEY_ID" "R2_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY")
            ;;
        access)
            credential_env=("CLOUDFLARE_ACCOUNT_ID=$ACCOUNT_ID" "R2_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY")
            ;;
        secret)
            credential_env=("CLOUDFLARE_ACCOUNT_ID=$ACCOUNT_ID" "R2_ACCESS_KEY_ID=$ACCESS_KEY_ID")
            ;;
        *)
            fail "unknown missing credential fixture: $missing"
            ;;
    esac

    set +e
    output="$(
        cd /
        env -u CLOUDFLARE_ACCOUNT_ID -u R2_ACCESS_KEY_ID -u R2_SECRET_ACCESS_KEY \
            "${credential_env[@]}" \
            RELEASE_CONFIG_PATH="$TEMP_ROOT/missing.env" \
            R2_BUCKET_NAME='switchtab' \
            UPDATE_DOMAIN='updates.test.example' \
            UPDATE_ARTIFACT_DIR="$ARTIFACT_DIR" \
            WRANGLER_BIN="$BIN_DIR/wrangler" \
            CURL_BIN="$BIN_DIR/curl" \
            SHASUM_BIN="$BIN_DIR/shasum" \
            XMLLINT_BIN="$BIN_DIR/xmllint" \
            WRANGLER_LOG="$WRANGLER_LOG" \
            CURL_LOG="$CURL_LOG" \
            MUTATION_LOG="$MUTATION_LOG" \
            PUBLIC_DIR="$PUBLIC_DIR" \
            ORIGIN_DIR="$ORIGIN_DIR" \
            "$FIXTURE_SCRIPT" 2>&1
    )"
    status=$?
    set -e
}

# New versioned artifacts are uploaded before the mutable appcast with exact metadata.
reset_fixture
invoke_script
assert_status 0
assert_output_contains 'https://updates.test.example/appcast.xml'
expected_mutation_log="conditional-put $DMG_NAME
conditional-put $DMG_NAME.sha256
conditional-put appcast.xml"
[[ "$(<"$MUTATION_LOG")" == "$expected_mutation_log" ]] || fail "appcast was not the final mutation: $(<"$MUTATION_LOG")"
[[ ! -s "$WRANGLER_LOG" ]] || fail "publication unexpectedly invoked Wrangler: $(<"$WRANGLER_LOG")"
expected_put_log="method=PUT url=https://$ACCOUNT_ID.r2.cloudflarestorage.com/switchtab/$DMG_NAME sigv4=aws:amz:auto:s3 conditional=none:* type=application/x-apple-diskimage cache=public, max-age=31536000, immutable config-stdin=1
method=PUT url=https://$ACCOUNT_ID.r2.cloudflarestorage.com/switchtab/$DMG_NAME.sha256 sigv4=aws:amz:auto:s3 conditional=none:* type=text/plain cache=public, max-age=31536000, immutable config-stdin=1
method=PUT url=https://$ACCOUNT_ID.r2.cloudflarestorage.com/switchtab/appcast.xml sigv4=aws:amz:auto:s3 conditional=none:* type=application/xml cache=public, max-age=60 config-stdin=1"
actual_put_log="$(grep '^method=PUT ' "$CURL_LOG")"
[[ "$actual_put_log" == "$expected_put_log" ]] || fail "unexpected conditional PUT endpoint/metadata: $actual_put_log"
[[ -f "$ORIGIN_DIR/$DMG_NAME" && -f "$ORIGIN_DIR/$DMG_NAME.sha256" ]] || fail "immutable objects did not reach the origin"
[[ "$(<"$CURL_LOG")" != *"$ACCESS_KEY_ID"* && "$(<"$CURL_LOG")" != *"$SECRET_ACCESS_KEY"* ]] || fail "R2 credentials appeared in the curl log"
[[ "$output" != *"$ACCESS_KEY_ID"* && "$output" != *"$SECRET_ACCESS_KEY"* ]] || fail "R2 credentials appeared in output"

# A newer release that finishes first cannot be rolled back by an older tag.
reset_fixture
write_appcast "$DMG_URL" 1 8
invoke_script
assert_status 0
newer_appcast="$TEMP_ROOT/newer-appcast.xml"
cp "$ORIGIN_DIR/appcast.xml" "$newer_appcast"
write_appcast "$DMG_URL" 1 7
: > "$MUTATION_LOG"
invoke_script
assert_failed
assert_output_contains 'newer appcast'
cmp -s "$newer_appcast" "$ORIGIN_DIR/appcast.xml" || fail "older tag rolled back the appcast"
assert_no_appcast_upload

# An appcast changed between the authoritative read and conditional write is retried safely.
reset_fixture
older_appcast="$TEMP_ROOT/older-appcast.xml"
newer_race_appcast="$TEMP_ROOT/newer-race-appcast.xml"
write_appcast "$DMG_URL" 1 6 "$older_appcast"
write_appcast "$DMG_URL" 1 8 "$newer_race_appcast"
cp "$older_appcast" "$ORIGIN_DIR/appcast.xml"
cp "$older_appcast" "$PUBLIC_DIR/appcast.xml"
FAKE_APPCAST_RACE_FILE="$newer_race_appcast"
invoke_script
assert_failed
assert_output_contains 'newer appcast'
cmp -s "$newer_race_appcast" "$ORIGIN_DIR/appcast.xml" || fail "conditional appcast race overwrote the newer feed"
[[ "$(grep -c 'conditional-put appcast.xml' "$MUTATION_LOG")" -eq 1 ]] || fail "appcast race was not attempted exactly once"

# An older remote appcast advances through If-Match, while same-version drift fails closed.
reset_fixture
write_appcast "$DMG_URL" 1 6 "$older_appcast"
cp "$older_appcast" "$ORIGIN_DIR/appcast.xml"
cp "$older_appcast" "$PUBLIC_DIR/appcast.xml"
invoke_script
assert_status 0
cmp -s "$ARTIFACT_DIR/appcast.xml" "$ORIGIN_DIR/appcast.xml" || fail "older appcast did not advance"
grep -Eq 'method=PUT .*appcast[.]xml .*conditional=match:"[a-f0-9]{64}"' "$CURL_LOG" || fail "appcast replacement did not use If-Match"

reset_fixture
same_version_drift="$TEMP_ROOT/same-version-drift.xml"
write_appcast 'https://updates.test.example/SwitchTab-other.dmg' 1 7 "$same_version_drift"
cp "$same_version_drift" "$ORIGIN_DIR/appcast.xml"
cp "$same_version_drift" "$PUBLIC_DIR/appcast.xml"
invoke_script
assert_failed
assert_output_contains 'same version'
cmp -s "$same_version_drift" "$ORIGIN_DIR/appcast.xml" || fail "same-version appcast drift was overwritten"
assert_no_appcast_upload

# A byte-identical appcast rerun is verification-only and performs no mutable write.
reset_fixture
cp "$ARTIFACT_DIR/appcast.xml" "$ORIGIN_DIR/appcast.xml"
cp "$ARTIFACT_DIR/appcast.xml" "$PUBLIC_DIR/appcast.xml"
invoke_script
assert_status 0
assert_no_appcast_upload

# Unsafe Sparkle build versions fail before any network mutation.
for unsafe_build_version in missing alpha too_many_parts; do
    reset_fixture
    case "$unsafe_build_version" in
        missing) write_appcast "$DMG_URL" 1 '' ;;
        alpha) write_appcast "$DMG_URL" 1 'release-7' ;;
        too_many_parts) write_appcast "$DMG_URL" 1 '1.2.3.4' ;;
    esac
    invoke_script
    assert_failed
    assert_output_contains 'sparkle:version'
    assert_no_uploads
    [[ ! -s "$CURL_LOG" ]] || fail "$unsafe_build_version build version reached the network"
done

# Identical immutable public objects are skipped, while appcast still publishes last.
reset_fixture
cp "$ARTIFACT_DIR/$DMG_NAME" "$PUBLIC_DIR/$DMG_NAME"
cp "$ARTIFACT_DIR/$DMG_NAME.sha256" "$PUBLIC_DIR/$DMG_NAME.sha256"
cp "$ARTIFACT_DIR/$DMG_NAME" "$ORIGIN_DIR/$DMG_NAME"
cp "$ARTIFACT_DIR/$DMG_NAME.sha256" "$ORIGIN_DIR/$DMG_NAME.sha256"
invoke_script
assert_status 0
[[ "$(grep -c '^method=PUT ' "$CURL_LOG")" -eq 3 ]] || fail "idempotent run did not use conditional writes"
[[ "$(tail -n 1 "$MUTATION_LOG")" == 'conditional-put appcast.xml' ]] || fail "appcast was not published last"

# An existing immutable DMG with different bytes is never overwritten.
reset_fixture
printf 'different remote dmg\n' > "$PUBLIC_DIR/$DMG_NAME"
invoke_script
assert_failed
assert_output_contains 'differs'
assert_no_uploads

# A stale public 404 cannot hide a different object already present at the origin.
reset_fixture
printf 'different authoritative dmg\n' > "$ORIGIN_DIR/$DMG_NAME"
origin_dmg_before="$(<"$ORIGIN_DIR/$DMG_NAME")"
FAKE_PUBLIC_STALE_ONCE_KEY="$DMG_NAME"
invoke_script
assert_failed
assert_output_contains 'origin'
[[ "$(<"$ORIGIN_DIR/$DMG_NAME")" == "$origin_dmg_before" ]] || fail "conditional race overwrote the origin DMG"
[[ "$(grep -c "method=PUT .*${DMG_NAME}.sha256" "$CURL_LOG" || true)" -eq 0 ]] || fail "checksum mutation ran after origin DMG mismatch"
assert_no_appcast_upload

# A stale public 404 with an identical origin object safely continues after 412.
reset_fixture
cp "$ARTIFACT_DIR/$DMG_NAME" "$ORIGIN_DIR/$DMG_NAME"
cp "$ARTIFACT_DIR/$DMG_NAME" "$PUBLIC_DIR/$DMG_NAME"
FAKE_PUBLIC_STALE_ONCE_KEY="$DMG_NAME"
invoke_script
assert_status 0
cmp -s "$ARTIFACT_DIR/$DMG_NAME" "$ORIGIN_DIR/$DMG_NAME" || fail "identical origin DMG was overwritten"
grep -Fq "method=GET url=https://$ACCOUNT_ID.r2.cloudflarestorage.com/switchtab/$DMG_NAME " "$CURL_LOG" || fail "412 did not trigger an authoritative origin GET"
grep -Fq 'conditional-put appcast.xml' "$MUTATION_LOG" || fail "identical race did not continue to appcast"

# A checksum created concurrently with different bytes blocks appcast publication.
reset_fixture
cp "$ARTIFACT_DIR/$DMG_NAME" "$ORIGIN_DIR/$DMG_NAME"
cp "$ARTIFACT_DIR/$DMG_NAME" "$PUBLIC_DIR/$DMG_NAME"
printf 'different authoritative checksum\n' > "$ORIGIN_DIR/$DMG_NAME.sha256"
origin_checksum_before="$(<"$ORIGIN_DIR/$DMG_NAME.sha256")"
FAKE_PUBLIC_STALE_ONCE_KEY="$DMG_NAME.sha256"
invoke_script
assert_failed
assert_output_contains 'checksum'
[[ "$(<"$ORIGIN_DIR/$DMG_NAME.sha256")" == "$origin_checksum_before" ]] || fail "conditional race overwrote the origin checksum"
assert_no_appcast_upload

# Conditional PUT transport and HTTP failures block all later release mutation.
reset_fixture
FAKE_PUT_TRANSPORT_STATUS=59
invoke_script
assert_status 59
[[ ! -e "$ORIGIN_DIR/$DMG_NAME" ]] || fail "transport failure created an origin object"
assert_no_appcast_upload

reset_fixture
FAKE_PUT_HTTP_STATUS=500
invoke_script
assert_failed
assert_output_contains '500'
[[ ! -e "$ORIGIN_DIR/$DMG_NAME" ]] || fail "failed conditional PUT created an origin object"
assert_no_appcast_upload

# An existing immutable checksum with different bytes is never overwritten.
reset_fixture
cp "$ARTIFACT_DIR/$DMG_NAME" "$PUBLIC_DIR/$DMG_NAME"
cp "$ARTIFACT_DIR/$DMG_NAME" "$ORIGIN_DIR/$DMG_NAME"
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

# Distinctive hash/XML failures are propagated.
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
grep -Fq 'conditional-put appcast.xml' "$MUTATION_LOG" || fail "appcast validation ran before upload"
[[ "$(tail -n 1 "$MUTATION_LOG")" == 'conditional-put appcast.xml' ]] || fail "appcast was not the last upload"

# Missing required inputs/tools and unexpected arguments fail before upload.
for missing_credential in account access secret; do
    reset_fixture
    invoke_with_missing_r2_credential "$missing_credential"
    assert_status 64
    assert_no_uploads
    [[ ! -s "$CURL_LOG" ]] || fail "missing $missing_credential credential reached curl"
done

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
        WRANGLER_BIN="$BIN_DIR/wrangler" CURL_BIN="$TEMP_ROOT/missing-curl" \
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
[[ "$output" != *"$ACCESS_KEY_ID"* && "$output" != *"$SECRET_ACCESS_KEY"* ]] || fail "xtrace exposed R2 credentials"
[[ "$(<"$MUTATION_LOG")" != *"$TRACE_SECRET"* ]] || fail "release credential reached mutation logs"

/bin/bash -n "$SCRIPT_SOURCE"
/bin/bash -n "$SCRIPT_DIR/publish-update-test.sh"

echo "publish-update contract tests passed"
