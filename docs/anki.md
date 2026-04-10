# Anki Deck Generator

Generate Anki flashcard decks (.apkg) from OALD10 dictionary entries.

## Requirements

```bash
pip install genanki
```

## Usage

Run from the project root:

```bash
# Specific words
python anki/create_deck.py run abandon set

# Oxford 5000 word list
python anki/create_deck.py --5000

# Custom word list (anki/custom-words.csv)
python anki/create_deck.py --custom

# Every word in the dictionary
python anki/create_deck.py --all
```

## Files

```
anki/
├── create_deck.py      # Deck generator (reads Body.data directly)
├── clean_csv.py        # Remove empty lines from custom-words.csv
├── oxford-5000.csv     # Oxford 5000 word list
└── custom-words.csv    # Your custom word list
```

## Custom Word List

Edit `anki/custom-words.csv` with one word per row (CSV with `word` header):

```csv
word
abandon
run
set
```

Run `python anki/clean_csv.py` to remove empty lines.
