# Database

## Schema

```
sources              — data provenance (OALD10, future sources)
entries              — headword + POS + IPA + CEFR + raw_html (76K rows)
  ├── pronunciations — GB/US audio files per entry
  ├── verb_forms     — conjugation table with audio
  ├── sense_groups   — topic clusters ("intention", "arrangement", ...)
  │   └── senses     — numbered definitions with CEFR level
  │       └── examples — sentences with HTML highlighting + audio + Chinese
  ├── synonyms       — synonym words with definitions
  ├── word_origins   — etymology (plain + HTML with italic terms)
  ├── word_family    — related forms (happy/happily/happiness)
  ├── collocations   — grouped by category (verbs/adverbs/prepositions)
  ├── xrefs          — cross-references (see also, compare)
  ├── phrasal_verbs  — linked phrasal verb phrases
  └── extra_examples — additional example sentences
variants             — alternate spellings → canonical entries
audio_files          — embedded MP3 binary data (217K files)
entries_fts          — FTS5 full-text search index
meta                 — schema version tracking
```

All Chinese text is **Traditional Chinese** (converted from Simplified via OpenCC at build time).

Raw HTML is preserved (zlib-compressed) for every entry, enabling re-parsing if the parser is improved.

## Data Source

`Body.data` in the macOS dictionary bundle stores entries as sequential zlib-compressed HTML blocks. Each block has a 12-byte header:

```
[sz1: 4B][sz2: 4B][decompressed_size: 4B][zlib data: sz2-4 bytes]
```

First block at offset `0x60`. Each decompressed block is Apple Dictionary Services XML with rich HTML content including definitions, examples, pronunciation, collocations, etymology, and more.

## Build Pipeline

1. **Index**: Scan `Body.data` to map 62,131 headwords to byte offsets
2. **Parse**: Decompress each entry and extract structured data via regex
3. **Convert**: Apply OpenCC `s2t` to all Chinese text fields
4. **Store**: Insert into SQLite with batch transactions
5. **Variants**: Build alternate spelling index
6. **Audio**: Read and embed all referenced MP3 files as BLOBs
7. **Optimize**: Run PRAGMA optimize

## Audio File Naming

| Type | Pattern | Example |
|------|---------|---------|
| Word pronunciation | `{word}__{dialect}_{n}.mp3` | `run__gb_1.mp3` |
| Phrase pronunciation | `{phrase}_{sense}_{dialect}_{n}.mp3` | `run_down_1_gb_1.mp3` |
| Sentence example | `_{word}__{code}_{n}.mp3` | `_run__gbs_1.mp3` |

Dialect codes: `gb`/`us` for words; `gbs`/`uss`/`brs`/`ams` for sentences.

## Stats

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
