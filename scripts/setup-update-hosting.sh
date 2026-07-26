#!/usr/bin/env bash
set -euo pipefail
set +x

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ $# -ne 0 ]]; then
    echo "Usage: scripts/setup-update-hosting.sh" >&2
    exit 64
fi

CONFIG_PATH="${RELEASE_CONFIG_PATH:-$PROJECT_ROOT/.env.release.local}"
if [[ -f "$CONFIG_PATH" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_PATH"
    set +a
fi

export R2_BUCKET_NAME="${R2_BUCKET_NAME:-switchtab}"
export UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.switchtab.royjen.com}"
export WRANGLER_BIN="${WRANGLER_BIN:-$PROJECT_ROOT/node_modules/.bin/wrangler}"

if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
    echo "CLOUDFLARE_ZONE_ID is required." >&2
    exit 64
fi

if [[ "$WRANGLER_BIN" == */* ]]; then
    if [[ ! -x "$WRANGLER_BIN" ]]; then
        echo "Wrangler executable not found at $WRANGLER_BIN." >&2
        echo "Run npm ci to install the pinned Wrangler executable." >&2
        exit 66
    fi
else
    WRANGLER_BIN="$(command -v "$WRANGLER_BIN" 2>/dev/null || true)"
    if [[ -z "$WRANGLER_BIN" ]]; then
        echo "Wrangler executable is not available." >&2
        echo "Run npm ci to install the pinned Wrangler executable." >&2
        exit 66
    fi
fi

run_wrangler_quiet() {
    local output status

    if output="$("$WRANGLER_BIN" "$@" 2>&1)"; then
        return 0
    else
        status=$?
        printf '%s\n' "$output" >&2
        return "$status"
    fi
}

run_wrangler_quiet whoami

normalize_diagnostic_line() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

is_bucket_absent_error() {
    local diagnostic_line line bucket_name bucket_endpoint bucket_error_re

    bucket_name="$(printf '%s' "$R2_BUCKET_NAME" | tr '[:upper:]' '[:lower:]')"
    bucket_endpoint="/r2/buckets/$bucket_name"
    bucket_error_re='^the specified bucket does not exist[.][[:space:]]+[[]code:[[:space:]][0-9]+[]]$'

    while IFS= read -r diagnostic_line || [[ -n "$diagnostic_line" ]]; do
        line="$(normalize_diagnostic_line "$diagnostic_line")"

        case "$line" in
            "bucket not found"|"bucket does not exist"|"no such bucket")
                return 0
                ;;
            "404 $bucket_endpoint"|"$bucket_endpoint 404")
                return 0
                ;;
        esac

        if [[ "$line" =~ $bucket_error_re ]]; then
            return 0
        fi
    done <<< "$1"

    return 1
}

is_domain_absent_error() {
    local diagnostic_line line bucket_name domain_name domain_endpoint domain_error_re domain_not_found_re

    bucket_name="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    domain_name="$(printf '%s' "$UPDATE_DOMAIN" | tr '[:upper:]' '[:lower:]')"
    domain_endpoint="/r2/buckets/$bucket_name/domains/custom/$domain_name"
    domain_error_re='^the specified custom domain does not exist[.][[:space:]]+[[]code:[[:space:]][0-9]+[]]$'
    domain_not_found_re='^domain not found[.][[:space:]]+[[]code:[[:space:]][0-9]+[]]$'

    while IFS= read -r diagnostic_line || [[ -n "$diagnostic_line" ]]; do
        line="$(normalize_diagnostic_line "$diagnostic_line")"

        case "$line" in
            "domain not found"|"domain does not exist"|"no such domain")
                return 0
                ;;
            "404 $domain_endpoint"|"$domain_endpoint 404")
                return 0
                ;;
        esac

        if [[ "$line" =~ $domain_error_re || "$line" =~ $domain_not_found_re ]]; then
            return 0
        fi
    done <<< "$1"

    return 1
}

extract_domain_label() {
    local output="$1"
    local label="$2"

    printf '%s\n' "$output" | awk -v label="$label" '
        index($0, label ":") == 1 {
            value = substr($0, length(label) + 2)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    '
}

verify_domain_state() {
    local output="$1"
    local domain enabled min_tls

    domain="$(extract_domain_label "$output" domain)"
    enabled="$(extract_domain_label "$output" enabled)"
    min_tls="$(extract_domain_label "$output" min_tls_version)"

    if [[ "$domain" != "$UPDATE_DOMAIN" \
        || "$enabled" != "Yes" \
        || ( "$min_tls" != "1.2" && "$min_tls" != "1.3" ) ]]; then
        printf 'R2 domain verification failed: domain=%s enabled=%s min_tls_version=%s\n' \
            "$domain" "$enabled" "$min_tls" >&2
        return 1
    fi
}

bucket_info_output=''
if bucket_info_output="$("$WRANGLER_BIN" r2 bucket info "$R2_BUCKET_NAME" --json 2>&1)"; then
    :
else
    bucket_info_status=$?
    if ! is_bucket_absent_error "$bucket_info_output"; then
        printf '%s\n' "$bucket_info_output" >&2
        exit "$bucket_info_status"
    fi

    run_wrangler_quiet r2 bucket create "$R2_BUCKET_NAME"
    run_wrangler_quiet r2 bucket info "$R2_BUCKET_NAME" --json
fi

domain_get_output=''
if domain_get_output="$("$WRANGLER_BIN" r2 bucket domain get "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN" 2>&1)"; then
    verify_domain_state "$domain_get_output"
else
    domain_get_status=$?
    if ! is_domain_absent_error "$domain_get_output" "$R2_BUCKET_NAME"; then
        printf '%s\n' "$domain_get_output" >&2
        exit "$domain_get_status"
    fi

    run_wrangler_quiet r2 bucket domain add "$R2_BUCKET_NAME" \
        --domain "$UPDATE_DOMAIN" \
        --zone-id "$CLOUDFLARE_ZONE_ID" \
        --min-tls 1.2 \
        --force
    if domain_get_output="$("$WRANGLER_BIN" r2 bucket domain get "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN" 2>&1)"; then
        verify_domain_state "$domain_get_output"
    else
        domain_get_status=$?
        printf '%s\n' "$domain_get_output" >&2
        exit "$domain_get_status"
    fi
fi

printf 'https://%s/appcast.xml\n' "$UPDATE_DOMAIN"
