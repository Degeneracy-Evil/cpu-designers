#!/usr/bin/env python3
"""bin2hex.py — Convert binary firmware to $readmemh hex format.

Usage:
    python3 tools/bin2hex.py input.bin output.hex [--width 32]

Produces hex file with one word per line, suitable for $readmemh.
Little-endian byte ordering (LSB first within each word).
"""

import sys
import argparse


def bin_to_hex(infile: str, outfile: str, width: int = 32):
    bytes_per_word = width // 8
    with open(infile, "rb") as f:
        data = f.read()

    # Pad to word boundary
    remainder = len(data) % bytes_per_word
    if remainder:
        data += b"\x00" * (bytes_per_word - remainder)

    with open(outfile, "w") as f:
        for i in range(0, len(data), bytes_per_word):
            word = data[i : i + bytes_per_word]
            # Little-endian: LSB at lowest address
            val = int.from_bytes(word, byteorder="little")
            f.write(f"{val:0{width // 4}X}\n")

    n_words = len(data) // bytes_per_word
    print(f"Converted {infile} → {outfile}: {len(data)} bytes ({n_words} words, {n_words * bytes_per_word / 1024 / 1024:.1f} MB)")


def main():
    parser = argparse.ArgumentParser(description="Convert binary to $readmemh hex format")
    parser.add_argument("input", help="Input .bin file")
    parser.add_argument("output", help="Output .hex file")
    parser.add_argument("--width", type=int, default=32, help="Word width in bits (default: 32)")
    args = parser.parse_args()
    bin_to_hex(args.input, args.output, args.width)


if __name__ == "__main__":
    main()
