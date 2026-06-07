#!/usr/bin/env python3
"""
uart_load.py — Load RISC-V program into DDR3 via UART bootloader.

The FPGA bootloader (running from Boot ROM at 0xFC00_0000) performs:
  1. DDR3 self-test (write → fence.i → read → LED indicator)
  2. UART receive: magic(4B) + length(4B) + load_addr(4B) + entry_addr(4B)
  3. UART receive: N bytes of program data → write to DDR3
  4. Jump to entry address

This script sends the header + program binary over serial.

Usage:
  python -m tools.uart_load -p COM3 -f program.hex
  python -m tools.uart_load -p /dev/ttyUSB0 -f program.hex -b 115200
  python -m tools.uart_load -p COM3 -f program.hex --load-addr 0x80000000 --entry 0x80000000
"""

import argparse
import struct
import sys
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

MAGIC = 0x52495343  # "RISC" in little-endian


def parse_hex(path: str) -> bytes:
    """Parse $readmemh-style hex file (one 32-bit word per line, hex)."""
    words = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue
            words.append(int(line, 16))
    # Convert words to little-endian byte stream
    data = b""
    for w in words:
        data += struct.pack("<I", w)
    return data


def parse_bin(path: str) -> bytes:
    """Read raw binary file."""
    with open(path, "rb") as f:
        return f.read()


def load_program(
    port: str,
    file_path: str,
    baud: int = 115200,
    load_addr: int = 0x80000000,
    entry_addr: int = 0x80000000,
    timeout: float = 10.0,
    wait_ready: bool = True,
):
    """Load program into DDR3 via UART bootloader."""

    # Read program data
    if file_path.endswith(".hex"):
        program = parse_hex(file_path)
    elif file_path.endswith(".bin"):
        program = parse_bin(file_path)
    else:
        # Try hex first, then bin
        try:
            program = parse_hex(file_path)
        except (ValueError, OSError):
            program = parse_bin(file_path)

    length = len(program)
    print(f"Program: {file_path}")
    print(f"  Size:   {length} bytes ({length // 4} words)")
    print(f"  Load:   0x{load_addr:08X}")
    print(f"  Entry:  0x{entry_addr:08X}")

    if length % 4 != 0:
        print(f"WARNING: Program size ({length}) not word-aligned, padding with zeros")
        program += b"\x00" * (4 - length % 4)
        length = len(program)

    # Open serial port
    ser = serial.Serial(port, baud, timeout=1.0)
    print(f"  Port:   {port} @ {baud} baud")

    # Wait for bootloader to be ready (DDR3 self-test + UART init)
    if wait_ready:
        print("Waiting for bootloader ready...")
        time.sleep(0.5)  # Brief pause for DDR3 calibration + self-test

    # Send header (16 bytes)
    header = struct.pack("<IIII", MAGIC, length, load_addr, entry_addr)
    print(f"Sending header: magic=0x{MAGIC:08X} len={length} "
          f"load=0x{load_addr:08X} entry=0x{entry_addr:08X}")
    ser.write(header)
    ser.flush()

    # Send program data in chunks
    CHUNK = 256
    sent = 0
    t0 = time.time()
    while sent < length:
        chunk = program[sent : sent + CHUNK]
        ser.write(chunk)
        sent += len(chunk)
        pct = sent * 100 // length
        print(f"\r  Progress: {sent}/{length} bytes ({pct}%)", end="", flush=True)
    print()

    ser.flush()
    elapsed = time.time() - t0
    throughput = length / elapsed if elapsed > 0 else 0
    print(f"  Done in {elapsed:.2f}s ({throughput:.0f} B/s)")

    ser.close()
    print("Program loaded. CPU should now execute from DDR3.")


def main():
    parser = argparse.ArgumentParser(
        description="Load RISC-V program into DDR3 via UART bootloader"
    )
    parser.add_argument("-p", "--port", required=True, help="Serial port (e.g., COM3, /dev/ttyUSB0)")
    parser.add_argument("-f", "--file", required=True, help="Program file (.hex or .bin)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument(
        "--load-addr",
        type=lambda x: int(x, 0),
        default=0x80000000,
        help="Load address in DDR3 (default: 0x80000000)",
    )
    parser.add_argument(
        "--entry",
        type=lambda x: int(x, 0),
        default=0x80000000,
        help="Entry address (default: 0x80000000)",
    )
    parser.add_argument("--no-wait", action="store_true", help="Skip ready-wait delay")

    args = parser.parse_args()
    load_program(
        port=args.port,
        file_path=args.file,
        baud=args.baud,
        load_addr=args.load_addr,
        entry_addr=args.entry,
        wait_ready=not args.no_wait,
    )


if __name__ == "__main__":
    main()
