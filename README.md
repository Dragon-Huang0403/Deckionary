# OALD10 Dictionary App & Anki Deck Generator

Python toolkit for the **Oxford Advanced Learner's Dictionary 10th Edition**: a SQLite dictionary database, a web dictionary browser, and an Anki flashcard generator.

## Requirements

- Python 3.10+
- A copy of the OALD10 macOS dictionary bundle (`oxford.dictionary`)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install genanki flask opencc-python-reimplemented
```

Installed macOS dictionaries are typically at `~/Library/Dictionaries/`. Symlink or copy the `.dictionary` folder as `oxford.dictionary` in the project root.

## Quick Start

```bash
# Build the database (~2.1 GB, ~10 minutes)
python build_db.py

# Browse the dictionary
python app.py --port 8000

# Generate Anki decks
python create_deck.py run abandon set    # specific words
python create_deck.py --5000             # Oxford 5000
python create_deck.py --all              # all entries
```

## Project Structure

```
.
├── app.py                  # Flask web dictionary
├── build_db.py             # CLI to build oald10.db
├── create_deck.py          # Anki deck generator
├── lookup_word.py          # Interactive word lookup
├── list_words.py           # List all headwords
├── db/
│   ├── schema.py           # SQLite schema (15 tables)
│   ├── models.py           # Dataclasses for parsed data
│   ├── parser.py           # HTML parser (regex-based)
│   ├── importer.py         # Build pipeline: Body.data → SQLite
│   └── query.py            # Read API: lookup, search, audio
├── scripts/
│   ├── export_for_r2.py    # Export HTML + audio filelist for R2
│   └── upload_to_r2.sh     # Upload to Cloudflare R2 via rclone
├── docs/
│   ├── database.md         # Schema, data source, build pipeline
│   └── r2-export.md        # Cloudflare R2 export guide
├── templates/
│   └── index.html          # Dictionary frontend
└── oxford.dictionary/      # macOS dictionary bundle (not in repo)
```
