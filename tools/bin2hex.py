#!/usr/bin/env python3
"""Convert a flat little-endian binary image to a $readmemh word file.

The word-extraction logic (byte → 4-byte alignment → little-endian 32-bit
hex words) is shared with :mod:`tools.rv2coe` via :func:`rv2coe.bin_to_words`.
This module only wraps that into a minimal standalone CLI.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow running both as `python -m tools.bin2hex` and as a standalone script
# (`python3 tools/bin2hex.py`) by ensuring the project root is on sys.path.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tools.rv2coe import bin_to_words, write_hex


def convert(input_path: Path, output_path: Path) -> tuple[int, int]:
    original_size = input_path.stat().st_size
    if original_size == 0:
        raise ValueError(f"input image is empty: {input_path}")

    words = bin_to_words(input_path, allow_empty=False)
    write_hex(words, output_path)
    return original_size, len(words)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a raw binary to one little-endian 32-bit hex word per line."
    )
    parser.add_argument("input", type=Path, help="input flat binary image")
    parser.add_argument("output", type=Path, help="output file for Verilog $readmemh")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        byte_count, word_count = convert(args.input, args.output)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}")
        return 1

    print(
        f"Converted {args.input} ({byte_count} bytes) -> "
        f"{args.output} ({word_count} words)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())