#!/usr/bin/env bash
set -Eeuo pipefail

# Persistent shared queue inside the container.
QUEUE="/config/download-organizer/download-queue.json"
LOCK="${QUEUE}.lock"

CATEGORY="${1:-}"
SOURCE="${2:-}"
TORRENT_HASH="${3:-}"

case "$CATEGORY" in
    movies|series) ;;
    *)
        echo "Ignoring unsupported category: $CATEGORY"
        exit 0
        ;;
esac

if [[ -z "$SOURCE" || -z "$TORRENT_HASH" ]]; then
    echo "Usage: $0 CATEGORY SOURCE TORRENT_HASH" >&2
    exit 1
fi

if [[ ! -e "$SOURCE" ]]; then
    echo "Error: source does not exist: $SOURCE" >&2
    exit 1
fi

SOURCE="$(realpath "$SOURCE")"

if [[ ! -f "$SOURCE" && ! -d "$SOURCE" ]]; then
    echo "Error: source is not a regular file or directory: $SOURCE" >&2
    exit 1
fi

for cmd in jq flock realpath; do
    command -v "$cmd" >/dev/null || {
        echo "Error: required command not found: $cmd" >&2
        exit 1
    }
done

mkdir -p -- "$(dirname -- "$QUEUE")"
touch "$LOCK"

# Serialize access to the queue.
exec 9>"$LOCK"
flock -x 9

if [[ ! -s "$QUEUE" ]]; then
    printf '[]\n' > "$QUEUE"
fi

jq -e 'type == "array"' "$QUEUE" >/dev/null || {
    echo "Error: invalid JSON queue: $QUEUE" >&2
    exit 1
}

# Avoid duplicate entries for the same pending torrent.
if jq -e \
    --arg hash "$TORRENT_HASH" \
    'any(.[]; .hash == $hash and
              (.status == "pending" or
               .status == "moved_pending_delete"))' \
    "$QUEUE" >/dev/null; then
    echo "Already queued: $TORRENT_HASH"
    exit 0
fi

TMP="$(mktemp "$(dirname -- "$QUEUE")/.queue.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT

jq \
    --arg hash "$TORRENT_HASH" \
    --arg category "$CATEGORY" \
    --arg source "$SOURCE" \
    --arg added "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '. + [{
        hash: $hash,
        category: $category,
        source: $source,
        destination: null,
        status: "pending",
        added_at: $added,
        error: null
    }]' "$QUEUE" > "$TMP"

chmod --reference="$QUEUE" "$TMP" 2>/dev/null || true
mv -f -- "$TMP" "$QUEUE"
trap - EXIT

echo "Queued [$CATEGORY]: $SOURCE (hash: $TORRENT_HASH)"
