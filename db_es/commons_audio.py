"""Wikimedia Commons audio fetcher for Spanish words.

Strategy (in order):
  1. Search Commons API for `intitle:"LL-Q1321 (spa)" intitle:{word}` —
     Lingua Libre Spanish recordings have predictable filenames like
     `LL-Q1321 (spa)-<speaker>-<word>.wav`. Filter results to exact word
     matches (so "tiempo" doesn't pick up "tiempos.wav").
  2. Fallback: parse EN Wiktionary's Spanish section for any embedded
     <audio> elements. Catches non-Lingua-Libre cases.
  3. Fallback: parse ES Wiktionary page for any audio.

For each candidate, resolve the actual media URL via the Commons imageinfo
API, then download into audio_es/<word>__es_<n>.<ext>. Cache result (hit
or miss) in audio_es/index.sqlite — re-calls are cheap.

No API key. Polite User-Agent + per-request rate limit.
"""

from __future__ import annotations

import html as html_lib
import json
import re
import sqlite3
import time
import urllib.parse
import urllib.request
from pathlib import Path

USER_AGENT = (
    "DeckionaryPreview/0.1 "
    "(https://github.com/local; "
    "personal language-learning preview tool) "
    "Python-urllib"
)
AUDIO_DIR = Path(__file__).resolve().parents[1] / "audio_es"
INDEX_DB = AUDIO_DIR / "index.sqlite"
MIN_INTERVAL = 1.0  # seconds between HTTP calls (Wikimedia bot policy)
COMMONS_API = "https://commons.wikimedia.org/w/api.php"

_last_call: list[float] = [0.0]


def _http_get(url: str, timeout: int = 15) -> bytes:
    """Polite HTTP GET: throttles to ~1 req/s, retries once on 429."""
    delay = MIN_INTERVAL - (time.monotonic() - _last_call[0])
    if delay > 0:
        time.sleep(delay)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = r.read()
        _last_call[0] = time.monotonic()
        return data
    except urllib.error.HTTPError as e:
        if e.code == 429:
            time.sleep(5.0)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
            _last_call[0] = time.monotonic()
            return data
        raise


def _ensure_index_db() -> sqlite3.Connection:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(INDEX_DB)
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS cache (
            word    TEXT PRIMARY KEY,
            status  TEXT NOT NULL,
            file    TEXT NOT NULL DEFAULT '',
            source  TEXT NOT NULL DEFAULT '',
            fetched TEXT NOT NULL DEFAULT (datetime('now'))
        )
        """
    )
    db.commit()
    return db


def _extract_spanish_section(html: str) -> str:
    """Slice the EN Wiktionary HTML to just the Spanish language section.

    Modern Wiktionary uses <h2 id="Spanish">; older pages use a <span
    class="mw-headline" id="Spanish"> inside an <h2>. Section ends at the
    next <h2> or the end-of-content marker.
    """
    patterns = [
        r'<h2[^>]*\bid="Spanish"[^>]*>',
        r'<span[^>]*\bclass="mw-headline"[^>]*\bid="Spanish"',
    ]
    start = -1
    for pat in patterns:
        m = re.search(pat, html)
        if m:
            start = m.start()
            break
    if start < 0:
        return ""
    end_m = re.search(r'<h2[^>]*\bid="(?!Spanish")[^"]+"', html[start + 10 :])
    end = (start + 10 + end_m.start()) if end_m else len(html)
    return html[start:end]


_AUDIO_SRC_RE = re.compile(
    r'<source\b[^>]*\bsrc="([^"]+\.(?:ogg|oga|mp3|wav))"', re.IGNORECASE
)


def _audio_urls_in(section_html: str) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()
    for m in _AUDIO_SRC_RE.finditer(section_html):
        url = html_lib.unescape(m.group(1))
        if url.startswith("//"):
            url = "https:" + url
        elif url.startswith("/"):
            url = "https://en.wiktionary.org" + url
        url = url.split("?", 1)[0]  # strip utm tracking params (triggers 429)
        if url not in seen:
            seen.add(url)
            urls.append(url)
    urls.sort(key=lambda u: 0 if "LL-Q1321" in u else 1)
    return urls


def _safe_name(word: str) -> str:
    """Produce a filesystem-safe filename component."""
    s = re.sub(r"[^a-z0-9áéíóúñü_-]+", "_", word.lower())
    return s.strip("_") or "_"


def _commons_search_lingua_libre(word: str) -> list[str]:
    """Return Commons File: titles for Lingua Libre Spanish recordings of
    `word`, filtered so only exact-word matches are returned.
    """
    query = f'intitle:"LL-Q1321 (spa)" intitle:{word}'
    params = {
        "action": "query",
        "list": "search",
        "srnamespace": "6",
        "srsearch": query,
        "format": "json",
        "srlimit": "10",
    }
    url = f"{COMMONS_API}?{urllib.parse.urlencode(params)}"
    try:
        data = json.loads(_http_get(url))
    except Exception:
        return []
    titles: list[str] = []
    word_lc = word.lower()
    pattern = re.compile(
        r"^File:LL-Q1321 \(spa\)-[^-]+-"
        + re.escape(word_lc)
        + r"\.(?:wav|ogg|mp3)$",
        re.IGNORECASE,
    )
    for hit in data.get("query", {}).get("search", []):
        title = hit.get("title", "")
        if pattern.match(title):
            titles.append(title)
    return titles


def _commons_resolve_url(file_title: str) -> str | None:
    """Given a 'File:Foo.wav' title, return the direct download URL."""
    params = {
        "action": "query",
        "prop": "imageinfo",
        "iiprop": "url",
        "titles": file_title,
        "format": "json",
    }
    url = f"{COMMONS_API}?{urllib.parse.urlencode(params)}"
    try:
        data = json.loads(_http_get(url))
    except Exception:
        return None
    pages = data.get("query", {}).get("pages", {})
    for _, page in pages.items():
        info = page.get("imageinfo", [])
        if info and info[0].get("url"):
            # Strip tracking query params — Wikimedia's bot policy 429's
            # download requests that carry the utm_* params returned here.
            url = info[0]["url"]
            return url.split("?", 1)[0]
    return None


def _try_commons_lingua_libre(word: str) -> Path | None:
    titles = _commons_search_lingua_libre(word)
    if not titles:
        return None
    for title in titles:
        url = _commons_resolve_url(title)
        if not url:
            continue
        ext = Path(urllib.parse.urlparse(url).path).suffix.lstrip(".").lower() or "ogg"
        if ext == "oga":
            ext = "ogg"
        target = AUDIO_DIR / f"{_safe_name(word)}__es_1.{ext}"
        try:
            target.write_bytes(_http_get(url))
            return target
        except Exception:
            continue
    return None


def _try_source(word: str, lang: str) -> Path | None:
    """Fetch Wiktionary page (lang='en' or 'es') and download first audio found."""
    url = f"https://{lang}.wiktionary.org/wiki/{urllib.parse.quote(word)}"
    try:
        html = _http_get(url).decode("utf-8", errors="replace")
    except Exception:
        return None

    section = _extract_spanish_section(html) if lang == "en" else html
    audio_urls = _audio_urls_in(section)
    if not audio_urls:
        return None

    for audio_url in audio_urls:
        path = urllib.parse.urlparse(audio_url).path
        ext = Path(path).suffix.lstrip(".").lower() or "ogg"
        if ext == "oga":
            ext = "ogg"
        target = AUDIO_DIR / f"{_safe_name(word)}__es_1.{ext}"
        try:
            data = _http_get(audio_url)
            target.write_bytes(data)
            return target
        except Exception:
            continue
    return None


def fetch(word: str, *, refresh: bool = False) -> Path | None:
    """Return cached audio path for `word`, downloading if needed.

    Returns None if no Spanish audio is available on Wiktionary. Result is
    cached in audio_es/index.sqlite — both hits and misses, so re-calling
    `fetch("xyz")` is cheap.
    """
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    db = _ensure_index_db()

    if not refresh:
        row = db.execute(
            "SELECT status, file FROM cache WHERE word = ?", (word,)
        ).fetchone()
        if row:
            status, file_name = row
            if status == "found" and file_name:
                p = AUDIO_DIR / file_name
                if p.exists():
                    return p
            elif status == "missing":
                return None

    # Primary: Commons API search for Lingua Libre Spanish recordings
    path = _try_commons_lingua_libre(word)
    if path:
        db.execute(
            "INSERT OR REPLACE INTO cache(word, status, file, source) "
            "VALUES (?, 'found', ?, 'commons_lingua_libre')",
            (word, path.name),
        )
        db.commit()
        return path

    # Fallbacks: Wiktionary pages
    for lang in ("en", "es"):
        path = _try_source(word, lang)
        if path:
            db.execute(
                "INSERT OR REPLACE INTO cache(word, status, file, source) "
                "VALUES (?, 'found', ?, ?)",
                (word, path.name, f"{lang}_wiktionary"),
            )
            db.commit()
            return path

    db.execute(
        "INSERT OR REPLACE INTO cache(word, status, file, source) "
        "VALUES (?, 'missing', '', '')",
        (word,),
    )
    db.commit()
    return None


if __name__ == "__main__":
    import sys

    words = sys.argv[1:] or ["correr", "casa", "tiempo", "ser", "hablar"]
    for w in words:
        p = fetch(w)
        if p:
            print(f"  {w:15s} -> {p.name} ({p.stat().st_size:,} bytes)")
        else:
            print(f"  {w:15s} -> (no audio)")
