"""Spanish word-frequency tier loader.

Source: hermitdave/FrequencyWords ES list (MIT, derived from OpenSubtitles).
Format: one word per line, ``<word> <count>``, sorted by count descending.

We translate frequency rank into a coarse tier that goes alongside each
entry in vox_es.db. Tiers mirror OALD10's ox3000/ox5000 idea — a quick
visual signal of how common a word is.

    rank ≤ 1,000   → 'top1k'
    rank ≤ 2,000   → 'top2k'
    rank ≤ 5,000   → 'top5k'
    rank ≤ 10,000  → 'top10k'
    rank ≤ 20,000  → 'top20k'
    else           → ''   (no badge shown)
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FREQ_FILE = REPO_ROOT / "data_es" / "es_frequency_50k.txt"

TIER_THRESHOLDS = (
    (1_000, "top1k"),
    (2_000, "top2k"),
    (5_000, "top5k"),
    (10_000, "top10k"),
    (20_000, "top20k"),
)


def _tier_for_rank(rank: int) -> str:
    for cutoff, name in TIER_THRESHOLDS:
        if rank <= cutoff:
            return name
    return ""


@lru_cache(maxsize=4)
def load_tier_map(path: str | Path = DEFAULT_FREQ_FILE) -> dict[str, str]:
    """Return ``{lowercased_word: tier}`` for the frequency list at ``path``.

    Cached per-path. If the file is missing, returns an empty dict so
    the build script can degrade gracefully (no tiers, but no crash).
    """
    p = Path(path)
    if not p.exists():
        return {}
    out: dict[str, str] = {}
    with p.open(encoding="utf-8") as f:
        for rank, line in enumerate(f, start=1):
            word = line.split(" ", 1)[0].strip().lower()
            if not word:
                continue
            tier = _tier_for_rank(rank)
            if not tier:
                # Past the last threshold — remaining entries get no tier
                break
            # First occurrence wins (file is rank-ordered)
            out.setdefault(word, tier)
    return out


if __name__ == "__main__":
    import sys
    tier_map = load_tier_map()
    print(f"Loaded tier map: {len(tier_map):,} words tiered")
    for w in sys.argv[1:] or ["correr", "casa", "tiempo", "ser", "hablar",
                              "perro", "ringorrango", "aflechado"]:
        print(f"  {w:18s} -> {tier_map.get(w.lower()) or '(none)'}")
