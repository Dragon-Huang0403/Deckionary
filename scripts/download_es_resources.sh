#!/usr/bin/env bash
# Download the offline data sources used to build vox_es.db.
#
# - EN Wiktionary XML dump (CC-BY-SA, ~1.6 GB)        → IPA per Spanish headword
# - hermitdave/FrequencyWords ES list (MIT, ~600 KB) → frequency tier
#
# Both files are placed under data_es/ and reused across rebuilds. Idempotent —
# skips a file if already present and non-empty.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${REPO_ROOT}/data_es"
mkdir -p "${DATA_DIR}"

WIKT_URL="https://dumps.wikimedia.org/enwiktionary/latest/enwiktionary-latest-pages-articles.xml.bz2"
WIKT_FILE="${DATA_DIR}/enwiktionary-latest-pages-articles.xml.bz2"

FREQ_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/es/es_50k.txt"
FREQ_FILE="${DATA_DIR}/es_frequency_50k.txt"

download() {
    local url="$1" path="$2" min_size="$3"
    if [[ -s "$path" ]]; then
        local sz
        sz=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
        if (( sz >= min_size )); then
            echo "✓ $(basename "$path") already present (${sz} bytes), skipping"
            return 0
        fi
        echo "✗ $(basename "$path") looks truncated (${sz} bytes < ${min_size}); re-downloading"
    fi
    echo "↓ $url"
    # -C -        resume from existing partial file
    # --retry N   retry on transient errors (bandwidth flakiness on the
    #             1.6 GB Wiktionary dump triggers this regularly)
    # --retry-all-errors  also retry on non-transient errors like 416
    curl -L --fail --progress-bar -C - --retry 10 --retry-all-errors \
         --retry-delay 5 -o "$path" "$url"
}

download "$FREQ_URL" "$FREQ_FILE" 100000
download "$WIKT_URL" "$WIKT_FILE" 1000000000  # >1 GB sanity check

echo
echo "Done. Files in ${DATA_DIR}:"
ls -lh "${DATA_DIR}"
