"""Read API for the dictionary database."""

import re
import sqlite3
import zlib
from pathlib import Path

from .models import (
    CollocationData, EntryData, ExampleData, ExtraExampleData,
    SenseData, SenseGroupData, SynonymData, VerbFormData,
    WordFamilyData, XrefData,
)

DEFAULT_DB = Path("oald10.db")


def connect(db_path: str | Path = DEFAULT_DB) -> sqlite3.Connection:
    db = sqlite3.connect(str(db_path))
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    return db


def _load_entry(db: sqlite3.Connection, row: sqlite3.Row) -> EntryData:
    """Load a full EntryData from an entries row, including all children."""
    entry_id = row["id"]

    # Pronunciations
    prons = db.execute(
        "SELECT dialect, ipa, audio_file FROM pronunciations WHERE entry_id = ?",
        (entry_id,),
    ).fetchall()
    audio_gb = ipa_gb = audio_us = ipa_us = ""
    for p in prons:
        if p["dialect"] == "gb":
            ipa_gb = p["ipa"]
            audio_gb = p["audio_file"]
        elif p["dialect"] == "us":
            ipa_us = p["ipa"]
            audio_us = p["audio_file"]

    # Verb forms
    vf_rows = db.execute(
        "SELECT form_label, form_text, audio_gb, audio_us FROM verb_forms WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()
    verb_forms = [
        VerbFormData(form_label=r["form_label"], form_text=r["form_text"],
                     audio_gb=r["audio_gb"], audio_us=r["audio_us"])
        for r in vf_rows
    ]

    # Load all xrefs for this entry at once, partition by level
    all_xref_rows = db.execute(
        """SELECT sense_group_id, sense_id, xref_type, target_word
           FROM xrefs WHERE entry_id = ? ORDER BY sort_order""",
        (entry_id,),
    ).fetchall()
    # Group by sense_id and sense_group_id
    sense_xrefs: dict[int, list[XrefData]] = {}
    group_xrefs: dict[int, list[XrefData]] = {}
    entry_xrefs: list[XrefData] = []
    for xr in all_xref_rows:
        xd = XrefData(xref_type=xr["xref_type"], target_word=xr["target_word"])
        if xr["sense_id"] is not None:
            sense_xrefs.setdefault(xr["sense_id"], []).append(xd)
        elif xr["sense_group_id"] is not None:
            group_xrefs.setdefault(xr["sense_group_id"], []).append(xd)
        else:
            entry_xrefs.append(xd)

    # Sense groups -> senses -> examples
    groups = []
    sg_rows = db.execute(
        "SELECT id, topic_en, topic_zh FROM sense_groups WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()

    for sg in sg_rows:
        s_rows = db.execute(
            """SELECT id, sense_num, cefr_level, grammar, labels, variants,
                      definition, definition_zh
               FROM senses WHERE sense_group_id = ? ORDER BY sort_order""",
            (sg["id"],),
        ).fetchall()

        senses = []
        for s in s_rows:
            ex_rows = db.execute(
                """SELECT text_plain, text_html, text_zh, audio_gb, audio_us
                   FROM examples WHERE sense_id = ? ORDER BY sort_order""",
                (s["id"],),
            ).fetchall()
            examples = [
                ExampleData(
                    text_plain=e["text_plain"], text_html=e["text_html"],
                    text_zh=e["text_zh"], audio_gb=e["audio_gb"], audio_us=e["audio_us"],
                )
                for e in ex_rows
            ]
            senses.append(SenseData(
                sense_num=s["sense_num"], cefr_level=s["cefr_level"],
                grammar=s["grammar"], labels=s["labels"], variants=s["variants"],
                definition=s["definition"], definition_zh=s["definition_zh"],
                examples=examples,
                xrefs=sense_xrefs.get(s["id"], []),
            ))
        groups.append(SenseGroupData(
            topic_en=sg["topic_en"], topic_zh=sg["topic_zh"], senses=senses,
            xrefs=group_xrefs.get(sg["id"], []),
        ))

    # Synonyms
    syn_rows = db.execute(
        "SELECT group_title, word, definition FROM synonyms WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()
    synonyms = [SynonymData(word=r["word"], group_title=r["group_title"], definition=r["definition"]) for r in syn_rows]

    # Word origin
    wo_row = db.execute(
        "SELECT text_plain, text_html FROM word_origins WHERE entry_id = ?",
        (entry_id,),
    ).fetchone()
    word_origin = wo_row["text_plain"] if wo_row else ""
    word_origin_html = wo_row["text_html"] if wo_row else ""

    # Word family
    wf_rows = db.execute(
        "SELECT word, pos, opposite FROM word_family WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()
    word_family = [WordFamilyData(word=r["word"], pos=r["pos"], opposite=r["opposite"]) for r in wf_rows]

    # Collocations
    coll_rows = db.execute(
        "SELECT category, words FROM collocations WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()
    collocations = [CollocationData(category=r["category"], words=r["words"].split(", ")) for r in coll_rows]

    # Phrasal verbs
    pv_rows = db.execute(
        "SELECT phrase FROM phrasal_verbs WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()
    phrasal_verbs = [r["phrase"] for r in pv_rows]

    # Extra examples
    ee_rows = db.execute(
        "SELECT text_plain, text_html, text_zh FROM extra_examples WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall()
    extra_examples = [ExtraExampleData(text_plain=r["text_plain"], text_html=r["text_html"], text_zh=r["text_zh"]) for r in ee_rows]

    return EntryData(
        headword=row["headword"],
        pos=row["pos"],
        ipa_gb=ipa_gb,
        ipa_us=ipa_us,
        audio_gb=audio_gb,
        audio_us=audio_us,
        cefr_level=row["cefr_level"],
        ox3000=bool(row["ox3000"]),
        ox5000=bool(row["ox5000"]),
        groups=groups,
        verb_forms=verb_forms,
        card_type="idiom" if row["pos"] == "idiom" else "word",
        raw_html=zlib.decompress(row["raw_html"]).decode("utf-8") if row["raw_html"] else "",
        synonyms=synonyms,
        word_origin=word_origin,
        word_origin_html=word_origin_html,
        word_family=word_family,
        collocations=collocations,
        xrefs=entry_xrefs,
        phrasal_verbs=phrasal_verbs,
        extra_examples=extra_examples,
    )


def lookup_word(db: sqlite3.Connection, headword: str) -> list[EntryData]:
    """Primary lookup by exact headword match."""
    rows = db.execute(
        "SELECT * FROM entries WHERE headword = ? ORDER BY entry_index",
        (headword.lower().strip(),),
    ).fetchall()
    return [_load_entry(db, r) for r in rows]


def lookup_variant(db: sqlite3.Connection, headword: str) -> list[EntryData]:
    """Look up via variant spellings table."""
    rows = db.execute(
        """SELECT e.* FROM entries e
           JOIN variants v ON v.entry_id = e.id
           WHERE v.variant = ?
           ORDER BY e.entry_index""",
        (headword.lower().strip(),),
    ).fetchall()
    return [_load_entry(db, r) for r in rows]


def _fuzzy_match(db: sqlite3.Connection, key: str) -> list[EntryData]:
    """Try common fuzzy matches: trademark symbols, plural/verb suffixes."""
    # Trademark symbols
    rows = db.execute(
        "SELECT * FROM entries WHERE headword LIKE ? ORDER BY entry_index",
        (key + "%",),
    ).fetchall()
    for r in rows:
        stripped = re.sub(r'[™®©]', '', r["headword"])
        if stripped == key:
            return [_load_entry(db, r2) for r2 in
                    db.execute("SELECT * FROM entries WHERE headword = ? ORDER BY entry_index",
                               (r["headword"],)).fetchall()]

    # Suffix stripping
    for suffix in ('s', 'es', 'ies', 'ed', 'ing', 'ly'):
        if key.endswith(suffix):
            base = key[:-len(suffix)]
            results = lookup_word(db, base)
            if results:
                return results
            if suffix == 'ies':
                results = lookup_word(db, base + 'y')
                if results:
                    return results
            if suffix == 'ed':
                results = lookup_word(db, base + 'e')
                if results:
                    return results
    return []


def fuzzy_lookup(db: sqlite3.Connection, headword: str) -> list[EntryData]:
    """Try exact -> variant -> fuzzy matching."""
    key = headword.lower().strip()
    results = lookup_word(db, key)
    if results:
        return results
    results = lookup_variant(db, key)
    if results:
        return results
    return _fuzzy_match(db, key)


def search(db: sqlite3.Connection, query: str, limit: int = 20) -> list[EntryData]:
    """Full-text search on headwords."""
    rows = db.execute(
        """SELECT e.* FROM entries_fts fts
           JOIN entries e ON e.id = fts.rowid
           WHERE fts.headword MATCH ?
           LIMIT ?""",
        (query, limit),
    ).fetchall()
    return [_load_entry(db, r) for r in rows]


def list_headwords(db: sqlite3.Connection, source_id: int | None = None) -> list[str]:
    """Return all unique headwords."""
    if source_id:
        rows = db.execute(
            "SELECT DISTINCT headword FROM entries WHERE source_id = ? ORDER BY headword",
            (source_id,),
        ).fetchall()
    else:
        rows = db.execute(
            "SELECT DISTINCT headword FROM entries ORDER BY headword",
        ).fetchall()
    return [r["headword"] for r in rows]


def get_entries_by_cefr(db: sqlite3.Connection, level: str) -> list[EntryData]:
    """Get all entries at a specific CEFR level."""
    rows = db.execute(
        "SELECT * FROM entries WHERE cefr_level = ? ORDER BY headword, entry_index",
        (level.lower(),),
    ).fetchall()
    return [_load_entry(db, r) for r in rows]


def get_oxford_entries(db: sqlite3.Connection, ox3000: bool = False, ox5000: bool = False) -> list[EntryData]:
    """Get entries by Oxford 3000/5000 membership."""
    conditions = []
    if ox3000:
        conditions.append("ox3000 = 1")
    if ox5000:
        conditions.append("ox5000 = 1")
    if not conditions:
        return []
    where = " OR ".join(conditions)
    rows = db.execute(
        f"SELECT * FROM entries WHERE {where} ORDER BY headword, entry_index",
    ).fetchall()
    return [_load_entry(db, r) for r in rows]


def get_audio(db: sqlite3.Connection, filename: str) -> bytes | None:
    """Get audio file data by filename."""
    row = db.execute(
        "SELECT data FROM audio_files WHERE filename = ?",
        (filename,),
    ).fetchone()
    return row["data"] if row else None


def to_legacy_dict(entry: EntryData) -> dict:
    """Convert EntryData to the dict format used by create_deck.py's parse_entry().
    This enables backward compatibility with the existing Anki generation code."""
    media_files = set()
    if entry.audio_gb:
        media_files.add(entry.audio_gb)
    if entry.audio_us:
        media_files.add(entry.audio_us)

    groups = []
    for g in entry.groups:
        senses = []
        for s in g.senses:
            examples = []
            for ex in s.examples:
                if ex.audio_us:
                    media_files.add(ex.audio_us)
                if ex.audio_gb:
                    media_files.add(ex.audio_gb)
                examples.append({
                    "text": ex.text_plain,
                    "text_zh": ex.text_zh,
                    "audio_us": ex.audio_us,
                })
            senses.append({
                "sense_num": s.sense_num,
                "grammar": s.grammar,
                "labels": s.labels,
                "variants": s.variants,
                "definition": s.definition,
                "definition_zh": s.definition_zh,
                "examples": examples,
            })
        groups.append({
            "topic_en": g.topic_en,
            "topic_zh": g.topic_zh,
            "senses": senses,
        })

    verb_forms = [
        {"label_word": vf.form_text, "audio_us": vf.audio_us}
        for vf in entry.verb_forms
    ]

    return {
        "headword": entry.headword,
        "pos": entry.pos,
        "ipa_gb": entry.ipa_gb,
        "ipa_us": entry.ipa_us,
        "audio_gb": entry.audio_gb,
        "audio_us": entry.audio_us,
        "groups": groups,
        "verb_forms": verb_forms,
        "media_files": media_files,
        "card_type": entry.card_type,
    }
