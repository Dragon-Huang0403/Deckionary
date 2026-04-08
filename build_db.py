#!/usr/bin/env python3
"""
Build the OALD10 SQLite dictionary database.

Usage:
    python build_db.py                # build oald10.db
    python build_db.py -o my.db       # custom output path
    python build_db.py --verbose      # show per-entry details
"""

import argparse
import sys

from db.importer import import_all


def main():
    parser = argparse.ArgumentParser(description="Build OALD10 dictionary database")
    parser.add_argument("-o", "--output", default="oald10.db", help="Output database path")
    parser.add_argument("--verbose", action="store_true", help="Show per-entry details")
    args = parser.parse_args()

    import_all(args.output, verbose=args.verbose)


if __name__ == "__main__":
    main()
