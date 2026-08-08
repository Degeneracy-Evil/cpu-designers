#!/usr/bin/env python3
"""Convert a flat little-endian binary image to a $readmemh word file."""

from __future__ import annotations

import argparse
from pathlib import Path


def convert(input_path: Path, output_path: Path) -> tuple[int, int]:
    data = input_path.read_bytes()
    original_size = len(data)
    if original_size == 0:
        raise ValueError(f"input image is empty: {input_path}")

    padded_size = (original_size + 3) & ~3
    data += b"\x00" * (padded_size - original_size)

    words = [
        f"{int.from_bytes(data[offset:offset + 4], byteorder='little'):08x}"
        for offset in range(0, padded_size, 4)
    ]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(words) + "\n", encoding="ascii")
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
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}")
        return 1

    print(
        f"Converted {args.input} ({byte_count} bytes) -> "
        f"{args.output} ({word_count} words)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
