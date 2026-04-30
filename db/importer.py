"""Import pipeline: read Body.data -> parse -> insert into SQLite."""

import re
import sqlite3
import struct
import sys
import zlib
from pathlib import Path

import opencc

from .models import EntryData
from .parser import parse_entry
from .schema import create_schema

_converter = opencc.OpenCC('s2t')
_t2s_converter = opencc.OpenCC('t2s')


def s2t(text: str) -> str:
    """Convert Simplified Chinese to Traditional Chinese."""
    return _converter.convert(text) if text else ""


def t2s(text: str) -> str:
    """Convert Traditional Chinese to Simplified Chinese."""
    return _t2s_converter.convert(text) if text else ""

CONTENTS = Path("oxford.dictionary/Contents").resolve()
BODY = CONTENTS / "Body.data"


def _read_entry_at(data: bytes, pos: int) -> str:
    sz2 = struct.unpack_from("<I", data, pos + 4)[0]
    zlib_start = pos + 12
    compressed_size = sz2 - 4
    return zlib.decompress(data[zlib_start:zlib_start + compressed_size]).decode("utf-8", errors="replace")


def _build_index(data: bytes) -> dict[str, int]:
    """Build word -> byte offset index from Body.data."""
    index: dict[str, int] = {}
    pos = 0x60
    while pos < len(data) - 12:
        sz1 = struct.unpack_from("<I", data, pos)[0]
        sz2 = struct.unpack_from("<I", data, pos + 4)[0]
        if sz1 == 0 or sz1 > 500_000:
            break
        zlib_start = pos + 12
        compressed_size = sz2 - 4
        try:
            partial = zlib.decompress(data[zlib_start:zlib_start + compressed_size], 15, 512)
            m = re.search(rb'd:title="([^"]+)"', partial)
            if m:
                title = m.group(1).decode("utf-8", errors="replace")
                index[title.lower()] = pos
        except Exception:
            pass
        pos = zlib_start + compressed_size
    return index


def _build_variants(data: bytes, index: dict[str, int]) -> dict[str, str]:
    """Build variant spelling -> headword map."""
    variants: dict[str, str] = {}
    for headword, pos in index.items():
        try:
            html = _read_entry_at(data, pos)
        except Exception:
            continue
        for m in re.finditer(r'<span class="v"[^>]*>([^<]+)</span>', html):
            variant = m.group(1).strip().lower()
            if variant and variant not in index:
                variants[variant] = headword
    return variants


def _insert_entry(
    db: sqlite3.Connection, source_id: int, entry: EntryData,
    entry_index: int, parent_entry_id: int | None = None,
) -> int:
    """Insert one entry and all its children. Returns entry_id."""
    cur = db.execute(
        """INSERT INTO entries
           (source_id, headword, pos, entry_index, ipa_gb, ipa_us,
            cefr_level, ox3000, ox5000, parent_entry_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (source_id, entry.headword, entry.pos, entry_index,
         entry.ipa_gb, entry.ipa_us, entry.cefr_level,
         int(entry.ox3000), int(entry.ox5000), parent_entry_id),
    )
    entry_id = cur.lastrowid

    # Pronunciations
    if entry.audio_gb or entry.ipa_gb:
        db.execute(
            "INSERT INTO pronunciations (entry_id, dialect, ipa, audio_file) VALUES (?, 'gb', ?, ?)",
            (entry_id, entry.ipa_gb, entry.audio_gb),
        )
    if entry.audio_us or entry.ipa_us:
        db.execute(
            "INSERT INTO pronunciations (entry_id, dialect, ipa, audio_file) VALUES (?, 'us', ?, ?)",
            (entry_id, entry.ipa_us, entry.audio_us),
        )

    # Verb forms
    for i, vf in enumerate(entry.verb_forms):
        db.execute(
            """INSERT INTO verb_forms
               (entry_id, form_label, form_text, audio_gb, audio_us, sort_order)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (entry_id, vf.form_label, vf.form_text, vf.audio_gb, vf.audio_us, i),
        )

    # Sense groups -> senses -> examples
    for gi, group in enumerate(entry.groups):
        gcur = db.execute(
            "INSERT INTO sense_groups (entry_id, topic_en, topic_zh, sort_order) VALUES (?, ?, ?, ?)",
            (entry_id, group.topic_en, s2t(group.topic_zh), gi),
        )
        group_id = gcur.lastrowid

        for si, sense in enumerate(group.senses):
            scur = db.execute(
                """INSERT INTO senses
                   (sense_group_id, entry_id, sense_num, cefr_level, grammar,
                    labels, variants, definition, definition_zh, sort_order)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (group_id, entry_id, sense.sense_num, sense.cefr_level,
                 sense.grammar, sense.labels, sense.variants,
                 sense.definition, s2t(sense.definition_zh), si),
            )
            sense_id = scur.lastrowid

            for ei, ex in enumerate(sense.examples):
                db.execute(
                    """INSERT INTO examples
                       (sense_id, text_plain, text_html, text_zh,
                        audio_gb, audio_us, sort_order)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (sense_id, ex.text_plain, ex.text_html, s2t(ex.text_zh),
                     ex.audio_gb, ex.audio_us, ei),
                )

            # Sense-level cross-references
            for xi, xref in enumerate(sense.xrefs):
                db.execute(
                    """INSERT INTO xrefs
                       (entry_id, sense_group_id, sense_id, xref_type, target_word, sort_order)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (entry_id, group_id, sense_id, xref.xref_type, xref.target_word, xi),
                )

        # Group-level cross-references
        for xi, xref in enumerate(group.xrefs):
            db.execute(
                """INSERT INTO xrefs
                   (entry_id, sense_group_id, xref_type, target_word, sort_order)
                   VALUES (?, ?, ?, ?, ?)""",
                (entry_id, group_id, xref.xref_type, xref.target_word, xi),
            )

    # Synonyms
    for i, syn in enumerate(entry.synonyms):
        db.execute(
            "INSERT INTO synonyms (entry_id, group_title, word, definition, sort_order) VALUES (?, ?, ?, ?, ?)",
            (entry_id, syn.group_title, syn.word, s2t(syn.definition), i),
        )

    # Word origin
    if entry.word_origin:
        db.execute(
            "INSERT INTO word_origins (entry_id, text_html, text_plain) VALUES (?, ?, ?)",
            (entry_id, entry.word_origin_html, entry.word_origin),
        )

    # Word family
    for i, wf in enumerate(entry.word_family):
        db.execute(
            "INSERT INTO word_family (entry_id, word, pos, opposite, sort_order) VALUES (?, ?, ?, ?, ?)",
            (entry_id, wf.word, wf.pos, wf.opposite, i),
        )

    # Collocations
    for i, coll in enumerate(entry.collocations):
        db.execute(
            "INSERT INTO collocations (entry_id, category, words, sort_order) VALUES (?, ?, ?, ?)",
            (entry_id, coll.category, ", ".join(coll.words), i),
        )

    # Cross-references
    for i, xref in enumerate(entry.xrefs):
        db.execute(
            "INSERT INTO xrefs (entry_id, xref_type, target_word, sort_order) VALUES (?, ?, ?, ?)",
            (entry_id, xref.xref_type, xref.target_word, i),
        )

    # Phrasal verbs
    for i, pv in enumerate(entry.phrasal_verbs):
        db.execute(
            "INSERT INTO phrasal_verbs (entry_id, phrase, sort_order) VALUES (?, ?, ?)",
            (entry_id, pv, i),
        )

    # Extra examples
    for i, ex in enumerate(entry.extra_examples):
        db.execute(
            """INSERT INTO extra_examples
               (entry_id, text_plain, text_html, text_zh, sort_order)
               VALUES (?, ?, ?, ?, ?)""",
            (entry_id, ex.text_plain, ex.text_html, s2t(ex.text_zh), i),
        )

    return entry_id


def import_all(db_path: str | Path, verbose: bool = False) -> None:
    """Build the full dictionary database from Body.data."""
    db_path = Path(db_path)
    if db_path.exists():
        db_path.unlink()

    db = sqlite3.connect(str(db_path))
    create_schema(db)

    # Insert source
    cur = db.execute(
        "INSERT INTO sources (name, version) VALUES (?, ?)",
        ("OALD10", "10th Edition"),
    )
    source_id = cur.lastrowid

    # Load binary data
    print("Loading Body.data...", file=sys.stderr)
    body_data = BODY.read_bytes()

    # Build index
    print("Building word index...", file=sys.stderr)
    index = _build_index(body_data)
    print(f"  {len(index)} headwords found", file=sys.stderr)

    # Parse and insert all entries
    print("Parsing and importing entries...", file=sys.stderr)
    total_entries = 0
    total_senses = 0
    total_examples = 0
    failed = []

    headwords = sorted(index.keys())
    batch_size = 1000

    for i, headword in enumerate(headwords):
        if i % batch_size == 0 and i > 0:
            db.commit()
            print(f"  {i}/{len(headwords)} headwords processed...", file=sys.stderr)

        try:
            html = _read_entry_at(body_data, index[headword])
            entries = parse_entry(html)

            parent_id = None
            for entry_index, (entry, _raw_html) in enumerate(entries):
                if entry.card_type == 'idiom':
                    _insert_entry(db, source_id, entry, entry_index, parent_entry_id=parent_id)
                else:
                    parent_id = _insert_entry(db, source_id, entry, entry_index)
                total_entries += 1
                for g in entry.groups:
                    total_senses += len(g.senses)
                    for s in g.senses:
                        total_examples += len(s.examples)

            if verbose and entries:
                pos_list = ", ".join(e.pos for e, _ in entries if e.pos)
                print(f"    {headword} ({pos_list}): {len(entries)} entries", file=sys.stderr)

        except Exception as e:
            failed.append((headword, str(e)))
            if verbose:
                print(f"    FAILED: {headword}: {e}", file=sys.stderr)

    db.commit()

    # Build variants
    print("Building variant index...", file=sys.stderr)
    variants = _build_variants(body_data, index)
    print(f"  {len(variants)} variants found", file=sys.stderr)

    # Map variant -> entry_id(s) for the target headword
    for variant, target_headword in variants.items():
        rows = db.execute(
            "SELECT id FROM entries WHERE headword = ?",
            (target_headword,),
        ).fetchall()
        for (entry_id,) in rows:
            db.execute(
                "INSERT OR IGNORE INTO variants (entry_id, variant) VALUES (?, ?)",
                (entry_id, variant),
            )
    db.commit()

    # Populate definition/example FTS index
    print("Building definition/example FTS index...", file=sys.stderr)
    db.execute("""
        INSERT INTO dictionary_fts(rowid, headword, definitions, examples)
        SELECT
            e.id,
            e.headword,
            COALESCE((SELECT GROUP_CONCAT(s.definition, char(10))
                      FROM senses s WHERE s.entry_id = e.id), ''),
            COALESCE((SELECT GROUP_CONCAT(ex.text_plain, char(10))
                      FROM examples ex
                      JOIN senses s2 ON ex.sense_id = s2.id
                      WHERE s2.entry_id = e.id), '')
        FROM entries e
    """)
    db.execute("INSERT INTO dictionary_fts(dictionary_fts) VALUES('optimize')")
    db.commit()
    fts_count = db.execute("SELECT COUNT(*) FROM dictionary_fts").fetchone()[0]
    print(f"  {fts_count} entries indexed", file=sys.stderr)

    # Populate Chinese FTS index (trigram tokenizer; dual Traditional + Simplified)
    print("Building Chinese definition/example FTS index...", file=sys.stderr)
    rows = db.execute("""
        SELECT
            e.id,
            e.headword,
            COALESCE((SELECT GROUP_CONCAT(s.definition_zh, char(10))
                      FROM senses s
                      WHERE s.entry_id = e.id AND s.definition_zh != ''), ''),
            COALESCE((SELECT GROUP_CONCAT(ex.text_zh, char(10))
                      FROM examples ex
                      JOIN senses s2 ON ex.sense_id = s2.id
                      WHERE s2.entry_id = e.id AND ex.text_zh != ''), '')
        FROM entries e
    """).fetchall()

    zh_inserted = 0
    for entry_id, headword, defs_zh, examples_zh in rows:
        if not defs_zh and not examples_zh:
            continue
        # Store Traditional + Simplified back-to-back so trigram FTS matches either input form.
        defs_dual = f"{defs_zh}\n{t2s(defs_zh)}" if defs_zh else ""
        examples_dual = f"{examples_zh}\n{t2s(examples_zh)}" if examples_zh else ""
        db.execute(
            "INSERT INTO dictionary_fts_zh(rowid, headword, definitions_zh, examples_zh) "
            "VALUES (?, ?, ?, ?)",
            (entry_id, headword, defs_dual, examples_dual),
        )
        zh_inserted += 1

    db.execute("INSERT INTO dictionary_fts_zh(dictionary_fts_zh) VALUES('optimize')")
    db.commit()
    print(f"  {zh_inserted} entries indexed (Chinese)", file=sys.stderr)

    # Optimize
    print("Optimizing database...", file=sys.stderr)
    db.execute("PRAGMA optimize")
    db.commit()
    db.close()

    # Report
    print(file=sys.stderr)
    print(f"Import complete: {db_path}", file=sys.stderr)
    print(f"  Headwords:  {len(headwords)}", file=sys.stderr)
    print(f"  Entries:    {total_entries}", file=sys.stderr)
    print(f"  Senses:    {total_senses}", file=sys.stderr)
    print(f"  Examples:  {total_examples}", file=sys.stderr)
    print(f"  Variants:  {len(variants)}", file=sys.stderr)
    if failed:
        print(f"  Failed:    {len(failed)}", file=sys.stderr)
        for word, err in failed[:10]:
            print(f"    {word}: {err}", file=sys.stderr)
        if len(failed) > 10:
            print(f"    ... and {len(failed) - 10} more", file=sys.stderr)

    size_mb = db_path.stat().st_size / (1024 * 1024)
    print(f"  DB size:   {size_mb:.1f} MB", file=sys.stderr)
