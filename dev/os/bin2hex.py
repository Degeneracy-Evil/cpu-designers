#!/usr/bin/env python3
"""bin2hex.py — Convert a flat binary to $readmemh hex format.

Usage: python3 bin2hex.py <input.bin> <output.hex> [--pad-start N]
                          [--boot-jump ADDR]

Output format: one 8-hex-char word per line (little-endian 32-bit words),
matching the format consumed by $readmemh in axi_wrap_ram.sv /
axi4lite_bootrom.sv and produced by tools/rv2coe.py:write_hex().

Options:
  --pad-start N   Prepend N zero words before the binary content.
                  Used when the binary's VMA is higher than the SRAM base
                  (e.g. kernel at 0x80004000, SRAM base 0x80000000 ->
                  pad-start = (0x80004000 - 0x80000000) / 4 = 4096 words).
  --boot-jump A   Place a 2-instruction jump sequence (lui t0,A>>12; jr t0)
                  at word 0 of the output, followed by (N-2) zero words,
                  then the binary content.  This lets the bootloader (which
                  jumps to the SRAM base 0x80000000) reach a kernel linked
                  at a higher address (e.g. 0x80004000) without modifying
                  the bootloader.  Requires --pad-start N >= 2.
"""
import sys


def main():
    args = sys.argv[1:]
    pad_start = 0
    boot_jump = None

    if "--pad-start" in args:
        idx = args.index("--pad-start")
        pad_start = int(args[idx + 1], 0)
        args = args[:idx] + args[idx + 2:]

    if "--boot-jump" in args:
        idx = args.index("--boot-jump")
        boot_jump = int(args[idx + 1], 0)
        args = args[:idx] + args[idx + 2:]

    if len(args) != 2:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.hex> "
              f"[--pad-start N] [--boot-jump ADDR]", file=sys.stderr)
        return 1

    in_path, out_path = args
    data = open(in_path, "rb").read()

    # Pad to 4-byte alignment
    pad = (4 - len(data) % 4) % 4
    data += b"\x00" * pad

    words = [f"{int.from_bytes(data[i:i+4], byteorder='little'):08x}"
             for i in range(0, len(data), 4)]

    pad_words = ["00000000"] * pad_start

    # Optionally place a boot jump at word 0: lui t0, ADDR>>12; jr t0
    if boot_jump is not None:
        if pad_start < 2:
            print("error: --boot-jump requires --pad-start >= 2",
                  file=sys.stderr)
            return 1
        # lui t0, imm20  —  imm20 = boot_jump >> 12 (20-bit immediate)
        imm20 = (boot_jump >> 12) & 0xFFFFF
        lui = (imm20 << 12) | (5 << 7) | 0x37   # rd=t0=x5, opcode=LUI
        # jr t0  =  jalr x0, t0, 0
        jr = (5 << 15) | (0 << 12) | (0 << 7) | 0x67  # rs1=t0, funct3=0, rd=x0
        pad_words[0] = f"{lui:08x}"
        pad_words[1] = f"{jr:08x}"

    all_words = pad_words + words

    with open(out_path, "w") as f:
        f.write("\n".join(all_words) + "\n")

    print(f"[HEX ] {out_path} ({len(all_words)} words, "
          f"{len(all_words) * 4} bytes; pad_start={pad_start})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
