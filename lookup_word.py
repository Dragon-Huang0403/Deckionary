#!/usr/bin/env python3
"""
Look up a word in OALD10 and render its full dictionary entry in the browser.

Usage:
    python lookup_word.py <word>
    python lookup_word.py run
    python lookup_word.py "run down"

First run builds an index cache (~10s). Subsequent runs are instant.
Output: opens the entry as an HTML file in your default browser.
         Pass --html to print the HTML to stdout instead.
"""

import json
import re
import struct
import sys
import zlib
import tempfile
import webbrowser
from pathlib import Path

CONTENTS = Path("oxford.dictionary/Contents").resolve()
BODY = CONTENTS / "Body.data"
INDEX_CACHE = Path(".oald10_index.json")


# ── Index ─────────────────────────────────────────────────────────────────────

def build_index() -> dict:
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
            partial = zlib.decompress(data[zlib_start : zlib_start + compressed_size], 15, 512)
            m = re.search(rb'd:title="([^"]+)"', partial)
            if m:
                title = m.group(1).decode("utf-8", errors="replace")
                index[title.lower()] = pos
        except Exception:
            pass

        pos = zlib_start + compressed_size

    INDEX_CACHE.write_text(json.dumps(index, ensure_ascii=False))
    print(f"Index built: {len(index)} entries.", file=sys.stderr)
    return index


def load_index() -> dict:
    if INDEX_CACHE.exists():
        return json.loads(INDEX_CACHE.read_text())
    return build_index()


# ── Entry HTML ────────────────────────────────────────────────────────────────

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


# ── Render ────────────────────────────────────────────────────────────────────

def render(entry_html: str, word: str) -> str:
    # Strip the <d:entry> wrapper — browsers don't know that tag
    body = re.sub(r"^<d:entry[^>]*>|</d:entry>$", "", entry_html.strip())

    # Rewrite relative audio src so they work from a temp file
    # e.g.  "run__gb_1.mp3"  →  absolute path
    def abs_audio(m):
        filename = m.group(1)
        abs_path = CONTENTS / filename
        return f'"{abs_path.as_uri()}"'

    body = re.sub(r'"([^"]+\.mp3)"', abs_audio, body)

    # Load the dictionary CSS
    css_path = CONTENTS / "oald10.css"
    css = css_path.read_text(encoding="utf-8") if css_path.exists() else ""

    # Load the dictionary JS
    js_path = CONTENTS / "oald10.js"
    js = js_path.read_text(encoding="utf-8") if js_path.exists() else ""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{word} — OALD10</title>
  <style>
{css}
  </style>
</head>
<body>
{body}
<script>{js}</script>
</body>
</html>"""


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    word = " ".join(args)

    index = load_index()
    entry_html = get_entry_html(index, word)

    if entry_html is None:
        lower = word.lower()
        matches = [k for k in index if k.startswith(lower)][:8]
        if matches:
            print(f'"{word}" not found. Did you mean: {", ".join(matches)}?')
        else:
            print(f'"{word}" not found in dictionary.')
        sys.exit(1)

    html = render(entry_html, word)

    if "--html" in flags:
        print(html)
        return

    # Write to a temp file and open in browser
    tmp = tempfile.NamedTemporaryFile(
        suffix=".html", prefix=f"oald_{word.replace(' ', '_')}_",
        delete=False, mode="w", encoding="utf-8"
    )
    tmp.write(html)
    tmp.close()
    print(f"Opening: {tmp.name}", file=sys.stderr)
    webbrowser.open(f"file://{tmp.name}")


if __name__ == "__main__":
    main()
