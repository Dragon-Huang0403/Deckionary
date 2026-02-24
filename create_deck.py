#!/usr/bin/env python3
"""
Create an Anki deck (.apkg) from OALD10 entries.

Usage:
    python create_deck.py run              # single word
    python create_deck.py run abandon set  # multiple words
    python create_deck.py --5000           # Oxford 5000 list (oxford-5000.csv)
    python create_deck.py --all            # every word in the dictionary

Requirements:
    pip install genanki
"""

import csv
import json
import re
import struct
import sys
import zlib
from pathlib import Path

import genanki

CONTENTS = Path("oxford.dictionary/Contents").resolve()
BODY = CONTENTS / "Body.data"
INDEX_CACHE = Path(".oald10_index.json")
INCLUDE_ALL_AUDIO = False

# ── Fixed IDs (must be stable across deck rebuilds) ───────────────────────────
MODEL_ID       = 1_718_200_004  # bumped: added Verb Forms field
DECK_ID_WORDS  = 1_718_200_002
DECK_ID_IDIOMS = 1_718_200_003

# ── Index ─────────────────────────────────────────────────────────────────────

def load_index() -> dict:
    if not INDEX_CACHE.exists():
        print("Building index (one-time, ~10s)…", file=sys.stderr)
        index = {}
        with open(BODY, "rb") as f:
            data = f.read()
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
        INDEX_CACHE.write_text(json.dumps(index, ensure_ascii=False))
        print(f"Index built: {len(index)} entries.", file=sys.stderr)
    return json.loads(INDEX_CACHE.read_text())


def get_entry_html(index: dict, word: str) -> str | None:
    key = word.lower().strip()
    if key not in index:
        return None
    pos = index[key]
    with open(BODY, "rb") as f:
        f.seek(pos)
        header = f.read(12)
        sz2 = struct.unpack_from("<I", header, 4)[0]
        compressed = f.read(sz2 - 4)
    return zlib.decompress(compressed).decode("utf-8", errors="replace")


# ── HTML parsing ──────────────────────────────────────────────────────────────

def strip_tags(html: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)).strip()


def extract_span(html: str, class_name: str) -> str | None:
    """Extract the full inner content of the first <span class="{class_name}">,
    correctly handling nested <span> tags that would fool a simple regex."""
    marker = f'class="{class_name}"'
    idx = html.find(marker)
    if idx == -1:
        return None
    tag_start = html.rfind("<", 0, idx)
    content_start = html.find(">", tag_start) + 1
    depth, pos = 1, content_start
    while pos < len(html) and depth > 0:
        open_next  = html.find("<span",  pos)
        close_next = html.find("</span>", pos)
        if close_next == -1:
            break
        if open_next != -1 and open_next < close_next:
            depth += 1
            pos = open_next + 5
        else:
            depth -= 1
            if depth == 0:
                return html[content_start:close_next]
            pos = close_next + 7
    return None


def _parse_senses(html: str, media_files: set) -> list:
    """Extract a flat list of senses from any HTML fragment."""
    senses = []
    for block in re.split(r'(?=<li\s[^>]*class="sense")', html):
        if 'class="sense"' not in block:
            continue

        m = re.search(r'sensenum="(\d+)"', block)
        sense_num = int(m.group(1)) if m else None

        m = re.search(r'<span class="grammar"[^>]*>(.*?)</span>', block, re.DOTALL)
        grammar = strip_tags(m.group(1)) if m else ""

        # Labels: (North American English), (informal), [plural], etc.
        labels = re.findall(r'<span class="labels"[^>]*>(.*?)</span>', block, re.DOTALL)
        labels_text = " ".join(strip_tags(l) for l in labels)

        # Variants: (British English ladder)
        m = re.search(r'<div class="variants"[^>]*>(.*?)</div>', block, re.DOTALL)
        variants = strip_tags(m.group(1)) if m else ""

        def_inner = extract_span(block, "def")
        definition = strip_tags(def_inner) if def_inner else ""
        if not definition:
            continue

        m = re.search(r'<deft>.*?<chn>(.*?)</chn>.*?</deft>', block, re.DOTALL)
        definition_zh = strip_tags(m.group(1)) if m else ""

        examples = []
        for ex_text_html, ex_tail in re.findall(
            r'<span class="x">(.*?)</span>(.*?)</li>', block, re.DOTALL
        ):
            text = strip_tags(ex_text_html)
            if not text:
                continue
            m = re.search(r'<chn>(.*?)</chn>', ex_tail, re.DOTALL)
            text_zh = strip_tags(m.group(1)) if m else ""
            ex_audio = re.findall(r'new Audio\("([^"]+)"\)', ex_tail)
            ex_us = next((a for a in ex_audio if "_uss_" in a or "_ams_" in a), "")
            if ex_us:
                media_files.add(ex_us)
            examples.append({"text": text, "text_zh": text_zh, "audio_us": ex_us})

        senses.append({
            "sense_num": sense_num,
            "grammar": grammar,
            "labels": labels_text,
            "variants": variants,
            "definition": definition,
            "definition_zh": definition_zh,
            "examples": examples,
        })
    return senses


def _parse_pos_block(block: str, fallback_headword: str) -> dict | None:
    """Parse one <div class="entry"> block. Senses are grouped by topic (shcut-g)."""

    m = re.search(r'<h1\s[^>]*class="headword"[^>]*>([^<]+)</h1>', block)
    headword = m.group(1).strip() if m else fallback_headword

    m = re.search(r'<span class="pos"[^>]*>([^<]+)</span>', block)
    pos = m.group(1).strip() if m else ""

    m = re.search(r'class="phons_br"[^>]*>.*?<span class="phon">([^<]+)</span>', block, re.DOTALL)
    ipa_gb = m.group(1).strip() if m else ""

    m = re.search(r'class="phons_n_am"[^>]*>.*?<span class="phon">([^<]+)</span>', block, re.DOTALL)
    ipa_us = m.group(1).strip() if m else ""

    sense_start = min(
        (block.find(t) for t in ('<ol class="sense', '<li class="sense') if block.find(t) != -1),
        default=2000,
    )
    phon_section = block[:sense_start]
    all_audio = re.findall(r'new Audio\("([^"]+)"\)', phon_section)
    audio_gb = next((a for a in all_audio if re.match(r"[^_].*__gb_", a)), "")
    audio_us = next((a for a in all_audio if re.match(r"[^_].*__us_", a)), "")

    media_files = set()
    if audio_gb:
        media_files.add(audio_gb)
    if audio_us:
        media_files.add(audio_us)

    groups = []

    # Senses that appear before any shcut-g / idm-g section
    first_section = min(
        (block.find(t) for t in ('<span class="shcut-g"', '<span class="idm-g"') if block.find(t) != -1),
        default=len(block),
    )
    pre_senses = _parse_senses(block[:first_section], media_files)
    if pre_senses:
        groups.append({"topic_en": "", "topic_zh": "", "senses": pre_senses})

    # Senses grouped under a topic header (shcut-g)
    for shcut in re.findall(
        r'<span class="shcut-g".*?(?=<span class="shcut-g"|<span class="idm-g"|$)',
        block, re.DOTALL,
    ):
        topic_en, topic_zh = "", ""
        h2 = re.search(r'<h2 class="shcut"[^>]*>(.*?)</h2>', shcut, re.DOTALL)
        if h2:
            raw = h2.group(1)
            topic_en = strip_tags(re.sub(r'<shcutt>.*?</shcutt>', '', raw, flags=re.DOTALL))
            chn = re.search(r'<chn>(.*?)</chn>', raw, re.DOTALL)
            topic_zh = chn.group(1).strip() if chn else ""
        senses = _parse_senses(shcut, media_files)
        if senses:
            groups.append({"topic_en": topic_en, "topic_zh": topic_zh, "senses": senses})

    if not groups:
        return None

    verb_forms = _parse_verb_forms(block, media_files) if pos == "verb" else []

    return {
        "headword": headword,
        "pos": pos,
        "ipa_gb": ipa_gb,
        "ipa_us": ipa_us,
        "audio_gb": audio_gb,
        "audio_us": audio_us,
        "groups": groups,
        "verb_forms": verb_forms,
        "media_files": media_files,
        "card_type": "word",
    }


def _parse_idioms(block: str) -> list[dict]:
    """One dict per idiom found in a PoS block — each becomes its own card."""
    idioms = []
    for idm in re.findall(
        r'<span class="idm-g".*?(?=<span class="idm-g"|$)',
        block, re.DOTALL,
    ):
        m = re.search(r'<span class="idm"[^>]*>(.*?)</span>', idm)
        phrase = strip_tags(m.group(1)) if m else ""
        if not phrase:
            continue
        media_files = set()
        senses = _parse_senses(idm, media_files)
        if not senses:
            continue
        idioms.append({
            "headword": phrase,
            "pos": "idiom",
            "ipa_gb": "", "ipa_us": "",
            "audio_gb": "", "audio_us": "",
            "groups": [{"topic_en": "", "topic_zh": "", "senses": senses}],
            "verb_forms": [],
            "media_files": media_files,
            "card_type": "idiom",
        })
    return idioms


def _parse_verb_forms(block: str, media_files: set) -> list:
    """Extract verb conjugation rows from <table class="verb_forms_table">."""
    forms = []
    for form_attr, content in re.findall(
        r'<tr\b[^>]*\bform="([^"]+)"[^>]*>(.*?)</tr>', block, re.DOTALL
    ):
        td = re.search(r'<td\b[^>]*\bclass="verb_form"[^>]*>(.*?)</td>', content, re.DOTALL)
        label_word = strip_tags(td.group(1)) if td else ""
        m = re.search(r'class="phons_n_am".*?new Audio\("([^"]+)"\)', content, re.DOTALL)
        audio_us = m.group(1) if m else ""
        if audio_us:
            media_files.add(audio_us)
        if label_word:
            forms.append({"label_word": label_word, "audio_us": audio_us})
    return forms


def build_verb_forms_html(forms: list) -> str:
    if not forms:
        return ""
    rows = ""
    for f in forms:
        sound = f'[sound:{f["audio_us"]}]' if f["audio_us"] else ""
        rows += f'<tr><td class="vf-text">{f["label_word"]}</td><td class="vf-audio">{sound}</td></tr>'
    return f'<table class="verb-forms">{rows}</table>'


def parse_entry(html: str) -> list[dict]:
    """Return one dict per PoS block + one dict per idiom."""
    m = re.search(r'd:title="([^"]+)"', html)
    fallback = m.group(1) if m else ""

    results = []
    for block in re.split(r'(?=<div class="entry")', html):
        if 'class="entry"' not in block:
            continue
        parsed = _parse_pos_block(block, fallback)
        if parsed:
            results.append(parsed)
        results.extend(_parse_idioms(block))
    return results


# ── Card content builders ─────────────────────────────────────────────────────

def build_senses_html(groups: list) -> str:
    parts = []
    first_audio_used = False
    for group in groups:
        if group["topic_en"] or group["topic_zh"]:
            parts.append(
                f'<div class="topic">'
                f'<span class="topic-en">{group["topic_en"]}</span>'
                f'<span class="topic-zh">{group["topic_zh"]}</span>'
                f'</div>'
            )
        for s in group["senses"]:
            num = f'<span class="sense-num">{s["sense_num"]}.</span> ' if s["sense_num"] else ""
            variants = f'<span class="variants">{s["variants"]}</span> ' if s["variants"] else ""
            gram = f'<span class="grammar">{s["grammar"]}</span> ' if s["grammar"] else ""
            labs = f'<span class="labels">{s["labels"]}</span> ' if s["labels"] else ""
            defn = f'<span class="def">{s["definition"]}</span>'
            defn_zh = f'<span class="def-zh">{s["definition_zh"]}</span>' if s["definition_zh"] else ""

            examples_html = ""
            for ex in s["examples"]:
                if (ex["audio_us"] and not first_audio_used) or INCLUDE_ALL_AUDIO:
                    sound_us = f'[sound:{ex["audio_us"]}]'
                    first_audio_used = True
                else:
                    sound_us = ""
                ex_zh = f'<span class="ex-zh">{ex["text_zh"]}</span>' if ex["text_zh"] else ""
                examples_html += f"""
            <li class="example">
              <span class="ex-text">{ex["text"]}</span>
              {ex_zh}
              <span class="ex-audio">{sound_us}</span>
            </li>"""

            ex_block = f'<ul class="examples">{examples_html}</ul>' if examples_html else ""
            parts.append(f"""
        <div class="sense">
          <div class="sense-head">{num}{variants}{gram}{labs}{defn} {defn_zh}</div>
          {ex_block}
        </div>""")

    return "\n".join(parts)


# ── Anki model ────────────────────────────────────────────────────────────────

CARD_CSS = """
/* ── Design tokens ───────────────────────────────────────── */
:root {
  --bg:          #ffffff;
  --text:        #1a1a1a;
  --text-soft:   #555555;
  --text-muted:  #888888;
  --accent:      #0057a8;
  --accent-soft: #3a7fc1;
  --topic:       #b85c00;
  --chinese:     #aaaaaa;
  --border:      #e0e0e0;
  --ex-text:     #333333;
}

/* Dark mode — Anki desktop (.night_mode), AnkiDroid (.nightMode),
   and system preference as fallback */
.night_mode, .nightMode {
  --bg:          #1e1e1e;
  --text:        #dde1e7;
  --text-soft:   #aaaaaa;
  --text-muted:  #777777;
  --accent:      #6ab0f5;
  --accent-soft: #89c4ff;
  --topic:       #e8935a;
  --chinese:     #666666;
  --border:      #3a3a3a;
  --ex-text:     #c8cdd4;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg:          #1e1e1e;
    --text:        #dde1e7;
    --text-soft:   #aaaaaa;
    --text-muted:  #777777;
    --accent:      #6ab0f5;
    --accent-soft: #89c4ff;
    --topic:       #e8935a;
    --chinese:     #666666;
    --border:      #3a3a3a;
    --ex-text:     #c8cdd4;
  }
}

/* ── Layout ──────────────────────────────────────────────── */
.card {
  font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
  font-size: 16px;
  color: var(--text);
  background: var(--bg);
  max-width: 680px;
  margin: 0 auto;
  padding: 16px;
  text-align: left;
}

/* ── Front ───────────────────────────────────────────────── */
.headword { font-size: 2em; font-weight: 700; color: var(--accent); }
.pos      { font-size: 0.85em; color: var(--text-muted); margin-left: 6px; font-style: italic; }

/* ── Phonetics ───────────────────────────────────────────── */
.phonetics { font-size: 0.95em; color: var(--text-soft); margin: 6px 0 12px; }
.ipa       { font-family: monospace; }
.dialect   { color: var(--text-muted); font-size: 0.8em; }

/* ── Topic headers ───────────────────────────────────────── */
.topic    { margin: 14px 0 4px; padding-bottom: 3px; border-bottom: 1px solid var(--border); }
.topic-en { font-weight: 600; color: var(--topic); font-style: italic; }
.topic-zh { color: var(--chinese); font-size: 0.8em; margin-left: 6px; }

/* ── Senses ──────────────────────────────────────────────── */
.senses    { margin-top: 12px; }
.sense     { margin-bottom: 14px; }
.sense-num { font-weight: 700; color: var(--accent); }
.grammar   { color: var(--text-soft); font-size: 0.85em; }
.labels    { color: var(--text-muted); font-size: 0.85em; font-style: italic; }
.variants  { color: var(--accent-soft); font-size: 0.85em; font-weight: 600; }
.def-zh    { color: var(--chinese); font-size: 0.8em; margin-left: 6px; }

/* ── Examples ────────────────────────────────────────────── */
.examples { margin: 6px 0 0 16px; padding: 0; list-style: disc; }
.example  { margin: 5px 0; }
.ex-text  { color: var(--ex-text); }
.ex-zh    { color: var(--chinese); font-size: 0.8em; display: block; margin-left: 4px; }
.ex-audio { font-size: 0.8em; color: var(--text-muted); }

/* ── Verb forms ──────────────────────────────────────────── */
.verb-forms { margin-top: 12px; border-collapse: collapse; width: 100%; font-size: 0.9em; }
.verb-forms td { padding: 3px 8px; color: var(--text); }
.vf-audio { color: var(--text-muted); }

hr { border: none; border-top: 1px solid var(--border); margin: 14px 0; }
"""

FRONT_TMPL = """
<div class="headword">{{Word}}</div>
<span class="pos">{{PoS}}</span>
<hr>
<div class="phonetics">
  <span class="dialect">GB</span> <span class="ipa">{{IPA GB}}</span>
  &nbsp;&nbsp;
  <span class="dialect">US</span> <span class="ipa">{{IPA US}}</span>
  &nbsp; {{Audio Word US}}
</div>
{{#Verb Forms}}<div class="verb-forms-section">{{Verb Forms}}</div>{{/Verb Forms}}
"""

BACK_TMPL = """
<div class="headword">{{Word}}</div>
<span class="pos">{{PoS}}</span>
<hr>
<div class="senses">{{Senses}}</div>
"""

OALD_MODEL = genanki.Model(
    MODEL_ID,
    "OALD10",
    fields=[
        {"name": "Word"},
        {"name": "PoS"},
        {"name": "IPA GB"},
        {"name": "IPA US"},
        {"name": "Audio Word GB"},
        {"name": "Audio Word US"},
        {"name": "Verb Forms"},
        {"name": "Senses"},
    ],
    templates=[{"name": "Card 1", "qfmt": FRONT_TMPL, "afmt": BACK_TMPL}],
    css=CARD_CSS,
)


# ── Main ──────────────────────────────────────────────────────────────────────

def make_note(entry: dict) -> genanki.Note:
    return genanki.Note(
        model=OALD_MODEL,
        fields=[
            entry["headword"],
            entry["pos"],
            entry["ipa_gb"],
            entry["ipa_us"],
            f'[sound:{entry["audio_gb"]}]' if entry["audio_gb"] else "",
            f'[sound:{entry["audio_us"]}]' if entry["audio_us"] else "",
            build_verb_forms_html(entry.get("verb_forms", [])),
            build_senses_html(entry["groups"]),
        ],
    )


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    index = load_index()

    if args == ["--all"]:
        words = list(index.keys())
    elif args == ["--5000"]:
        csv_path = Path("oxford-5000.csv")
        if not csv_path.exists():
            print("oxford-5000.csv not found.", file=sys.stderr)
            sys.exit(1)
        with open(csv_path, encoding="utf-8") as f:
            words = list(dict.fromkeys(row["word"].strip().lower() for row in csv.DictReader(f)))
    else:
        words = [w.lower() for w in args]

    word_deck  = genanki.Deck(DECK_ID_WORDS,  "OALD10::5000")
    idiom_deck = genanki.Deck(DECK_ID_IDIOMS, "OALD10::5000-Idioms")
    word_media: set[Path]  = set()
    idiom_media: set[Path] = set()
    missing = []

    for word in words:
        html = get_entry_html(index, word)
        if html is None:
            print(f'  skipped (not found): {word}', file=sys.stderr)
            missing.append(word)
            continue

        entries = parse_entry(html)
        for entry in entries:
            note = make_note(entry)
            used = set(re.findall(r'\[sound:([^\]]+)\]', " ".join(note.fields)))
            media_paths = {CONTENTS / f for f in entry["media_files"] if f in used and (CONTENTS / f).exists()}
            if entry["card_type"] == "idiom":
                idiom_deck.add_note(note)
                idiom_media |= media_paths
            else:
                word_deck.add_note(note)
                word_media |= media_paths

        label = entries[0]["headword"] if entries else word
        word_cards  = [e for e in entries if e["card_type"] == "word"]
        idiom_cards = [e for e in entries if e["card_type"] == "idiom"]
        pos_list = ", ".join(e["pos"] for e in word_cards if e["pos"])
        print(
            f"  added: {label} ({pos_list}) — "
            f"{len(word_cards)} word card(s), {len(idiom_cards)} idiom card(s)",
            file=sys.stderr,
        )

    if not word_deck.notes and not idiom_deck.notes:
        print("No notes created.", file=sys.stderr)
        sys.exit(1)

    all_media = word_media | idiom_media
    pkg = genanki.Package([word_deck, idiom_deck])
    pkg.media_files = [str(p) for p in all_media]
    pkg.write_to_file("oald10.apkg")

    print(file=sys.stderr)
    print(f"  Saved → oald10.apkg", file=sys.stderr)
    print(f"    OALD10:        {len(word_deck.notes)} notes", file=sys.stderr)
    print(f"    OALD10 Idioms: {len(idiom_deck.notes)} notes", file=sys.stderr)
    print(f"    Audio files:   {len(all_media)}", file=sys.stderr)
    if missing:
        print(f"  Not found: {', '.join(missing)}", file=sys.stderr)


if __name__ == "__main__":
    main()
