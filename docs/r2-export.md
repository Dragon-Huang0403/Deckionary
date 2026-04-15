# Static Asset Export (Cloudflare R2)

Raw HTML and audio files from the dictionary are static and never change. Instead of storing them as BLOBs in the database, they can be exported and hosted on Cloudflare R2 for public access with free egress.

## How it works

1. **Export** reads `oxford.dictionary/Contents/Body.data` directly (not the DB)
2. Each entry's HTML is decompressed from the binary and split into per-POS blocks
3. Saved as individual files: `{headword}__{pos}__{index}.html` (76K files, ~458MB)
4. Audio filenames referenced by entries are collected into a filelist (217K mp3s)
5. Both are uploaded to R2 via rclone (S3-compatible)

## R2 bucket structure

```
oald10/
  html/         # 76,210 HTML files (raw, uncompressed)
  audio/        # 217,191 MP3 files (for on-demand playback)
  audio-packs/  # ~257 tar archives + manifest.json (for bulk download)
  db/           # oald10.db (SQLite dictionary database)
```

### Audio packs

The export script bundles audio files into tar archives of 1,000 files each for fast bulk download. The Flutter app downloads these packs (~12 MB each, ~257 total) instead of 257K individual files, reducing download time from hours to minutes.

`manifest.json` lists each pack's name, file count, and byte size. The app tracks completed packs and resumes from where it left off.

## Usage

```bash
# 1. Export HTML files + audio filelist
python scripts/export_for_r2.py

# 2. Upload to R2 via rclone
./scripts/upload_to_r2.sh
```

## rclone setup

```bash
brew install rclone
rclone config
# Type: s3
# Provider: Cloudflare
# Access key + secret: Cloudflare dashboard > R2 > Manage R2 API Tokens
# Endpoint: https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com
#   (use .eu. for WEUR-located buckets, omit for default location)
```

The upload script uses the rclone remote name `cloudflare r2` by default. Override with `R2_REMOTE` env var. Parallelism defaults to 16 transfers, override with `R2_TRANSFERS`.

## Verify upload

The upload script is idempotent — rerunning skips already-uploaded files. After it finishes, compare remote vs local counts:

```bash
# Remote
rclone size "cloudflare r2:oald10/html/"
rclone size "cloudflare r2:oald10/audio/"

# Local (expected: 76,210 html, 217,191 audio)
ls export/html/ | wc -l
wc -l export/audio_filelist.txt
```

If counts don't match, just rerun `./scripts/upload_to_r2.sh` — it only uploads missing files.

## Public access

Enable public access on the bucket via Cloudflare dashboard (R2 > oald10 > Settings). URLs become:

```
https://pub-<hash>.r2.dev/html/abandon__verb__0.html
https://pub-<hash>.r2.dev/audio/abandon__gb_1.mp3
```

No manifest or file-ID lookup needed — the app already knows the headword, POS, and audio filename, so it constructs the URL directly.
