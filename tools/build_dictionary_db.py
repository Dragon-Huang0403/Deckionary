#!/usr/bin/env python3
"""
Build a text-only dictionary.db from the full oald10.db.

Strips the audio_files table (1.75GB of MP3 BLOBs) to produce a ~200MB
read-only dictionary database suitable for bundling with mobile/desktop apps.

Usage:
    python tools/build_dictionary_db.py                    # default: dictionary.db
    python tools/build_dictionary_db.py -o my_dict.db      # custom output
    python tools/build_dictionary_db.py --gzip             # also produce .gz
"""

import argparse
import gzip
import shutil
import sqlite3
import sys
from pathlib import Path

SOURCE_DB = Path("oald10.db")

# Tables to copy (everything except audio_files)
TABLES = [
    "sources",
    "entries",
    "pronunciations",
    "verb_forms",
    "sense_groups",
    "senses",
    "examples",
    "extra_examples",
    "synonyms",
    "word_origins",
    "word_family",
    "collocations",
    "xrefs",
    "phrasal_verbs",
    "variants",
    "meta",
]


def build_dictionary_db(source: Path, output: Path, do_gzip: bool = False) -> None:
    if not source.exists():
        print(f"Source database not found: {source}", file=sys.stderr)
        sys.exit(1)

    if output.exists():
        output.unlink()

    print(f"Creating {output} from {source}...", file=sys.stderr)

    db = sqlite3.connect(str(output))
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=OFF")  # Faster bulk insert

    # Attach source database
    db.execute(f"ATTACH DATABASE '{source}' AS src")

    # Get schema DDL from source (excluding audio_files and FTS/triggers)
    schema_rows = db.execute(
        """SELECT type, name, sql FROM src.sqlite_master
           WHERE sql IS NOT NULL
             AND name NOT LIKE 'audio_%'
             AND name NOT LIKE 'entries_fts%'
             AND name NOT LIKE 'sqlite_%'
             AND type IN ('table', 'index')
           ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END"""
    ).fetchall()

    # Create tables and indexes
    for row_type, name, sql in schema_rows:
        try:
            db.execute(sql)
        except sqlite3.OperationalError as e:
            print(f"  Warning: {name}: {e}", file=sys.stderr)

    db.commit()

    # Copy data table by table
    for table in TABLES:
        try:
            count = db.execute(f"SELECT COUNT(*) FROM src.{table}").fetchone()[0]
            db.execute(f"INSERT INTO main.{table} SELECT * FROM src.{table}")
            db.commit()
            print(f"  {table}: {count} rows", file=sys.stderr)
        except sqlite3.OperationalError as e:
            print(f"  {table}: SKIPPED ({e})", file=sys.stderr)

    # Rebuild FTS5 index
    print("  Building FTS5 index...", file=sys.stderr)
    db.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
            headword, content='entries', content_rowid='id'
        )
    """)
    db.execute("INSERT INTO entries_fts(rowid, headword) SELECT id, headword FROM entries")

    # FTS triggers for consistency
    db.executescript("""
        CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts(rowid, headword) VALUES (new.id, new.headword);
        END;
        CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, headword) VALUES ('delete', old.id, old.headword);
        END;
        CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, headword) VALUES ('delete', old.id, old.headword);
            INSERT INTO entries_fts(rowid, headword) VALUES (new.id, new.headword);
        END;
    """)
    db.commit()

    # Detach and optimize
    db.execute("DETACH DATABASE src")
    db.execute("PRAGMA foreign_keys=ON")
    print("  Optimizing...", file=sys.stderr)
    db.execute("PRAGMA optimize")
    db.execute("VACUUM")
    db.commit()
    db.close()

    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"\nDone: {output} ({size_mb:.1f} MB)", file=sys.stderr)

    # Verify
    db = sqlite3.connect(str(output))
    entry_count = db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    sense_count = db.execute("SELECT COUNT(*) FROM senses").fetchone()[0]
    print(f"  Entries: {entry_count}, Senses: {sense_count}", file=sys.stderr)
    db.close()

    # Optional gzip
    if do_gzip:
        gz_path = Path(str(output) + ".gz")
        print(f"Compressing to {gz_path}...", file=sys.stderr)
        with open(output, "rb") as f_in, gzip.open(gz_path, "wb", compresslevel=9) as f_out:
            shutil.copyfileobj(f_in, f_out)
        gz_size = gz_path.stat().st_size / (1024 * 1024)
        print(f"  {gz_path} ({gz_size:.1f} MB)", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Build text-only dictionary.db")
    parser.add_argument("-o", "--output", default="dictionary.db", help="Output path")
    parser.add_argument("-s", "--source", default=str(SOURCE_DB), help="Source oald10.db path")
    parser.add_argument("--gzip", action="store_true", help="Also produce .gz compressed version")
    args = parser.parse_args()

    build_dictionary_db(Path(args.source), Path(args.output), do_gzip=args.gzip)


if __name__ == "__main__":
    main()
