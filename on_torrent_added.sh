#!/usr/bin/env bash
set -Eeuo pipefail

exec > /config/script-debug.log 2>&1

echo "========== SCRIPT STARTED $(date) =========="

RESULTS_JSON="/rss-parser/results.json"

# ------------------------------------------------------------
# Validate arguments.
# qBittorrent passes: "%L" "%F" "%I" "%N"
# ------------------------------------------------------------

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 CATEGORY CONTENT_PATH INFO_HASH TORRENT_NAME" >&2
    exit 1
fi

CATEGORY="$1"
CONTENT_PATH="$2"
INFO_HASH="$3"
TORRENT_NAME="$4"

for cmd in jq curl; do
    command -v "$cmd" >/dev/null || {
        echo "Error: required command not found: $cmd" >&2
        exit 1
    }
done

QBITTORRENT_URL="http://localhost:6520"
QBITTORRENT_API_KEY="qbt_xIu6N5dq78nYYPYx9"

: "${QBITTORRENT_URL:?Missing QBITTORRENT_URL}"
: "${QBITTORRENT_API_KEY:?Missing QBITTORRENT_API_KEY}"

QBITTORRENT_URL="${QBITTORRENT_URL%/}"

echo "[IMAGE] Category: $CATEGORY"
echo "[IMAGE] Content path: $CONTENT_PATH"
echo "[IMAGE] Info hash: $INFO_HASH"
echo "[IMAGE] Torrent name: $TORRENT_NAME"

# ------------------------------------------------------------
# Extract the title and year from the torrent name.
# Example:
# "Example Movie (2025) English HDRip - 720p"
# becomes:
# "Example Movie (2025)"
# ------------------------------------------------------------


extract_search_title() {
    local name="$1"

    # Remove the website prefix if the name starts with "ww"
    if [[ "$name" == ww*' - '* ]]; then
        name="${name#* - }"
    fi

    # Extract the title and year.
    if [[ "$name" =~ ^(.*\((19|20)[0-9]{2}\)) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' "$name"
    fi
}

SEARCH_TITLE="$(extract_search_title "$TORRENT_NAME")"

echo "[IMAGE] Search title: $SEARCH_TITLE"

# ------------------------------------------------------------
# Find the first matching title in output.json.
# Matching is case-insensitive and ignores punctuation.
# The JSON title must begin with the extracted title.
# ------------------------------------------------------------

if [[ ! -f "$RESULTS_JSON" ]]; then
    echo "Error: results file not found: $RESULTS_JSON" >&2
    exit 1
fi

MATCH="$(
    jq -ce --arg title "$SEARCH_TITLE" '
        def normalize:
            ascii_downcase
            | gsub("[^a-z0-9]+"; " ")
            | gsub("^ +| +$"; "");

        ($title | normalize) as $needle
        | first(
            .[]
            | select(
                ((.title // "") | normalize) as $candidate
                | $candidate == $needle
                  or ($candidate | startswith($needle + " "))
            )
        ) // empty
    ' "$RESULTS_JSON"
)" || {
    echo "[IMAGE] No matching entry found for: $SEARCH_TITLE"
    exit 0
}

MATCHED_TITLE="$(jq -r '.title // ""' <<<"$MATCH")"
IMAGE_URL="$(jq -er '.first_image | select(type == "string" and length > 0)' <<<"$MATCH")" || {
    echo "[IMAGE] Matching entry has no valid first_image" >&2
    exit 0
}

echo "[IMAGE] Matched title: $MATCHED_TITLE"
echo "[IMAGE] Image URL: $IMAGE_URL"

# ------------------------------------------------------------
# Build the JSON comment payload.
# ------------------------------------------------------------

COMMENT_JSON="$(
    jq -cn --arg image_url "$IMAGE_URL" \
        '{image_url: $image_url}'
)"

echo "[IMAGE] Updating torrent comment..."

# ------------------------------------------------------------
# Update the torrent comment using the qBittorrent API.
# Requires a qBittorrent version supporting torrents/setComment.
# ------------------------------------------------------------

HTTP_CODE="$(
    curl --silent --show-error \
        --connect-timeout 10 \
        --max-time 30 \
        --output /dev/null \
        --write-out '%{http_code}' \
        --header "Authorization: Bearer $QBITTORRENT_API_KEY" \
        --referer "$QBITTORRENT_URL" \
        --request POST \
        --data-urlencode "hashes=$INFO_HASH" \
        --data-urlencode "comment=$COMMENT_JSON" \
        "$QBITTORRENT_URL/api/v2/torrents/setComment"
)" || {
    echo "Error: failed to contact qBittorrent API" >&2
    exit 1
}

if [[ "$HTTP_CODE" != "204" ]]; then
    echo "Error: qBittorrent API returned HTTP $HTTP_CODE" >&2
    exit 1
fi

echo "[IMAGE] Torrent comment updated successfully."
