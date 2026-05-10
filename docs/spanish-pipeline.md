# Spanish dictionary preview — pipeline reference

This is the canonical reference for the Spanish dictionary work that
parallels the OALD10 build. The artifact is `vox_es.db` plus a small
FastAPI preview server. Nothing here is wired into the Flutter app yet
— that's a deliberate "evaluate quality before integrating" gate.

Last updated: 2026-05-10.

## TL;DR

- **What**: build a Spanish-for-English-speakers dictionary in the same
  schema shape as `oald10.db`, with a web preview to judge quality.
- **Output**: `vox_es.db` (~72 MB, 61,656 entries).
- **Sources used**:
  - Larousse "Spanish" monolingual macOS Dictionary.app bundle (Body.data extraction)
  - Oxford "Spanish - English" bilingual macOS Dictionary.app bundle (Body.data extraction)
  - hermitdave/FrequencyWords ES list (OpenSubtitles-derived) for frequency tier
  - **espeak-ng** (build-time only) for IPA generation
  - Wikimedia Commons (Lingua Libre Spanish recordings) for human audio (on-demand)
  - **Piper neural TTS** (`es_ES-sharvard-medium`, build-time pre-generation) for synthetic audio fallback — gives the dictionary 100% audio coverage
- **Run**: `python3 build_es_db.py` (one command; ~25 s).
- **Preview**: `uvicorn preview_web.server:app --reload --port 8137`

---

## Sources & licensing matrix

| Source | What it gives | Where it lives | License situation |
|---|---|---|---|
| Larousse "Spanish" bundle | ES headwords, ES senses, examples, etymology, sub-entry phrases | `/System/Library/AssetsV2/.../Spanish.dictionary/Contents/Resources/Body.data` | Apple-licensed; same grey area as OALD10 — extracted locally, never redistributed |
| Oxford "Spanish - English" bundle | EN translations per sense, bilingual examples (ES + EN), idioms | `/System/Library/AssetsV2/.../Spanish - English.dictionary/Contents/Resources/Body.data` | Same as above |
| hermitdave/FrequencyWords (ES) | Word→frequency rank from OpenSubtitles | `data_es/es_frequency_50k.txt` | MIT — redistributable |
| espeak-ng | Castilian Spanish IPA via G2P (text→phoneme) | `brew install espeak-ng` (build-time only, not in app) | GPL — fine, output is data |
| Wikimedia Commons (Lingua Libre) | Castilian Spanish audio recordings (real human voices) | Fetched on-demand via Commons API | CC-BY-SA — redistributable with attribution |
| Piper TTS (`es_ES-sharvard-medium`) | Castilian Spanish audio (synthetic, fallback) | Pre-generated locally in `audio_es_tts/` | Apache 2.0 — model + output free to use |

User must enable the two macOS bundles via **Dictionary.app → Settings →
Dictionary**:
- ☑ "Larousse Editorial Diccionario General de la Lengua Española"
- ☑ "Gran Diccionario Oxford – Español-Inglés • Inglés-Español"

After enabling, macOS auto-downloads them. `python3 -m db_es.importer`
lists installed bundles to confirm.

---

## Build pipeline

```
data_es/es_frequency_50k.txt   ──┐
                                 │
[Larousse Body.data]  ──┐        │
                        │  ┌─────▼──────────┐
[Oxford Body.data]    ──┼─►│ build_es_db.py │──► vox_es.db (72 MB)
                        │  └─────▲──────────┘
[espeak-ng (subprocess)]┘        │
                                 │
                   db_es/ipa_cache.sqlite (pre-warmed once)
```

Pipeline stages, in order (`build_es_db.py` orchestrates):

1. **Discover bundles** (`db_es.importer.find_dictionary_bundles`) →
   walks `/Library/Dictionaries`, `~/Library/Dictionaries`, and
   `/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_*/`
   for `.dictionary/Contents/.../Body.data`.

2. **Index Body.data** (`db_es.importer.BodyDataReader`) → walks the
   binary, decompresses each zlib block, finds every `<d:entry>...</d:entry>`
   inside (Apple bundles pack ~150 entries per block, not 1 like OALD10),
   indexes by `d:title` lowercased. Larousse: 60,674 unique. Oxford: 108K
   (both directions; ES entries filtered by `id="s_b-es-en..."`).

3. **Pre-warm IPA cache** (`db_es.ipa.precompute`) → batches all 60K mono
   headwords through `espeak-ng -v es --ipa -q` via stdin, stores results
   in `db_es/ipa_cache.sqlite`. ~21 s one-time, then cached.

4. **Load frequency tier map** (`db_es.frequency.load_tier_map`) → reads
   `es_frequency_50k.txt`, assigns tiers by rank: top1k / top2k / top5k /
   top10k / top20k.

5. **Per-headword loop** (`build_es_db.py:build`):
   - `parser_mono.parse_entry(html)` → ES senses, examples, sub-phrases
   - `parser_bilng.parse_entry(html)` → EN translations, bilingual examples
   - `_topic_en_for(pos, bilng_senses)` → joins EN translations grouped
     by POS to attach to each Spanish sense_group as a summary line
   - `ipa_cache` lookup → IPA string
   - `tier_map` lookup → frequency tier
   - `_insert_entry` writes one `entries` row + sense_groups + senses +
     examples + phrases

6. **Build dictionary_fts** at the end → unicode61-tokenized full-text
   search across headword + ES definitions + ES examples + EN glosses.

Throughput: ~2,500 entries/s on M-series Mac. Full build: ~25 s.

---

## Schema (`db_es/schema.py`, version 2)

Mirrors `db/schema.py` (OALD10) with these adaptations:

| OALD10 column | vox_es column | Notes |
|---|---|---|
| `ipa_gb`, `ipa_us` | `ipa` (single) | One IPA, Castilian |
| `definition_zh` | `definition_en` | Bilingual gloss role |
| `text_zh` (examples) | `text_en` | Bilingual example translation |
| `ox3000`, `ox5000` | `frequency_tier` | TEXT, values: top1k/top2k/top5k/top10k/top20k or empty |
| (none) | `gender` | New, on `entries`. Values: m/f/mf/empty |
| `dictionary_fts_zh` | (omitted) | No Chinese FTS |
| `audio_files` BLOB | (omitted) | Audio served from disk in preview phase |

Tables: `sources`, `entries`, `sense_groups`, `senses`, `examples`,
`pronunciations`, `verb_forms`, `variants`, `xrefs`, `phrases`,
`word_origins`, plus FTS tables. Foreign keys with cascading delete.

**Entry structure for a typical word** (`correr`):
- 1 `entries` row
- 7 ES `sense_groups` (one per Larousse POS section: vi+vt, vi, vt, vi…
  vp) + 1 "English meanings" sense_group
- 25 ES senses + 32 EN-side senses → 57 `senses` rows
- ~100 `examples`
- 5 `phrases` (locutions/idioms)
- Etymology in `word_origins`

---

## IPA — espeak-ng decision

We initially tried two failed approaches before landing here:

1. **Wiktionary XML dump → regex `{{IPA|es|...}}`**: parsed the 1.58 GB
   dump, found only **0.05% of Spanish entries** use the explicit IPA
   template. The rest use `{{es-pr}}`, a server-rendered template that
   computes IPA algorithmically from the headword.

2. **Hand-rolled rules-based generator** (~250 lines): worked on common
   words but an audit against Wiktionary's actual rendering showed only
   **~60% exact match**. Failed on hiatuses (`bahía`, `país`), `x` in
   foreign spellings (`México`), s-voicing (`mismo`), n-velarization
   (`cinco`), final-d (`verdad`).

Final approach: **espeak-ng** as a build-time subprocess. It's the same
G2P backbone Piper / Coqui / RHVoice all use under the hood — purpose-
built for this exact task. Tiny install, GPL (fine for build tools),
batch-mode does 60K words in ~21 s.

We chose espeak-ng over Piper/Coqui/MBROLA because those are TTS engines
(text → audio), not G2P engines (text → IPA). For pure G2P, espeak-ng is
the right-sized tool; the ML stacks would just route through it anyway.

Coverage: ~99% of dictionary headwords have IPA. Misses are mostly
non-Spanish words (proper-noun loans, abbreviations) where espeak-ng
correctly returns nothing.

---

## Audio — two-tier (human voice → synthetic fallback)

The macOS Spanish bundles **don't ship audio**. We use two sources:

1. **Wikimedia Commons** (preferred): real human voice recordings,
   fetched on-demand and cached. Coverage ~76% (excellent for top-20K
   words, drops off on long-tail vocabulary).
2. **Piper TTS** (fallback): pre-generated synthetic audio for every
   headword. Lifts overall coverage to **~100%**.

When the user clicks 🔊, the server tries Commons first; on miss, returns
the pre-generated TTS file. Response carries an `X-Audio-Source` header
that the frontend reads to mark synthetic playback with a small ✷.

### Server flow

```
GET /audio/{word}
   │
   ▼
commons_audio.fetch(word)
   │
   ├── Cache hit (found) ──► FileResponse + X-Audio-Source: wikimedia-commons
   │
   ├── Cache hit (missing) ─┐
   │                        │
   ├── Cache miss ─────────►│   API search → download → cache
   │                        │
   ▼                        ▼
   None ──► tts.lookup(word)
            │
            ├─► path ──► FileResponse + X-Audio-Source: piper-tts
            └─► None ──► 404 (rare; only entries with non-letter headwords)
```

### Commons fetch (`db_es/commons_audio.py`)

```
1. Cache check (audio_es/index.sqlite)
2. Commons API search: intitle:"LL-Q1321 (spa)" intitle:{word}
   - Filter: regex match exact word (so "tiempo" doesn't match "tiempos")
3. imageinfo API → direct CDN URL
4. Strip ?utm_* tracking params (Wikimedia 429s those)
5. Download into audio_es/<word>__es_1.{wav|ogg|mp3}
6. Cache outcome (found / missing) in audio_es/index.sqlite
7. Fallback chain if no LL hit: EN Wiktionary Spanish section <audio>,
   then ES Wiktionary anywhere on the page
```

### Piper TTS pre-generation (`db_es/tts.py`)

```
python3 -m db_es.tts --build
```

For every headword in `vox_es.db`:
1. Skip if already cached in `audio_es_tts/index.sqlite`
2. Synthesize WAV with Piper `es_ES-sharvard-medium` (Castilian neural TTS)
3. Pipe through `ffmpeg → libmp3lame -q 5` for ~5 KB MP3
4. Write to `audio_es_tts/<safe_word>.mp3`
5. Record (word, file, generated_at) in cache index

One-time cost: **~55 minutes for 60K words on M-series Mac, ~413 MB total disk**.
Subsequent runs are no-ops (skip cached). The build is independent of
`build_es_db.py` — `vox_es.db` is the input list; nothing changes in its
schema.

### Why Lingua Libre is the primary

`LL-Q1321 (spa)-...` is the Wikidata Q-ID for the Spanish language,
prefix used by the Lingua Libre crowdsourcing project (Wikimedia's
pronunciation recording tool). Filenames are predictable and the
recordings are by self-identified Spanish speakers. Most contributors
are in Spain → leans Castilian, though some Latin-American voices appear.
We don't filter by speaker country (would require an extra Wikidata
lookup per file); accept the small dialect variation as cost-of-free.

### Politeness

- 1 req/s minimum interval between any HTTP calls (Wikimedia bot policy)
- 429-aware retry with 5-s backoff
- Custom UA: `DeckionaryPreview/0.1 ...`

### Coverage

**Wikimedia Commons (real human voice) — sampled 2026-05-09:**

| Tier | Coverage |
|---|---|
| top1k (most common 1,000) | **5/5 (100%)** |
| top5k | **5/5 (100%)** |
| top10k | 4/5 (80%) |
| top20k | 4/5 (80%) |
| Untiered (long-tail dictionary words) | 1/5 (20%) |
| **Commons subtotal** | **19/25 (76%)** |

The pattern matches the underlying truth: Lingua Libre volunteers
recorded common vocabulary first. Drops off for archaic / domain-
specific entries.

**With Piper TTS fallback — verified 2026-05-10 (live HTTP test, 25 random words across tiers):**

| Tier | Result |
|---|---|
| top1k | 5/5 — all Commons |
| top5k | 5/5 — all Commons |
| top10k | 5/5 — 4 Commons, 1 Piper |
| top20k | 5/5 — 4 Commons, 1 Piper |
| Untiered (long tail) | 5/5 — 1 Commons, 4 Piper |
| **Total** | **25/25 (100%)** — 19 Commons, 6 Piper |

Piper cleanly fills exactly the gaps Commons can't (`cierro`, `cayo`,
`lugre`, `resistero`, `imprimar`, `ixtle`). Cache state: 60,673 / 60,674
unique headwords have a pre-generated TTS file. The single uncovered
entry is the empty-headword degenerate case (filtered at synthesis time).

### Why Commons stays on-demand (not bulk pre-fetched)

- 60K HTTP requests at 1 req/s = ~17 hours
- Real-voice coverage is ~76% — bulk pre-fetch would still leave 24%
  of headwords without audio
- Cache builds organically as users click
- The TTS layer makes the overall coverage 100% without bulk Commons work

### Why Piper for the fallback (not espeak-ng / Coqui / macOS `say`)

- The task is **G2P→audio synthesis**, with quality high enough to be a
  pronunciation reference
- Piper produces near-human VITS-based neural TTS at ~50 ms/word on CPU
- ~5 KB MP3 per word means the entire fallback fits in 413 MB
- macOS `say` is decent but Mac-only and synthetic-sounding; Piper sounds
  noticeably more natural
- espeak-ng is robotic — fine for IPA generation (which we use it for!)
  but a poor pronunciation reference
- Coqui TTS is heavier (PyTorch + GPU recommended) with no clear quality
  advantage on Spanish
- Piper internally uses espeak-ng as its phonemizer — so we share the
  phonology pipeline between IPA generation and audio generation

---

## Frequency tier — OpenSubtitles list

Source: `https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/es/es_50k.txt`

(Originally planned to use SUBTLEX-ESP from UGent, but the official page
went 404 in 2026. hermitdave's list is OpenSubtitles-derived, MIT-licensed,
broadly equivalent.)

Format: one word per line, `<word> <count>`, frequency-descending.

Tier assignment (`db_es/frequency.py`):
- rank ≤ 1,000 → `top1k`
- rank ≤ 2,000 → `top2k`
- rank ≤ 5,000 → `top5k`
- rank ≤ 10,000 → `top10k`
- rank ≤ 20,000 → `top20k`
- else → `""` (no badge)

**Caveat**: the list contains *surface forms*, not lemmas. "correr",
"corro", "corres", "corrió" each take separate rank slots. So lemma
"correr" might rank lower than the verb's actual frequency suggests.
Lemmatization would fix this; out of scope for v1.

Coverage of `vox_es.db` headwords: 7,725 / 61,656 (~12.5%) get a tier,
because the dictionary is much bigger than the top-20K subtitle words
(many dictionary entries are obscure / archaic / domain-specific).

---

## Web preview

`preview_web/server.py` is a small FastAPI app:

- `GET /` → search box + 12 random headwords + an audio test box
- `GET /search?q=X` → top headword matches (LIKE prefix, length-sorted)
- `GET /entry/{headword}` → renders entry: header (POS, gender, freq
  badge, IPA, audio button, EN summary), then ES sense_groups (each with
  its own EN translation summary line), then "English meanings"
  sense_group at the bottom with full bilingual examples
- `GET /audio/{word}` → tries `commons_audio.fetch` (real human voice
  from Wikimedia Commons); on miss, falls back to `tts.lookup`
  (pre-generated Piper TTS). Returns the file with appropriate
  `audio/wav` / `audio/ogg` / `audio/mpeg` Content-Type and an
  `X-Audio-Source` header (`wikimedia-commons` or `piper-tts`) so the
  frontend can mark synthetic playback with a ✷.
- `GET /health` → DB / cache state

Run: `uvicorn preview_web.server:app --reload --port 8137`.

Templates: Jinja2 in `preview_web/templates/`. CSS in
`preview_web/static/style.css`.

---

## Known limitations / future work

- **No lemmatization** — typing `hay`, `está`, `los`, `una` 404s; only
  lemmas (`haber`, `estar`, `el`, `un`) are headwords. Out of scope for
  preview.
- **Sense alignment is POS-level, not 1-to-1** — Larousse and Oxford
  structure their senses differently. We attach EN translations grouped
  by POS instead of trying to match each ES sense to one EN sense (would
  be unreliable). The "English meanings" section at entry bottom shows
  the bilingual structure faithfully.
- **No conjugation tables** — Larousse inlines irregular forms; we don't
  extract them as a separate table.
- **Audio is mixed dialect** — Lingua Libre Spanish includes some
  Latin-American voices; we don't filter by country.
- **Frequency tier from surface forms, not lemmas** — see above.

---

## Replicating from scratch

```bash
# 1. Enable Spanish bundles in macOS Dictionary.app
#    (Settings → Dictionary → check Larousse + Gran Diccionario Oxford)

# 2. Install build-time deps
brew install espeak-ng ffmpeg
pip3 install fastapi uvicorn jinja2 lxml piper-tts

# 3. Download the frequency list (one-shot, idempotent)
bash scripts/download_es_resources.sh
#    Note: the Wiktionary dump it also downloads is now unused — can be deleted.

# 4. Download the Piper Castilian voice (~77 MB)
mkdir -p db_es/piper_voices && cd db_es/piper_voices
curl -Lo es_ES-sharvard-medium.onnx \
  https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx
curl -Lo es_ES-sharvard-medium.onnx.json \
  https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx.json
cd ../..

# 5. Build the database
python3 build_es_db.py
#    → vox_es.db (~72 MB, ~25 s)

# 6. Pre-generate TTS audio (~55 min, ~413 MB)
python3 -m db_es.tts --build
#    → audio_es_tts/*.mp3 (~60K files)

# 7. Run the preview
uvicorn preview_web.server:app --reload --port 8137
#    Open http://127.0.0.1:8137/entry/correr
```

---

## File map

```
oxford-5000-to-anki/
├── build_es_db.py              # Top-level build orchestrator
├── db_es/
│   ├── __init__.py
│   ├── schema.py               # SQLite schema, version 2
│   ├── importer.py             # Body.data binary reader, bundle discovery
│   ├── parser_mono.py          # Larousse HTML → MonoEntry
│   ├── parser_bilng.py         # Oxford bilingual HTML → BilngEntry
│   ├── ipa.py                  # espeak-ng wrapper + cache
│   ├── frequency.py            # OpenSubtitles tier loader
│   ├── commons_audio.py        # Wikimedia Commons audio fetcher
│   ├── tts.py                  # Piper TTS wrapper + bulk pre-generator
│   ├── ipa_cache.sqlite        # gitignored, regenerated
│   └── piper_voices/           # gitignored, ~77 MB ONNX + JSON
├── preview_web/
│   ├── server.py               # FastAPI app
│   ├── templates/              # entry.html, index.html, search.html, _layout.html
│   └── static/                 # style.css, audio.js
├── data_es/                    # gitignored, manual + downloaded inputs
│   ├── es_frequency_50k.txt    # OpenSubtitles list, ~660 KB
│   └── enwiktionary-...bz2     # 1.6 GB, NOW UNUSED — can delete
├── audio_es/                   # gitignored, Commons cache (real voices, on-demand)
│   ├── index.sqlite
│   └── *.wav / *.ogg / *.mp3
├── audio_es_tts/               # gitignored, Piper pre-generated MP3 (~413 MB)
│   ├── index.sqlite
│   └── *.mp3
├── scripts/
│   └── download_es_resources.sh
└── vox_es.db                   # gitignored, 72 MB build artifact
```
