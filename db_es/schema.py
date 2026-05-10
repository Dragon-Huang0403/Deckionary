"""SQLite schema for the Spanish dictionary (vox_es.db).

Mirrors db/schema.py with these adaptations:
- ES-only: dropped ipa_us / dialect 'us' columns; ES has one IPA, one dialect.
- Bilingual gloss: definition_zh -> definition_en, text_zh -> text_en (so the
  "secondary language" column role is preserved). Senses store ES def in
  `definition`, EN gloss in `definition_en`.
- Added `gender` on entries (m/f/mf/empty) for nouns.
- Dropped: ox3000, ox5000 (no equivalent curated list yet for Spanish).
- Dropped: dictionary_fts_zh, dictionary_zh_like (English UI; FTS uses unicode61
  on a single mixed ES+EN content).
- audio_files BLOB table: omitted. Audio served from on-disk audio_es/ during
  preview phase; can be added later if we mirror to R2.
"""

import sqlite3

SCHEMA_VERSION = 2

TABLES = """
CREATE TABLE IF NOT EXISTS sources (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    version     TEXT NOT NULL DEFAULT '',
    imported_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS entries (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER NOT NULL REFERENCES sources(id),
    headword    TEXT NOT NULL,
    pos         TEXT NOT NULL DEFAULT '',
    gender      TEXT NOT NULL DEFAULT '',
    entry_index INTEGER NOT NULL DEFAULT 0,
    ipa         TEXT NOT NULL DEFAULT '',
    cefr_level  TEXT NOT NULL DEFAULT '',
    frequency_tier TEXT NOT NULL DEFAULT '',
    parent_entry_id INTEGER REFERENCES entries(id) ON DELETE CASCADE,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_entries_headword       ON entries(headword);
CREATE INDEX IF NOT EXISTS idx_entries_source         ON entries(source_id);
CREATE INDEX IF NOT EXISTS idx_entries_pos            ON entries(pos);
CREATE INDEX IF NOT EXISTS idx_entries_parent         ON entries(parent_entry_id);
CREATE INDEX IF NOT EXISTS idx_entries_frequency_tier ON entries(frequency_tier);

CREATE TABLE IF NOT EXISTS pronunciations (
    id          INTEGER PRIMARY KEY,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    ipa         TEXT NOT NULL DEFAULT '',
    audio_file  TEXT NOT NULL DEFAULT '',
    UNIQUE(entry_id)
);

CREATE TABLE IF NOT EXISTS verb_forms (
    id          INTEGER PRIMARY KEY,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    form_label  TEXT NOT NULL DEFAULT '',
    form_text   TEXT NOT NULL,
    audio_file  TEXT NOT NULL DEFAULT '',
    sort_order  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_verb_forms_entry ON verb_forms(entry_id);

CREATE TABLE IF NOT EXISTS sense_groups (
    id          INTEGER PRIMARY KEY,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    topic       TEXT NOT NULL DEFAULT '',
    topic_en    TEXT NOT NULL DEFAULT '',
    sort_order  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_sense_groups_entry ON sense_groups(entry_id);

CREATE TABLE IF NOT EXISTS senses (
    id              INTEGER PRIMARY KEY,
    sense_group_id  INTEGER NOT NULL REFERENCES sense_groups(id) ON DELETE CASCADE,
    entry_id        INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    sense_num       INTEGER,
    grammar         TEXT NOT NULL DEFAULT '',
    labels          TEXT NOT NULL DEFAULT '',
    variants        TEXT NOT NULL DEFAULT '',
    definition      TEXT NOT NULL,
    definition_en   TEXT NOT NULL DEFAULT '',
    sort_order      INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_senses_group ON senses(sense_group_id);
CREATE INDEX IF NOT EXISTS idx_senses_entry ON senses(entry_id);

CREATE TABLE IF NOT EXISTS examples (
    id              INTEGER PRIMARY KEY,
    sense_id        INTEGER NOT NULL REFERENCES senses(id) ON DELETE CASCADE,
    text_plain      TEXT NOT NULL,
    text_html       TEXT NOT NULL DEFAULT '',
    text_en         TEXT NOT NULL DEFAULT '',
    audio_file      TEXT NOT NULL DEFAULT '',
    sort_order      INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_examples_sense ON examples(sense_id);

CREATE TABLE IF NOT EXISTS variants (
    id          INTEGER PRIMARY KEY,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    variant     TEXT NOT NULL,
    UNIQUE(variant, entry_id)
);

CREATE INDEX IF NOT EXISTS idx_variants_variant ON variants(variant);

CREATE TABLE IF NOT EXISTS xrefs (
    id              INTEGER PRIMARY KEY,
    entry_id        INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    sense_group_id  INTEGER REFERENCES sense_groups(id) ON DELETE CASCADE,
    sense_id        INTEGER REFERENCES senses(id) ON DELETE CASCADE,
    xref_type       TEXT NOT NULL,
    target_word     TEXT NOT NULL,
    sort_order      INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_xrefs_entry ON xrefs(entry_id);

CREATE TABLE IF NOT EXISTS phrases (
    id          INTEGER PRIMARY KEY,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    phrase      TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_phrases_entry ON phrases(entry_id);

CREATE TABLE IF NOT EXISTS word_origins (
    id          INTEGER PRIMARY KEY,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    text_html   TEXT NOT NULL DEFAULT '',
    text_plain  TEXT NOT NULL DEFAULT '',
    UNIQUE(entry_id)
);
"""

FTS_TABLE = """
CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    headword,
    content='entries',
    content_rowid='id'
);

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
"""

DICTIONARY_FTS_TABLE = """
CREATE VIRTUAL TABLE IF NOT EXISTS dictionary_fts USING fts5(
    headword,
    definitions,
    examples,
    glosses_en,
    content='',
    tokenize='unicode61 remove_diacritics 2'
);
"""

META_TABLE = """
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
"""


def create_schema(db: sqlite3.Connection) -> None:
    db.executescript(TABLES)
    db.executescript(FTS_TABLE)
    db.executescript(DICTIONARY_FTS_TABLE)
    db.executescript(META_TABLE)
    db.execute(
        "INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)",
        (str(SCHEMA_VERSION),),
    )
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.commit()
