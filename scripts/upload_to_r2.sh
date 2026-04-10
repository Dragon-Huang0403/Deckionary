#!/usr/bin/env bash
set -euo pipefail

# Upload exported HTML and audio files to Cloudflare R2 via rclone.
#
# Prerequisites:
#   1. brew install rclone
#   2. rclone config
#      - Type: s3
#      - Provider: Cloudflare
#      - Access key + secret: Cloudflare dashboard > R2 > Manage R2 API Tokens
#      - Endpoint: https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com
#        (use .eu. for WEUR buckets, plain for default)
#   3. python scripts/export_for_r2.py

REMOTE="${R2_REMOTE:-cloudflare r2}"
BUCKET="oald10"
TRANSFERS="${R2_TRANSFERS:-16}"

if [[ ! -d export/html ]]; then
    echo "Error: export/html/ not found. Run: python scripts/export_for_r2.py" >&2
    exit 1
fi

if [[ ! -f export/audio_filelist.txt ]]; then
    echo "Error: export/audio_filelist.txt not found. Run: python scripts/export_for_r2.py" >&2
    exit 1
fi

echo "=== Uploading HTML files ==="
rclone copy export/html/ "${REMOTE}:${BUCKET}/html/" \
    --progress --transfers "$TRANSFERS" --retries 5 --low-level-retries 10 \
    --s3-no-check-bucket

echo "=== Uploading audio files ==="
rclone copy oxford.dictionary/Contents/ "${REMOTE}:${BUCKET}/audio/" \
    --files-from export/audio_filelist.txt \
    --progress --transfers "$TRANSFERS" --retries 5 --low-level-retries 10 \
    --s3-no-check-bucket

echo ""
echo "=== Verifying ==="
rclone size "${REMOTE}:${BUCKET}/"

echo ""
echo "Done. Enable public access: Cloudflare dashboard > R2 > oald10 > Settings"
