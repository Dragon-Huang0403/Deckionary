"""Extract Spanish IPA pronunciations from the EN Wiktionary XML dump.

Strategy:
  - Stream the bz2-compressed dump directly with iterparse (no full
    decompression to disk; constant memory usage)
  - For each ``<page>`` in the main namespace, find the ``==Spanish==``
    section in the wikitext
  - Inside that section, capture every ``{{IPA|es|...}}`` invocation
    (and a few synonyms like ``{{IPA|es-419|...}}``)
  - Strip the slash/bracket delimiters and store the first IPA per
    headword in ``db_es/ipa_index.sqlite``

Wiktionary also has a parametrized ``{{es-IPA|word}}`` template that's
expanded server-side from a phonological algorithm — we don't try to
render those in v1. Coverage of explicit ``{{IPA|es|...}}`` is already
high for common vocabulary.

Usage:
    python -m db_es.wiktionary_ipa --build           # parse → ipa_index.sqlite
    python -m db_es.wiktionary_ipa correr casa       # lookup samples
"""

from __future__ import annotations

import argparse
import bz2
import re
import sqlite3
import sys
import time
from pathlib import Path
from xml.etree import ElementTree as ET

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DUMP = REPO_ROOT / "data_es" / "enwiktionary-latest-pages-articles.xml.bz2"
DEFAULT_INDEX = Path(__file__).resolve().parent / "ipa_index.sqlite"

# MediaWiki XML namespace; iterparse reports element tags as
# "{namespace}tag" so we strip that prefix before comparing.
_NS_RE = re.compile(r"^\{[^}]+\}")

# Match the Spanish language section. Wiki sections are delimited by
# headers of the form `== Foo ==` (level 2 = a language). We slice from
# `==Spanish==` to the next L2 header or end-of-page.
_SPANISH_SECTION_RE = re.compile(
    r"==\s*Spanish\s*==(.*?)(?=\n==[^=]|\Z)",
    re.DOTALL,
)

# Capture every {{IPA|es|...}} or {{IPA|es-XX|...}} call. The first
# pipe-delimited argument after the lang code is the IPA itself.
# Examples:
#   {{IPA|es|/koˈreɾ/}}
#   {{IPA|es|[koˈɾeɾ]|/koˈreɾ/}}
#   {{IPA|es-ES|/ˈkasa/}}
_IPA_RE = re.compile(
    r"\{\{IPA\|es(?:-[A-Za-z0-9]+)?\|([^|}]+?)(?:\|[^}]*)?\}\}",
)


def _localname(tag: str) -> str:
    return _NS_RE.sub("", tag)


def _normalize_ipa(raw: str) -> str:
    """Strip surrounding /…/ or […] and trim whitespace."""
    s = raw.strip()
    if len(s) >= 2 and s[0] in "/[" and s[-1] in "/]":
        s = s[1:-1].strip()
    return s


def _extract_ipa(spanish_section: str) -> str:
    """Return the first ``{{IPA|es|…}}`` value in the slice, or ''."""
    m = _IPA_RE.search(spanish_section)
    if not m:
        return ""
    return _normalize_ipa(m.group(1))


def iter_spanish_ipa(dump_path: Path):
    """Yield ``(headword, ipa)`` for every Spanish entry with an explicit IPA."""
    with bz2.open(dump_path, "rb") as fh:
        # Stream parse: only fire on </page> elements
        ctx = ET.iterparse(fh, events=("end",))
        for _, elem in ctx:
            if _localname(elem.tag) != "page":
                continue
            try:
                title_el = elem.find("./{*}title") or elem.find("title")
                ns_el = elem.find("./{*}ns") or elem.find("ns")
                if title_el is None or ns_el is None:
                    continue
                # Only main namespace (ns=0). Talk, User, etc. ≠ 0.
                if (ns_el.text or "").strip() != "0":
                    continue
                rev_el = elem.find("./{*}revision/{*}text") \
                       or elem.find("revision/text")
                if rev_el is None or not rev_el.text:
                    continue
                text = rev_el.text
                section_m = _SPANISH_SECTION_RE.search(text)
                if not section_m:
                    continue
                ipa = _extract_ipa(section_m.group(1))
                if ipa:
                    yield title_el.text, ipa
            finally:
                elem.clear()


def build_index(dump_path: Path = DEFAULT_DUMP,
                index_path: Path = DEFAULT_INDEX,
                progress_every: int = 100_000) -> int:
    """Stream the dump → SQLite. Returns row count written."""
    if not dump_path.exists():
        raise FileNotFoundError(f"Wiktionary dump not at {dump_path}. "
                                f"Run scripts/download_es_resources.sh first.")
    index_path.parent.mkdir(parents=True, exist_ok=True)
    if index_path.exists():
        index_path.unlink()
    db = sqlite3.connect(index_path)
    db.execute(
        "CREATE TABLE ipa (headword TEXT PRIMARY KEY, ipa TEXT NOT NULL)"
    )
    t0 = time.time()
    n_pages = 0
    n_ipa = 0
    batch: list[tuple[str, str]] = []
    last_print = t0

    for headword, ipa in iter_spanish_ipa(dump_path):
        n_ipa += 1
        batch.append((headword.lower(), ipa))
        if len(batch) >= 1000:
            db.executemany(
                "INSERT OR IGNORE INTO ipa(headword, ipa) VALUES (?, ?)", batch
            )
            batch.clear()
        # Progress: count by IPA hits (page count requires a counter we'd
        # have to maintain anyway; this is what we care about)
        if n_ipa % progress_every == 0 and time.time() - last_print > 1:
            elapsed = time.time() - t0
            print(f"  ... {n_ipa:,} IPAs / {elapsed:.0f}s "
                  f"({n_ipa / elapsed:.0f}/s)", flush=True)
            last_print = time.time()

    if batch:
        db.executemany(
            "INSERT OR IGNORE INTO ipa(headword, ipa) VALUES (?, ?)", batch
        )
    db.commit()
    inserted = db.execute("SELECT COUNT(*) FROM ipa").fetchone()[0]
    db.execute("PRAGMA optimize")
    db.close()
    print(f"Done. {inserted:,} unique Spanish IPAs in {time.time() - t0:.0f}s "
          f"-> {index_path}")
    return inserted


def lookup(headword: str, index_path: Path = DEFAULT_INDEX) -> str | None:
    if not index_path.exists():
        return None
    db = sqlite3.connect(f"file:{index_path}?mode=ro", uri=True)
    row = db.execute(
        "SELECT ipa FROM ipa WHERE headword = ?", (headword.lower(),)
    ).fetchone()
    db.close()
    return row[0] if row else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--build", action="store_true",
                   help="(re)build ipa_index.sqlite from the dump")
    p.add_argument("--dump", type=Path, default=DEFAULT_DUMP)
    p.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    p.add_argument("words", nargs="*",
                   help="lookup mode: print IPA for given words")
    args = p.parse_args()

    if args.build:
        build_index(args.dump, args.index)
        return

    if not args.words:
        sys.exit("Pass --build to build the index, or words to look up.")
    for w in args.words:
        ipa = lookup(w, args.index)
        print(f"  {w:18s} -> {ipa or '(no IPA)'}")


if __name__ == "__main__":
    main()
