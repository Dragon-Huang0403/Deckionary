# OALD10 Dictionary Scripts

Python scripts for querying the **Oxford Advanced Learner's Dictionary 10th Edition** macOS dictionary bundle.

This repo contains only the scripts. You must supply the dictionary data yourself (see below).

---

## Requirements

- Python 3.10+
- A copy of the OALD10 macOS dictionary bundle (`oxford.dictionary`)

### Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install genanki
```

`genanki` is only required for `create_deck.py`. The other two scripts use only the standard library.

---

## Directory Structure

The scripts expect the dictionary bundle to sit **alongside them** in the same directory:

```
OALD10/
├── oxford.dictionary/          ← dictionary bundle (not in this repo)
│   └── Contents/
│       ├── Body.data           ← all entries, zlib-compressed HTML (94 MB)
│       ├── KeyText.data        ← keyword trie index
│       ├── KeyText.index
│       ├── oald10.css          ← entry stylesheet
│       ├── oald10.js           ← entry interactivity
│       └── *.mp3               ← ~275 000 audio files (word + sentence)
├── oxford-5000.csv             ← Oxford 5000 word list (optional, for --5000)
├── list_words.py
├── lookup_word.py
├── create_deck.py
└── README.md
```

> **Where to get the bundle**
> The `oxford.dictionary` bundle is installed by the macOS Dictionary app.
> Installed dictionaries are typically found at:
> ```
> ~/Library/Dictionaries/
> ```
> Copy or symlink the `oxford.dictionary` folder into this directory.

---

## Scripts

### `list_words.py` — list all headwords

Prints all 62 137 headwords to stdout, one per line.

```bash
# Print to terminal
python list_words.py

# Save to file
python list_words.py words.txt
```

### `lookup_word.py` — look up a word

Finds the entry in `Body.data`, decompresses it, and opens the fully rendered HTML (with styling and working audio) in your default browser.

```bash
python lookup_word.py run
python lookup_word.py abandon
python lookup_word.py "run down"      # multi-word entries

# Print raw HTML instead of opening a browser
python lookup_word.py run --html
```

**First run** builds a word→offset index and saves it as `.oald10_index.json` (~10 seconds). Every subsequent lookup is instant.

### `create_deck.py` — generate an Anki deck

Creates an `.apkg` file importable into Anki. Each card shows the headword on the front and IPA, part of speech, definitions, and examples (with audio) on the back.

```bash
python create_deck.py run                  # single word
python create_deck.py run abandon set      # multiple words
python create_deck.py --5000               # Oxford 5000 word list
python create_deck.py --all                # all 62 137 entries
```

Output is always `oald10.apkg` in the current directory. Import it in Anki via **File → Import**.

The deck bundles all referenced audio files directly into the `.apkg`, so pronunciation and sentence audio work immediately after import without any extra setup.

#### Oxford 5000 word list

`--5000` reads `oxford-5000.csv` and deduplicates by headword before lookup. The CSV is sourced from [Berehulia/Oxford-3000-5000](https://github.com/Berehulia/Oxford-3000-5000).

---

## How It Works

`Body.data` stores all dictionary entries as sequential **zlib-compressed HTML blocks**. Each block has a 12-byte header:

```
[sz1: 4 bytes][sz2: 4 bytes][decompressed_size: 4 bytes][zlib data: sz2-4 bytes]
```

The first block starts at offset `0x60`. The index maps each lowercased headword to its block's byte offset so lookups can seek directly without scanning the file.

Each decompressed block is an Apple Dictionary Services XML fragment:

```xml
<d:entry d:title="run">
  <div class="entry" id="run_1">…</div>
</d:entry>
```

`lookup_word.py` strips the `<d:entry>` wrapper, rewrites relative `.mp3` paths to absolute `file://` URIs, injects `oald10.css` and `oald10.js`, and writes a self-contained HTML file to a temp directory.

### Audio file naming

| Type | Pattern | Example |
|------|---------|---------|
| Word pronunciation | `{word}__{dialect}_{n}.mp3` | `run__gb_1.mp3` |
| Phrase pronunciation | `{phrase}_{sense}_{dialect}_{n}.mp3` | `run_down_1_gb_1.mp3` |
| Sentence example | `_{word}__{code}_{n}.mp3` | `_run__gbs_1.mp3` |

Dialect codes: `gb` / `us` for words; `gbs` / `uss` / `brs` / `ams` for sentences.
All files live flat in `oxford.dictionary/Contents/`.
