#!/usr/bin/env python3
"""Build the Spanish dictionary SQLite (vox_es.db).

Pipeline:
  1. Open both macOS-bundled dictionaries (Larousse mono + Oxford ES-EN).
  2. Use the monolingual headword set as the canonical Spanish vocabulary.
     For each headword, parse the mono entry to get ES senses + examples.
  3. Look up the same headword in the bilingual bundle (filtering ES→EN
     entries only). Parse it to get EN translations per sense + bilingual
     examples + idioms.
  4. Merge: mono is the primary structure; bilingual fills `definition_en`
     and contributes its bilingual example pairs (which have EN translations,
     much more useful to learners than mono's untranslated ones).
  5. Write into vox_es.db using the schema from db_es.schema.

Usage:
    python build_es_db.py                         # full build
    python build_es_db.py -o /tmp/preview.db
    python build_es_db.py --sample correr,casa,tiempo --verbose
    python build_es_db.py --limit 1000            # first 1000 ES lemmas
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
import time
from pathlib import Path

from db_es import frequency, ipa as ipa_gen
from db_es.importer import BodyDataReader, find_dictionary_bundles
from db_es.parser_bilng import BilngEntry, BilngExample, BilngSense
from db_es.parser_bilng import parse_entry as parse_bilng
from db_es.parser_mono import MonoEntry, parse_entry as parse_mono
from db_es.schema import create_schema


# Maps Larousse's ES POS strings to the closest Oxford ES-EN equivalent.
# Used to attach EN translations to each mono sense_group as a summary
# gloss line — true sense-by-sense alignment between the two dictionaries
# is unreliable, but POS-level alignment is robust.
ES_TO_EN_POS: dict[str, list[str]] = {
    "verbo intransitivo": ["intransitive verb"],
    "verbo transitivo": ["transitive verb"],
    "verbo pronominal": ["pronominal verb"],
    "verbo copulativo": ["copular verb"],
    "verbo auxiliar": ["auxiliary verb"],
    "verbo impersonal": ["impersonal verb"],
    "verbo intransitivo y transitivo": ["intransitive verb", "transitive verb"],
    "nombre femenino": ["feminine noun"],
    "nombre masculino": ["masculine noun"],
    "nombre común": ["masculine and feminine noun", "noun"],
    "nombre masculino y femenino": ["masculine and feminine noun"],
    "nombre masculino plural": ["masculine plural noun"],
    "nombre femenino plural": ["feminine plural noun"],
    "adjetivo": ["adjective"],
    "adjetivo y nombre": ["adjective"],
    "adverbio": ["adverb"],
    "preposición": ["preposition"],
    "conjunción": ["conjunction"],
    "pronombre": ["pronoun"],
    "pronombre personal": ["personal pronoun"],
    "pronombre relativo": ["relative pronoun"],
    "pronombre demostrativo": ["demonstrative pronoun"],
    "pronombre posesivo": ["possessive pronoun"],
    "pronombre interrogativo": ["interrogative pronoun"],
    "pronombre exclamativo": ["exclamative pronoun"],
    "interjección": ["interjection"],
    "determinante": ["determiner"],
    "determinante artículo": ["definite article"],
    "artículo": ["definite article", "indefinite article"],
}


def _split_es_pos(topic: str) -> list[str]:
    """Larousse may join multiple POSes with ', ' or '; '. Split into parts."""
    parts: list[str] = []
    for chunk in topic.replace(";", ",").split(","):
        c = chunk.strip()
        if c:
            parts.append(c)
    return parts


def _topic_en_for(es_topic: str, bilng_senses: list[BilngSense]) -> str:
    """Collect unique EN translations from bilingual senses whose POS matches
    `es_topic`. Returns up to ~12 translations joined with '; '."""
    if not bilng_senses:
        return ""
    wanted_en_pos: set[str] = set()
    for es_p in _split_es_pos(es_topic):
        for en_p in ES_TO_EN_POS.get(es_p, []):
            wanted_en_pos.add(en_p)
    if not wanted_en_pos:
        return ""
    seen: set[str] = set()
    out: list[str] = []
    for bs in bilng_senses:
        if bs.pos not in wanted_en_pos or not bs.translation:
            continue
        for trans in bs.translation.split(" / "):
            t = trans.strip().rstrip(",;:.")
            if t and t.lower() not in seen:
                seen.add(t.lower())
                out.append(t)
        if len(out) >= 12:
            break
    return "; ".join(out)


def _get_bilng_entry(bilng_reader: BodyDataReader, headword: str) -> BilngEntry | None:
    """Return the first ES→EN bilingual entry for `headword`, or None."""
    for html in bilng_reader.get_all_html(headword):
        result = parse_bilng(html)
        if result is not None:
            return result
    return None


def _insert_entry(
    db: sqlite3.Connection,
    source_id: int,
    mono: MonoEntry,
    bilng: BilngEntry | None,
    entry_index: int,
    ipa: str = "",
    frequency_tier: str = "",
) -> int:
    """Insert one merged entry. Returns the new entries.id.

    `ipa` is supplied by the build orchestrator (sourced from the Wiktionary
    index since Larousse omits it). `frequency_tier` comes from the
    OpenSubtitles ES frequency list.
    """
    cur = db.execute(
        """INSERT INTO entries
              (source_id, headword, pos, gender, entry_index, ipa,
               frequency_tier)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (source_id, mono.headword, mono.pos, mono.gender, entry_index,
         ipa or mono.ipa, frequency_tier),
    )
    entry_id = cur.lastrowid

    # 1) Mono sense_groups → ES sense structure. Each sense_group gets a
    #    `topic_en` summary listing the bilingual translations for the same
    #    POS (true per-sense alignment isn't reliable across dictionaries).
    bilng_senses = bilng.senses if bilng else []
    sg_order = 0
    for sg in mono.sense_groups:
        topic_en = _topic_en_for(sg.topic, bilng_senses)
        sg_cur = db.execute(
            """INSERT INTO sense_groups (entry_id, topic, topic_en, sort_order)
               VALUES (?, ?, ?, ?)""",
            (entry_id, sg.topic, topic_en, sg_order),
        )
        sg_id = sg_cur.lastrowid
        sg_order += 1

        for s_order, sense in enumerate(sg.senses):
            sense_num = None
            if sense.sense_num.strip():
                try:
                    sense_num = int(sense.sense_num.strip())
                except ValueError:
                    sense_num = None
            sense_cur = db.execute(
                """INSERT INTO senses
                      (sense_group_id, entry_id, sense_num, grammar, labels,
                       variants, definition, definition_en, sort_order)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (sg_id, entry_id, sense_num, sense.grammar, sense.labels,
                 "", sense.definition, "", s_order),
            )
            sense_id = sense_cur.lastrowid
            for ex_order, ex in enumerate(sense.examples):
                if ex.text_plain:
                    db.execute(
                        """INSERT INTO examples
                              (sense_id, text_plain, text_html, text_en, sort_order)
                           VALUES (?, ?, ?, '', ?)""",
                        (sense_id, ex.text_plain, ex.text_html, ex_order),
                    )

    # 2) Bilingual entry → separate sense_group "English meanings" with each
    #    bilingual sense as a child sense (with `definition_en` populated and
    #    bilingual examples carrying their EN translations).
    if bilng and bilng.senses:
        sg_cur = db.execute(
            """INSERT INTO sense_groups (entry_id, topic, topic_en, sort_order)
               VALUES (?, ?, ?, ?)""",
            (entry_id, "English meanings", bilng.pos, sg_order),
        )
        en_sg_id = sg_cur.lastrowid
        sg_order += 1

        for s_order, bs in enumerate(bilng.senses):
            label_parts = [
                bs.sense_path, bs.field_label, bs.context, bs.indicator,
            ]
            labels = " · ".join(p for p in label_parts if p)
            sense_cur = db.execute(
                """INSERT INTO senses
                      (sense_group_id, entry_id, sense_num, grammar, labels,
                       variants, definition, definition_en, sort_order)
                   VALUES (?, ?, NULL, ?, ?, '', ?, '', ?)""",
                (en_sg_id, entry_id, bs.pos, labels,
                 bs.translation or "—", s_order),
            )
            en_sense_id = sense_cur.lastrowid
            for ex_order, ex in enumerate(bs.examples):
                if ex.text_es:
                    db.execute(
                        """INSERT INTO examples
                              (sense_id, text_plain, text_html, text_en, sort_order)
                           VALUES (?, ?, '', ?, ?)""",
                        (en_sense_id, ex.text_es, ex.text_en, ex_order),
                    )

    # Phrases: mono has phrase headwords; bilingual idioms have ES + EN.
    # Use bilingual phrases when overlap, else use mono.
    bilng_idiom_map = {idm.text_es.lower(): idm for idm in (bilng.idioms if bilng else [])}
    phrases_inserted: set[str] = set()
    for ph_order, phrase in enumerate(mono.phrases):
        key = phrase.lower()
        if key in phrases_inserted:
            continue
        phrases_inserted.add(key)
        db.execute(
            "INSERT INTO phrases (entry_id, phrase, sort_order) VALUES (?, ?, ?)",
            (entry_id, phrase, ph_order),
        )
    if bilng:
        for idm in bilng.idioms:
            key = idm.text_es.lower()
            if key in phrases_inserted:
                continue
            phrases_inserted.add(key)
            db.execute(
                "INSERT INTO phrases (entry_id, phrase, sort_order) VALUES (?, ?, ?)",
                (entry_id, idm.text_es, len(phrases_inserted)),
            )

    if mono.etymology:
        db.execute(
            """INSERT OR REPLACE INTO word_origins (entry_id, text_plain, text_html)
               VALUES (?, ?, '')""",
            (entry_id, mono.etymology),
        )

    return entry_id


def _populate_dictionary_fts(db: sqlite3.Connection) -> None:
    """Build the dictionary_fts virtual table from inserted rows."""
    db.execute("DELETE FROM dictionary_fts")
    rows = db.execute(
        """
        SELECT
            e.id,
            e.headword,
            COALESCE(GROUP_CONCAT(s.definition, ' '), ''),
            COALESCE(GROUP_CONCAT(x.text_plain, ' '), ''),
            COALESCE(GROUP_CONCAT(s.definition_en, ' '), '')
        FROM entries e
        LEFT JOIN senses s ON s.entry_id = e.id
        LEFT JOIN examples x ON x.sense_id = s.id
        GROUP BY e.id
        """
    ).fetchall()
    db.executemany(
        "INSERT INTO dictionary_fts(rowid, headword, definitions, examples, glosses_en) "
        "VALUES (?, ?, ?, ?, ?)",
        rows,
    )


def build(
    output: Path,
    sample: list[str] | None = None,
    limit: int | None = None,
    verbose: bool = False,
    skip_ipa: bool = False,
    skip_frequency: bool = False,
) -> None:
    bundles = find_dictionary_bundles()
    if "Spanish" not in bundles:
        sys.exit("Error: 'Spanish' (Larousse) bundle not installed. "
                 "Enable in Dictionary.app → Settings → Dictionary.")
    if "Spanish - English" not in bundles:
        sys.exit("Error: 'Spanish - English' (Oxford) bundle not installed. "
                 "Enable in Dictionary.app → Settings → Dictionary.")

    print(f"Loading Larousse mono   from {bundles['Spanish']}")
    mono_reader = BodyDataReader(bundles["Spanish"])
    print(f"Loading Oxford ES-EN    from {bundles['Spanish - English']}")
    bilng_reader = BodyDataReader(bundles["Spanish - English"])

    print(f"  mono headwords:  {mono_reader.unique_headword_count():,}")
    print(f"  bilng headwords: {bilng_reader.unique_headword_count():,}")

    # Side data:
    #   - IPA: rules-based Castilian generator (no external file needed)
    #   - Frequency tier: OpenSubtitles ES list
    if not skip_ipa:
        print("  IPA generator:   Castilian rules-based "
              "(db_es.ipa.to_ipa)")

    tier_map: dict[str, str] = {}
    if not skip_frequency:
        tier_map = frequency.load_tier_map()
        if tier_map:
            print(f"  Frequency tiers: {len(tier_map):,} words tiered")
        else:
            print(f"  Frequency tiers: (file not at "
                  f"{frequency.DEFAULT_FREQ_FILE} — skipping)")

    if output.exists():
        output.unlink()
    db = sqlite3.connect(output)
    create_schema(db)
    cur = db.execute(
        "INSERT INTO sources (name, version) VALUES (?, ?)",
        ("Larousse + Oxford ES-EN (preview)", "1"),
    )
    source_id = cur.lastrowid
    db.commit()

    if sample:
        targets = sample
    else:
        targets = mono_reader.headwords()
        if limit:
            targets = targets[:limit]

    t0 = time.time()
    n_with_bilng = 0
    n_with_ipa = 0
    n_with_tier = 0
    n_total = 0

    def _generate_ipa(word: str) -> str:
        if skip_ipa:
            return ""
        try:
            # Store raw IPA without brackets — the template owns the
            # formatting (matches OALD10's convention).
            return ipa_gen.to_ipa(word, brackets=False)
        except Exception:
            return ""

    for entry_index, headword in enumerate(targets):
        ipa = _generate_ipa(headword)
        tier = tier_map.get(headword.lower(), "")
        if ipa:
            n_with_ipa += 1
        if tier:
            n_with_tier += 1
        for mono_html in mono_reader.get_all_html(headword):
            try:
                mono = parse_mono(mono_html)
            except Exception as e:
                if verbose:
                    print(f"  ! mono parse failed for {headword!r}: {e}")
                continue
            bilng = _get_bilng_entry(bilng_reader, headword)
            if bilng:
                n_with_bilng += 1
            try:
                _insert_entry(db, source_id, mono, bilng, entry_index,
                              ipa=ipa, frequency_tier=tier)
                n_total += 1
            except Exception as e:
                if verbose:
                    print(f"  ! insert failed for {headword!r}: {e}")
                continue

            if verbose:
                tag = "✓" if bilng else "·"
                ipa_tag = ipa or "-"
                tier_tag = tier or "-"
                print(f"  {tag} {headword:30s} sg={len(mono.sense_groups)} "
                      f"se={sum(len(g.senses) for g in mono.sense_groups)}"
                      f" ph={len(mono.phrases)}"
                      f" en={len(bilng.senses) if bilng else 0}"
                      f" ipa={ipa_tag} tier={tier_tag}")

        if not verbose and entry_index and entry_index % 1000 == 0:
            print(f"  ... {entry_index:,}/{len(targets):,} "
                  f"({entry_index / (time.time() - t0):.0f}/s)")

        if entry_index % 500 == 0:
            db.commit()

    db.commit()
    print(
        f"\nInserted {n_total:,} entries — "
        f"{n_with_bilng:,} with bilingual gloss, "
        f"{n_with_ipa:,} with IPA, "
        f"{n_with_tier:,} with frequency tier. "
        f"{time.time() - t0:.1f}s elapsed."
    )

    print("Building dictionary_fts ...")
    _populate_dictionary_fts(db)
    db.commit()
    db.execute("PRAGMA optimize")
    db.close()

    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"Done. {output} → {size_mb:.1f} MB")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-o", "--output", default="vox_es.db", type=Path)
    p.add_argument("--sample", help="comma-separated test words (skips full build)")
    p.add_argument("--limit", type=int, help="only build first N headwords")
    p.add_argument("--verbose", action="store_true")
    p.add_argument("--skip-ipa", action="store_true",
                   help="don't read db_es/ipa_index.sqlite (entries get empty IPA)")
    p.add_argument("--skip-frequency", action="store_true",
                   help="don't load es_frequency_50k.txt (entries get empty tier)")
    args = p.parse_args()
    sample = args.sample.split(",") if args.sample else None
    build(args.output, sample=sample, limit=args.limit, verbose=args.verbose,
          skip_ipa=args.skip_ipa, skip_frequency=args.skip_frequency)


if __name__ == "__main__":
    main()
