#!/usr/bin/env python3
"""Remove empty lines from custom-words.csv."""

from pathlib import Path

csv_path = Path("custom-words.csv")
lines = csv_path.read_text().splitlines()
cleaned = [line for line in lines if line.strip()]
csv_path.write_text("\n".join(cleaned) + "\n")
print(f"Done: {len(cleaned) - 1} words (removed {len(lines) - len(cleaned)} empty lines)")
