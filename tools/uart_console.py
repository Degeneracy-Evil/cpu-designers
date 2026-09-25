#!/usr/bin/env python3
"""
uart_console.py — UART console with optional program loading.

Bootloader protocol (see software/baremetal/boot/bootloader.s):
  magic(4B) + length(4B) + load_addr(4B) + entry_addr(4B) + payload, all little-endian.

Usage:
  # LED0 亮起（DDR 自检通过）后运行：上传 Linux 并进入控制台
  python -m tools.uart_console -p /dev/ttyUSB0 -f build/opensbi/platform/generic/firmware/fw_payload.bin

  # 仅当控制台用（程序已在 DDR 中）
  python -m tools.uart_console -p /dev/ttyUSB0
"""

import argparse
import struct
import sys
import threading
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

MAGIC = 0x52495343  # "RISC" little-endian magic number
CHUNK = 4096


def parse_hex(path):
    """$readmemh-style text: one 32-bit word per line, packed little-endian."""
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith(("//", "#")):
                words.append(int(line, 16))
    return b"".join(struct.pack("<I", w) for w in words)


def load_program(ser, file_path, load_addr=0x80000000, entry_addr=0x80000000):
    if file_path.endswith(".hex"):
        program = parse_hex(file_path)
    else:
        with open(file_path, "rb") as f:
            program = f.read()
    if len(program) % 4:  # bootloader 只收整字，尾部补零防止末尾字节被丢弃
        program += b"\x00" * (4 - len(program) % 4)
    length = len(program)

    print(f"Program: {file_path}  {length} bytes ({length // 4} words)")
    print(f"Load 0x{load_addr:08X}  Entry 0x{entry_addr:08X}")

    ser.write(struct.pack("<IIII", MAGIC, length, load_addr, entry_addr))
    t0 = time.time()
    for off in range(0, length, CHUNK):
        ser.write(program[off : off + CHUNK])
        print(f"\r  Progress: {min(off + CHUNK, length)}/{length} bytes", end="", flush=True)
    ser.flush()
    print(f"\n  Done in {time.time() - t0:.1f}s")


def serial_read_thread(ser):
    try:
        while True:
            data = ser.read(ser.in_waiting or 1)
            if data:
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
    except serial.SerialException:
        print("\nSerial port closed or error.")


def serial_write_line_mode(ser):
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        ser.write(line.encode("utf-8"))


def main():
    ap = argparse.ArgumentParser(
        description="UART console with optional program loading via UART bootloader"
    )
    ap.add_argument("-p", "--port", required=True, help="Serial port (e.g., /dev/ttyUSB0)")
    ap.add_argument("-b", "--baud", type=int, default=230400,
                    help="Baud rate (default: 230400, matches bootloader BAUD_DIV=27)")
    ap.add_argument("-f", "--file", default=None,
                    help="Program file (.hex or .bin) to load first; omit for console only")
    ap.add_argument("--load-addr", type=lambda x: int(x, 0), default=0x80000000,
                    help="Load address in DDR3 (default: 0x80000000)")
    ap.add_argument("--entry", type=lambda x: int(x, 0), default=0x80000000,
                    help="Entry address (default: 0x80000000)")
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.1)

    if args.file:
        load_program(ser, args.file, args.load_addr, args.entry)
    print("-" * 60)
    print("Console started: 输入回车发送, Ctrl+C / Ctrl+D 退出")

    threading.Thread(target=serial_read_thread, args=(ser,), daemon=True).start()
    try:
        serial_write_line_mode(ser)
    except KeyboardInterrupt:
        print("\nExited.")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
