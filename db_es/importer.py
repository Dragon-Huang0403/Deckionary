"""Body.data binary reader for macOS Dictionary.app bundles.

Two known block layouts in the wild:
  - OALD10 / 3rd-party bundles: one <d:entry> per zlib block. ~62K blocks
    in OALD10's 90 MB Body.data.
  - Apple's bundled dictionaries (NOAD, Larousse, Oxford ES-EN): many
    <d:entry> packed into each zlib block (~150 entries, ~270KB
    decompressed per block). 357 blocks in 12 MB Larousse Body.data
    stretches to ~53K headwords once unpacked.

This reader handles both: it walks all blocks, decompresses each fully,
splits on `<d:entry...></d:entry>` and indexes per entry. For OALD10 the
per-block split yields one entry; for Apple bundles it yields all of
them. Homographs (multiple entries with the same `d:title`) are kept as
a list per key.

Memory: full decompressed corpus held in RAM (~100MB for Larousse,
~120MB for Oxford bilingual, ~120MB for OALD10) — fine on a dev box.
"""

from __future__ import annotations

import re
import struct
import zlib
from pathlib import Path

_ENTRY_RE = re.compile(
    rb'<d:entry\b[^>]*\bd:title="([^"]+)"[^>]*>.*?</d:entry>',
    re.DOTALL,
)


def _iter_blocks(data: bytes):
    """Yield (block_pos, decompressed_bytes) for every zlib block."""
    pos = 0x60
    while pos < len(data) - 12:
        sz1 = struct.unpack_from("<I", data, pos)[0]
        sz2 = struct.unpack_from("<I", data, pos + 4)[0]
        if sz1 == 0 or sz1 > 50_000_000:
            break
        zlib_start = pos + 12
        compressed_size = sz2 - 4
        try:
            decompressed = zlib.decompress(
                data[zlib_start : zlib_start + compressed_size]
            )
        except Exception:
            pos = zlib_start + compressed_size
            continue
        yield pos, decompressed
        pos = zlib_start + compressed_size


def _extract_entries(block: bytes):
    """Yield (headword_lower, entry_html) for every <d:entry> in block."""
    for m in _ENTRY_RE.finditer(block):
        title = m.group(1).decode("utf-8", errors="replace")
        html = m.group(0).decode("utf-8", errors="replace")
        yield title.lower(), html


class BodyDataReader:
    """In-memory reader: full corpus indexed up front."""

    def __init__(self, body_path: str | Path):
        self.body_path = Path(body_path)
        if not self.body_path.exists():
            raise FileNotFoundError(f"Body.data not found at {self.body_path}")
        self._index: dict[str, list[str]] | None = None

    def _load(self) -> dict[str, list[str]]:
        if self._index is None:
            data = self.body_path.read_bytes()
            index: dict[str, list[str]] = {}
            for _, block in _iter_blocks(data):
                for title, html in _extract_entries(block):
                    index.setdefault(title, []).append(html)
            self._index = index
        return self._index

    def headwords(self) -> list[str]:
        return list(self._load().keys())

    def __len__(self) -> int:
        return sum(len(v) for v in self._load().values())

    def unique_headword_count(self) -> int:
        return len(self._load())

    def __contains__(self, headword: str) -> bool:
        return headword.lower() in self._load()

    def get_html(self, headword: str) -> str | None:
        """Return the first entry's HTML for `headword`, or None."""
        entries = self._load().get(headword.lower())
        return entries[0] if entries else None

    def get_all_html(self, headword: str) -> list[str]:
        """Return all homograph entries' HTML for `headword`."""
        return list(self._load().get(headword.lower(), []))

    def iter_entries(self):
        """Yield (headword, html) for every entry, including homographs."""
        for headword, htmls in self._load().items():
            for html in htmls:
                yield headword, html


def find_dictionary_bundles() -> dict[str, Path]:
    """Search standard macOS dictionary asset locations for installed bundles.

    Returns {bundle_display_name: path_to_Body.data}. Caller can filter for
    Spanish bundles by name. Searches three roots:
      - /Library/Dictionaries
      - ~/Library/Dictionaries
      - /System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS/*.asset
    """
    roots = [
        Path("/Library/Dictionaries"),
        Path.home() / "Library/Dictionaries",
        Path(
            "/System/Library/AssetsV2/"
            "com_apple_MobileAsset_DictionaryServices_dictionary3macOS"
        ),
    ]
    found: dict[str, Path] = {}
    for root in roots:
        if not root.exists():
            continue
        for body in root.rglob("Body.data"):
            try:
                bundle = next(
                    p for p in body.parents if p.suffix == ".dictionary"
                )
            except StopIteration:
                continue
            found.setdefault(bundle.stem, body)
    return found


if __name__ == "__main__":
    # Quick CLI for inspection: `python -m db_es.importer`
    import sys

    bundles = find_dictionary_bundles()
    print(f"Found {len(bundles)} dictionary bundle(s):")
    for name, path in sorted(bundles.items()):
        size_mb = path.stat().st_size / (1024 * 1024)
        print(f"  {name:60s} {size_mb:6.1f} MB  {path}")

    if len(sys.argv) > 1:
        target = sys.argv[1]
        if target not in bundles:
            print(f"\nBundle '{target}' not found.", file=sys.stderr)
            sys.exit(1)
        reader = BodyDataReader(bundles[target])
        n_total = len(reader)
        n_unique = reader.unique_headword_count()
        print(
            f"\n{target}: {n_unique:,} unique headwords, "
            f"{n_total:,} total entries (incl. homographs)"
        )
        print("First 10 headwords:", reader.headwords()[:10])
        if len(sys.argv) > 2:
            word = sys.argv[2]
            html = reader.get_html(word)
            if html:
                print(f"\n--- {word} ({len(html)} chars) ---")
                print(html[:1500])
            else:
                print(f"\n'{word}' not found")
