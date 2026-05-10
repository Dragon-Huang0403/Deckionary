"""Pre-generated Piper TTS audio fallback for the Spanish dictionary.

Two-tier audio strategy: prefer human recordings from Wikimedia Commons
(see ``commons_audio.py``); when Commons has nothing, fall back to a
neural TTS file generated here.

This module is the build-time generator + runtime lookup helper. It does
*not* synthesize on demand from the web server — that path stays cache-only
to keep latency predictable.

Voice: ``es_ES-sharvard-medium`` (Apache 2.0). Castilian Spanish, neural
VITS via Piper. Output: MP3 via ffmpeg, ~3–5 KB per word.

Usage (build time):
    python -m db_es.tts --build              # all 61K headwords from vox_es.db
    python -m db_es.tts --build --limit 100  # smoke-test
    python -m db_es.tts correr casa          # ad-hoc synthesis

Usage (server runtime):
    from db_es import tts
    path = tts.lookup("correr")              # pure cache lookup, no synth
"""

from __future__ import annotations

import argparse
import io
import re
import sqlite3
import subprocess
import sys
import time
import wave
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]
TTS_DIR = REPO_ROOT / "audio_es_tts"
INDEX_DB = TTS_DIR / "index.sqlite"
VOICE_PATH = Path(__file__).resolve().parent / "piper_voices" / "es_ES-sharvard-medium.onnx"

_SAFE_RE = re.compile(r"[^a-z0-9áéíóúñü_-]+", re.IGNORECASE)


def _safe_name(word: str) -> str:
    """Same convention as commons_audio._safe_name()."""
    s = _SAFE_RE.sub("_", word.lower()).strip("_")
    return s


def _ensure_dir() -> sqlite3.Connection:
    TTS_DIR.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(INDEX_DB)
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS cache (
            word         TEXT PRIMARY KEY,
            file         TEXT NOT NULL,
            generated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        """
    )
    db.commit()
    return db


def _load_voice():
    if not VOICE_PATH.exists():
        raise FileNotFoundError(
            f"Piper voice not at {VOICE_PATH}. "
            f"Download with:\n"
            f"  curl -Lo {VOICE_PATH} "
            f"https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/"
            f"es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx\n"
            f"  curl -Lo {VOICE_PATH}.json "
            f"https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/"
            f"es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx.json"
        )
    from piper import PiperVoice
    return PiperVoice.load(str(VOICE_PATH))


def _wav_bytes(voice, text: str) -> bytes:
    """Run Piper synthesis; return the raw WAV bytes."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:
        voice.synthesize_wav(text, wav)
    return buf.getvalue()


def _wav_to_mp3(wav_bytes: bytes, out_path: Path) -> None:
    """Pipe WAV bytes through ffmpeg → MP3 file. Raises if ffmpeg fails."""
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "wav", "-i", "pipe:0",
            "-codec:a", "libmp3lame", "-q:a", "5",
            str(out_path),
        ],
        input=wav_bytes,
        check=True,
        capture_output=True,
    )


def lookup(word: str) -> Path | None:
    """Pure cache lookup — never synthesizes. Used by the web server."""
    safe = _safe_name(word)
    if not safe:
        return None
    if not INDEX_DB.exists():
        # Fall back to file-system probe so the server still works in
        # partial-build states.
        candidate = TTS_DIR / f"{safe}.mp3"
        return candidate if candidate.exists() else None
    db = sqlite3.connect(f"file:{INDEX_DB}?mode=ro", uri=True)
    row = db.execute(
        "SELECT file FROM cache WHERE word = ?", (word.lower(),)
    ).fetchone()
    db.close()
    if not row:
        return None
    path = TTS_DIR / row[0]
    return path if path.exists() else None


def synthesize(word: str, *, voice=None, db: sqlite3.Connection | None = None) -> Path | None:
    """Synthesize ``word`` (idempotent). Returns the path or None on skip.

    ``voice`` and ``db`` are optional pre-loaded handles for batch use.
    """
    safe = _safe_name(word)
    if not safe:
        return None
    out_path = TTS_DIR / f"{safe}.mp3"
    own_db = db is None
    if own_db:
        db = _ensure_dir()
    try:
        existing = db.execute(
            "SELECT file FROM cache WHERE word = ?", (word.lower(),)
        ).fetchone()
        if existing and (TTS_DIR / existing[0]).exists():
            return TTS_DIR / existing[0]

        if voice is None:
            voice = _load_voice()
        wav_bytes = _wav_bytes(voice, word)
        _wav_to_mp3(wav_bytes, out_path)

        db.execute(
            "INSERT OR REPLACE INTO cache(word, file) VALUES (?, ?)",
            (word.lower(), out_path.name),
        )
        db.commit()
        return out_path
    finally:
        if own_db:
            db.close()


def precompute(words: Iterable[str], *, progress_every: int = 500) -> int:
    """Bulk-synthesize ``words`` (skip already-cached). Returns count added."""
    voice = _load_voice()
    db = _ensure_dir()
    cached = {row[0] for row in db.execute("SELECT word FROM cache")}

    # Materialize first so the summary print can report total inputs
    # accurately even if `words` is a generator.
    all_inputs = list(words)
    n_inputs = len(all_inputs)

    pending: list[str] = []
    pending_seen: set[str] = set()
    n_already_cached = 0
    n_skipped_invalid = 0
    for w in all_inputs:
        key = w.strip().lower()
        if not key or key in pending_seen:
            continue
        if key in cached:
            pending_seen.add(key)
            n_already_cached += 1
            continue
        if not _safe_name(key):
            pending_seen.add(key)
            n_skipped_invalid += 1
            continue
        pending.append(w.strip())
        pending_seen.add(key)

    if not pending:
        db.close()
        return 0

    n_added = 0
    n_failed = 0
    t0 = time.time()
    for i, word in enumerate(pending, 1):
        try:
            wav_bytes = _wav_bytes(voice, word)
            out_path = TTS_DIR / f"{_safe_name(word)}.mp3"
            _wav_to_mp3(wav_bytes, out_path)
            db.execute(
                "INSERT OR REPLACE INTO cache(word, file) VALUES (?, ?)",
                (word.lower(), out_path.name),
            )
            n_added += 1
            if n_added % 50 == 0:
                db.commit()
        except Exception as e:
            n_failed += 1
            if n_failed <= 5:
                print(f"  ! failed on {word!r}: {e}", file=sys.stderr)
        if i % progress_every == 0:
            elapsed = time.time() - t0
            rate = i / elapsed if elapsed > 0 else 0
            remaining = (len(pending) - i) / rate if rate > 0 else 0
            print(
                f"  ... {i:,}/{len(pending):,} "
                f"({rate:.0f}/s, ~{remaining/60:.0f} min remaining)",
                flush=True,
            )

    db.commit()
    db.close()
    print(
        f"\nDone. Added {n_added:,} new files. "
        f"Inputs: {n_inputs:,} total, {n_already_cached:,} already cached, "
        f"{n_skipped_invalid:,} skipped (invalid filename), "
        f"{n_failed:,} synthesis failures. "
        f"{time.time() - t0:.1f}s elapsed."
    )
    return n_added


def _read_headwords_from_db(db_path: Path) -> list[str]:
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rows = db.execute(
        "SELECT DISTINCT headword FROM entries ORDER BY headword"
    ).fetchall()
    db.close()
    return [r[0] for r in rows]


def main():
    p = argparse.ArgumentParser()
    p.add_argument(
        "--build", action="store_true",
        help="bulk-generate audio for every headword in vox_es.db",
    )
    p.add_argument(
        "--limit", type=int, default=None,
        help="bulk mode: stop after N headwords (smoke test)",
    )
    p.add_argument(
        "--db", type=Path, default=REPO_ROOT / "vox_es.db",
        help="path to vox_es.db (default: ./vox_es.db)",
    )
    p.add_argument(
        "words", nargs="*",
        help="ad-hoc synthesis: synthesize each given word (no --build needed)",
    )
    args = p.parse_args()

    if args.build:
        if not args.db.exists():
            sys.exit(f"vox_es.db not at {args.db}; build it first.")
        words = _read_headwords_from_db(args.db)
        if args.limit:
            words = words[: args.limit]
        print(f"Pre-generating Piper TTS for {len(words):,} headwords ...")
        precompute(words)
        return

    if not args.words:
        sys.exit(
            "Pass --build to bulk-generate, or list words to synthesize. "
            "Examples:\n"
            "  python -m db_es.tts --build --limit 100\n"
            "  python -m db_es.tts correr casa tiempo"
        )
    db = _ensure_dir()
    voice = _load_voice()
    for w in args.words:
        path = synthesize(w, voice=voice, db=db)
        if path:
            print(f"  {w:18s} -> {path.relative_to(REPO_ROOT)}")
        else:
            print(f"  {w:18s} -> (skipped: invalid for filename)")
    db.close()


if __name__ == "__main__":
    main()
