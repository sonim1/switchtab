#!/usr/bin/env bash
set -euo pipefail
set +x

usage() {
    echo 'Usage: scripts/dispatch-homebrew-update.sh v<version>' >&2
}

if [[ $# -ne 1 ]]; then
    usage
    exit 64
fi

TAG="$1"
if [[ ! "$TAG" =~ ^v[0-9]+([.][0-9]+)*$ ]]; then
    echo 'Release tag must match v<version>' >&2
    usage
    exit 64
fi

if [[ -z "${TAP_GH_TOKEN:-}" ]]; then
    echo 'TAP_GH_TOKEN is required' >&2
    exit 64
fi

GH_BIN="${GH_BIN:-gh}"

GH_TOKEN="$TAP_GH_TOKEN" \
TAP_GH_TOKEN='' \
GH_HOST='github.com' \
GH_REPO='sonim1/homebrew-tap' \
"$GH_BIN" api \
    --hostname github.com \
    --method POST \
    repos/sonim1/homebrew-tap/dispatches \
    -f event_type=homebrew_release \
    -f 'client_payload[repository]=sonim1/switchtab' \
    -f "client_payload[tag]=$TAG"
