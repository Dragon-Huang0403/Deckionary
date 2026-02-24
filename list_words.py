#!/usr/bin/env python3
"""List all headwords in the OALD10 dictionary."""

import struct
import zlib
import re
import sys

BODY = "oxford.dictionary/Contents/Body.data"


def list_words(output_file=None):
    with open(BODY, "rb") as f:
        data = f.read()

    out = open(output_file, "w", encoding="utf-8") if output_file else sys.stdout

    pos = 0x60  # first 12-byte block header
    count = 0

    while pos < len(data) - 12:
        sz1 = struct.unpack_from("<I", data, pos)[0]
        sz2 = struct.unpack_from("<I", data, pos + 4)[0]
        if sz1 == 0 or sz1 > 500_000:
            break

        zlib_start = pos + 12
        compressed_size = sz2 - 4

        try:
            dec = zlib.decompress(data[zlib_start : zlib_start + compressed_size])
            m = re.search(rb'd:title="([^"]+)"', dec)
            if m:
                title = m.group(1).decode("utf-8", errors="replace")
                print(title, file=out)
                count += 1
        except Exception:
            pass

        pos = zlib_start + compressed_size

    if output_file:
        out.close()
        print(f"Wrote {count} words to {output_file}", file=sys.stderr)
    else:
        print(f"\n# Total: {count} words", file=sys.stderr)


if __name__ == "__main__":
    output = sys.argv[1] if len(sys.argv) > 1 else None
    list_words(output)
