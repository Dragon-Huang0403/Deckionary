#!/usr/bin/env python3
"""
Extract audio BLOBs from oald10.db to individual MP3 files.

Produces a flat directory of ~217K MP3 files ready for CDN upload,
plus a manifest JSON for integrity checking.

Usage:
    python tools/extract_audio.py                         # default: audio_out/
    python tools/extract_audio.py -o /path/to/audio       # custom output dir
    python tools/extract_audio.py --manifest-only         # just generate manifest
"""

import argparse
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

SOURCE_DB = Path("oald10.db")
BATCH_SIZE = 1000


def extract_audio(source: Path, output_dir: Path, manifest_only: bool = False) -> None:
    if not source.exists():
        print(f"Source database not found: {source}", file=sys.stderr)
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(str(source))
    total = db.execute("SELECT COUNT(*) FROM audio_files").fetchone()[0]
    print(f"Extracting {total} audio files to {output_dir}/", file=sys.stderr)

    manifest = {}
    extracted = 0

    cursor = db.execute("SELECT filename, data FROM audio_files ORDER BY filename")
    while True:
        rows = cursor.fetchmany(BATCH_SIZE)
        if not rows:
            break

        for filename, data in rows:
            md5 = hashlib.md5(data).hexdigest()
            manifest[filename] = {"size": len(data), "md5": md5}

            if not manifest_only:
                filepath = output_dir / filename
                if not filepath.exists() or filepath.stat().st_size != len(data):
                    filepath.write_bytes(data)

            extracted += 1

        print(f"  {extracted}/{total} processed...", file=sys.stderr)

    db.close()

    # Write manifest
    manifest_path = output_dir / "audio_manifest.json"
    manifest_path.write_text(json.dumps(manifest, sort_keys=True, indent=None))

    total_size_mb = sum(v["size"] for v in manifest.values()) / (1024 * 1024)
    print(f"\nDone: {extracted} files ({total_size_mb:.1f} MB)", file=sys.stderr)
    print(f"Manifest: {manifest_path}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Extract audio files from oald10.db")
    parser.add_argument("-o", "--output", default="audio_out", help="Output directory")
    parser.add_argument("-s", "--source", default=str(SOURCE_DB), help="Source oald10.db path")
    parser.add_argument("--manifest-only", action="store_true", help="Only generate manifest, skip file extraction")
    args = parser.parse_args()

    extract_audio(Path(args.source), Path(args.output), manifest_only=args.manifest_only)


if __name__ == "__main__":
    main()
