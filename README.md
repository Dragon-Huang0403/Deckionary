# OALD10 Dictionary App & Anki Deck Generator

Python toolkit for the **Oxford Advanced Learner's Dictionary 10th Edition**: a self-contained SQLite dictionary database, a web-based dictionary browser, and an Anki flashcard generator.

---

## What's Inside

### Dictionary Database (`oald10.db`)

A single SQLite file containing the complete OALD10 dictionary, built from the macOS dictionary bundle:

| Data | Count |
|------|-------|
| Headwords | 62,131 |
| Entries (multi-POS) | 76,210 |
| Definitions | 110,600 |
| Examples | 145,014 |
| Extra Examples | 62,189 |
| Audio Files (embedded MP3) | 217,156 |
| Synonyms | 4,725 |
| Word Origins | 22,325 |
| Word Family entries | 1,198 |
| Collocations | 48,783 |
| Cross-references | 961 |
| Phrasal Verb links | 2,523 |
| Variant spellings | 6,919 |

All Chinese text is **Traditional Chinese** (converted from Simplified via OpenCC at build time).

Raw HTML is preserved (zlib-compressed) for every entry, enabling re-parsing if the parser is improved.

### Web Dictionary (`app.py`)

A Flask-based dictionary browser with:

- Live search with debounce (exact match, fuzzy match, FTS5 prefix search)
- Full entry display: headword, POS, IPA (GB/US), CEFR badges, Oxford 3000/5000 badges
- Audio playback for word pronunciation (GB/US) and example sentences
- Definitions with Traditional Chinese translations
- Example sentences with HTML highlighting preserved (collocations in bold)
- Verb conjugation tables with audio
- **Synonyms** with pill tags and distinguishing definitions
- **Word Family** (happy/happily/happiness with opposites)
- **Collocations** grouped by category (verbs, adverbs, prepositions, phrases)
- **Cross-references** (clickable "see also" and "compare" links)
- **Phrasal Verbs** (clickable pills that trigger search)
- **Word Origin / Etymology** with italic foreign language terms
- **Extra Examples** (collapsible, with count)
- Dark mode support (follows system preference)

### Anki Deck Generator (`create_deck.py`)

Generates `.apkg` files with audio for import into Anki. Cards show headword + IPA on front, definitions + examples + audio on back.

---

## Requirements

- Python 3.10+
- A copy of the OALD10 macOS dictionary bundle (`oxford.dictionary`)

### Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install genanki flask opencc-python-reimplemented
```

---

## Quick Start

### 1. Build the database

```bash
python build_db.py
```

This reads `oxford.dictionary/Contents/Body.data`, parses all 62,131 entries, embeds 217K audio files, converts Chinese to Traditional, and writes `oald10.db` (~2.1 GB). Takes about 10 minutes.

### 2. Browse the dictionary

```bash
python app.py --port 8000
```

Open http://localhost:8000 in your browser.

### 3. Generate Anki decks

```bash
python create_deck.py run              # single word
python create_deck.py run abandon set  # multiple words
python create_deck.py --5000           # Oxford 5000 word list
python create_deck.py --custom         # custom word list (custom-words.csv)
python create_deck.py --all            # all 62,137 entries
```

---

## Project Structure

```
.
├── app.py                  # Flask web dictionary
├── build_db.py             # CLI to build oald10.db
├── create_deck.py          # Anki deck generator
├── lookup_word.py          # Interactive browser-based word lookup
├── list_words.py           # List all headwords
├── clean_csv.py            # Remove blank lines from CSV
├── db/
│   ├── __init__.py
│   ├── schema.py           # SQLite schema (15 tables)
│   ├── models.py           # Dataclasses for all parsed data
│   ├── parser.py           # HTML parser (regex-based, extracts all fields)
│   ├── importer.py         # Build pipeline: Body.data → parse → SQLite + OpenCC
│   └── query.py            # Read API: lookup, fuzzy search, FTS5, audio
├── templates/
│   └── index.html          # Single-page dictionary frontend
├── oxford-5000.csv         # Oxford 5000 word list
├── custom-words.csv        # User's custom word list
└── oxford.dictionary/      # Symlink to macOS dictionary bundle (not in repo)
```

## Database Schema

```
sources              ─ data provenance (OALD10, future sources)
entries              ─ headword + POS + IPA + CEFR + raw_html (76K rows)
  ├── pronunciations ─ GB/US audio files per entry
  ├── verb_forms     ─ conjugation table with audio
  ├── sense_groups   ─ topic clusters ("intention", "arrangement", ...)
  │   └── senses     ─ numbered definitions with CEFR level
  │       └── examples ─ sentences with HTML highlighting + audio + Chinese
  ├── synonyms       ─ synonym words with definitions
  ├── word_origins   ─ etymology (plain + HTML with italic terms)
  ├── word_family    ─ related forms (happy/happily/happiness)
  ├── collocations   ─ grouped by category (verbs/adverbs/prepositions)
  ├── xrefs          ─ cross-references (see also, compare)
  ├── phrasal_verbs  ─ linked phrasal verb phrases
  └── extra_examples ─ additional example sentences
variants             ─ alternate spellings → canonical entries
audio_files          ─ embedded MP3 binary data (217K files)
entries_fts          ─ FTS5 full-text search index
meta                 ─ schema version tracking
```

## How It Works

### Data Source

`Body.data` in the macOS dictionary bundle stores entries as sequential zlib-compressed HTML blocks. Each block has a 12-byte header:

```
[sz1: 4B][sz2: 4B][decompressed_size: 4B][zlib data: sz2-4 bytes]
```

First block at offset `0x60`. Each decompressed block is Apple Dictionary Services XML with rich HTML content including definitions, examples, pronunciation, collocations, etymology, and more.

### Build Pipeline

1. **Index**: Scan `Body.data` to map 62,131 headwords to byte offsets
2. **Parse**: Decompress each entry and extract structured data via regex
3. **Convert**: Apply OpenCC `s2t` to all Chinese text fields
4. **Store**: Insert into SQLite with batch transactions
5. **Variants**: Build alternate spelling index
6. **Audio**: Read and embed all referenced MP3 files as BLOBs
7. **Optimize**: Run PRAGMA optimize

### Audio File Naming

| Type | Pattern | Example |
|------|---------|---------|
| Word pronunciation | `{word}__{dialect}_{n}.mp3` | `run__gb_1.mp3` |
| Phrase pronunciation | `{phrase}_{sense}_{dialect}_{n}.mp3` | `run_down_1_gb_1.mp3` |
| Sentence example | `_{word}__{code}_{n}.mp3` | `_run__gbs_1.mp3` |

Dialect codes: `gb`/`us` for words; `gbs`/`uss`/`brs`/`ams` for sentences.

---

## Dictionary Data Note

This repo contains only code. You must supply the OALD10 dictionary bundle yourself. Installed macOS dictionaries are typically at `~/Library/Dictionaries/`. Symlink or copy the `.dictionary` folder as `oxford.dictionary` in the project root.
