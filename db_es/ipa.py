"""Castilian Spanish IPA — thin wrapper around espeak-ng.

Why espeak-ng instead of a hand-rolled phonology generator: a previous
audit (vs Wiktionary's `Module:es-pronunc`) showed that a 200-line
ruleset reaches only ~60% exact match because Spanish has enough
edge cases (hiatus on accented weak vowels, lexical /x/-spellings like
"México", final-d dialect choice, n→ŋ before velars, s→z before voiced
consonants, ...) that an algorithmic implementation either becomes a
giant ruleset or gets things wrong.

espeak-ng is a mature open-source TTS engine with comprehensive Spanish
phonology. We use it as a build-time tool only (the resulting IPA strings
get baked into vox_es.db; the app itself doesn't need espeak-ng installed).

Usage:
    # Build-time pre-warm: batch espeak-ng once for the whole corpus
    ipa.precompute(all_headwords)

    # Per-word lookup: pure SQLite cache hit, no subprocess spawn
    ipa.to_ipa("correr")  # -> '[korˈeɾ]'

The cache lives at db_es/ipa_cache.sqlite (gitignored, regenerable).
"""

from __future__ import annotations

import shutil
import sqlite3
import subprocess
from pathlib import Path

CACHE_DB = Path(__file__).resolve().parent / "ipa_cache.sqlite"
ESPEAK_VOICE = "es"  # Castilian; "es-419" for Latin America


def _have_espeak() -> bool:
    return shutil.which("espeak-ng") is not None


def _ensure_cache() -> sqlite3.Connection:
    db = sqlite3.connect(CACHE_DB)
    db.execute(
        "CREATE TABLE IF NOT EXISTS ipa "
        "(word TEXT PRIMARY KEY, ipa TEXT NOT NULL)"
    )
    db.commit()
    return db


def _espeak_batch(words: list[str]) -> list[str]:
    """Pipe ``words`` (one per line) into espeak-ng; return IPAs in same order.

    espeak-ng emits one IPA per input line on stdout. Empty lines or
    failed conversions become empty strings.
    """
    if not words:
        return []
    input_text = "\n".join(words).encode("utf-8")
    try:
        result = subprocess.run(
            ["espeak-ng", "-v", ESPEAK_VOICE, "--ipa", "-q"],
            input=input_text,
            capture_output=True,
            timeout=180,
            check=True,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return [""] * len(words)
    lines = result.stdout.decode("utf-8", errors="replace").splitlines()
    # Pad/truncate to align with input length
    if len(lines) < len(words):
        lines += [""] * (len(words) - len(lines))
    return [l.strip() for l in lines[: len(words)]]


def precompute(words, batch_size: int = 5000) -> int:
    """Populate the cache for ``words`` (idempotent — skips already-cached).

    Returns the number of new entries added. Run once at build start so the
    rest of the build can hit cache only.
    """
    if not _have_espeak():
        return 0
    db = _ensure_cache()
    seen = {row[0] for row in db.execute("SELECT word FROM ipa")}
    pending: list[str] = []
    pending_seen: set[str] = set()
    for w in words:
        key = w.strip().lower()
        if not key or key in seen or key in pending_seen:
            continue
        pending.append(w.strip())
        pending_seen.add(key)
    if not pending:
        db.close()
        return 0

    n_added = 0
    for i in range(0, len(pending), batch_size):
        batch = pending[i : i + batch_size]
        ipas = _espeak_batch(batch)
        rows = [(w.lower(), ipa) for w, ipa in zip(batch, ipas) if ipa]
        if rows:
            db.executemany(
                "INSERT OR REPLACE INTO ipa(word, ipa) VALUES (?, ?)", rows
            )
            db.commit()
            n_added += len(rows)
    db.close()
    return n_added


def to_ipa(word: str, *, brackets: bool = True) -> str:
    """Return Castilian IPA for ``word`` (cached lookup; spawns espeak-ng
    only on miss). Empty string if espeak-ng isn't installed or fails.
    """
    if not word:
        return ""
    key = word.strip().lower()
    if not key:
        return ""
    db = _ensure_cache()
    row = db.execute("SELECT ipa FROM ipa WHERE word = ?", (key,)).fetchone()
    db.close()
    if row is not None:
        ipa = row[0]
    else:
        if not _have_espeak():
            return ""
        ipas = _espeak_batch([word.strip()])
        ipa = ipas[0] if ipas else ""
        if ipa:
            db = _ensure_cache()
            db.execute(
                "INSERT OR REPLACE INTO ipa(word, ipa) VALUES (?, ?)",
                (key, ipa),
            )
            db.commit()
            db.close()
    if not ipa:
        return ""
    return f"[{ipa}]" if brackets else ipa


if __name__ == "__main__":
    import sys
    if not _have_espeak():
        sys.exit("espeak-ng not on PATH. Install with: brew install espeak-ng")
    words = sys.argv[1:] or [
        "correr", "casa", "tiempo", "ser", "hablar", "rojo", "perro",
        "zapato", "cinco", "ñoño", "guerra", "pingüino", "México",
        "español", "habilitación",
        # Cases the previous rules-based generator got wrong:
        "país", "bahía", "búho", "río", "oír", "prohíbe", "mismo",
        "verdad", "Madrid",
    ]
    for w in words:
        print(f"  {w:18s} -> {to_ipa(w)}")
