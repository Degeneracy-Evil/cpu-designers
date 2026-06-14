#!/usr/bin/env python3
"""
uart_console.py — UART console with optional program loading.

Supports loading a RISC-V program into DDR3 via UART bootloader
(using the same protocol as uart_load.py), then immediately entering
an interactive console.

Usage:
  # Console only
  python -m tools.uart_console -p /dev/ttyUSB0

  # Load program then enter console
  python -m tools.uart_console -p /dev/ttyUSB0 -f program.hex

  # Full options
  python -m tools.uart_console -p /dev/ttyUSB0 -b 115200 -f program.hex \
      --load-addr 0x80000000 --entry 0x80000000
"""

import argparse
import os
import struct
import sys
import threading
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

# ── Bootloader protocol constants ──────────────────────────────────────
MAGIC = 0x52495343  # "RISC" in little-endian


# ── Hex / Bin parsers ──────────────────────────────────────────────────
def parse_hex(path: str) -> bytes:
    """Parse $readmemh-style hex file (one 32-bit word per line, hex)."""
    words = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue
            words.append(int(line, 16))
    data = b""
    for w in words:
        data += struct.pack("<I", w)
    return data


def parse_bin(path: str) -> bytes:
    """Read raw binary file."""
    with open(path, "rb") as f:
        return f.read()


def read_program(file_path: str) -> bytes:
    """Read program file, auto-detecting format (.hex / .bin)."""
    if file_path.endswith(".hex"):
        return parse_hex(file_path)
    elif file_path.endswith(".bin"):
        return parse_bin(file_path)
    else:
        try:
            return parse_hex(file_path)
        except (ValueError, OSError):
            return parse_bin(file_path)


# ── Program loading ────────────────────────────────────────────────────
def load_program(
    ser: serial.Serial,
    file_path: str,
    load_addr: int = 0x80000000,
    entry_addr: int = 0x80000000,
    wait_ready: bool = True,
):
    """Load program into DDR3 via UART bootloader on an already-open serial port."""
    program = read_program(file_path)
    length = len(program)

    print(f"Program: {file_path}")
    print(f"  Size:   {length} bytes ({length // 4} words)")
    print(f"  Load:   0x{load_addr:08X}")
    print(f"  Entry:  0x{entry_addr:08X}")

    if length % 4 != 0:
        print(f"WARNING: Program size ({length}) not word-aligned, padding with zeros")
        program += b"\x00" * (4 - length % 4)
        length = len(program)

    # Wait for bootloader to be ready (DDR3 self-test + UART init)
    if wait_ready:
        print("Waiting for bootloader ready...")
        time.sleep(0.5)

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
    print("Program loaded. CPU should now execute from DDR3.")


# ── Serial init ────────────────────────────────────────────────────────
def serial_init(port: str, baudrate: int = 115200):
    ser = serial.Serial()
    ser.port = port
    ser.baudrate = baudrate
    ser.bytesize = serial.EIGHTBITS
    ser.parity = serial.PARITY_NONE
    ser.stopbits = serial.STOPBITS_ONE
    ser.xonxoff = False
    ser.rtscts = False
    ser.dsrdtr = False
    ser.timeout = 0.1
    try:
        ser.open()
        if ser.is_open:
            print(f"Serial port {port} opened at {baudrate} bps")
            return ser
    except serial.SerialException as e:
        print(f"Failed to open {port}: {e}")
    return None


# ── Console read thread ────────────────────────────────────────────────
def serial_read_thread(ser: serial.Serial):
    buffer = bytearray()
    try:
        while True:
            data = ser.read(max(1, ser.in_waiting))
            if data:
                buffer.extend(data)

                # 检查缓冲区末尾是否为不完整的 UTF-8 多字节字符
                split_idx = len(buffer)
                for i in range(1, min(5, len(buffer) + 1)):
                    b = buffer[-i]
                    if b < 0x80:
                        break
                    elif b >= 0xC0:
                        expected_len = 2 if b < 0xE0 else (3 if b < 0xF0 else 4)
                        if i < expected_len:
                            split_idx = len(buffer) - i
                        break

                if split_idx == 0:
                    continue

                chunk = buffer[:split_idx]
                buffer = buffer[split_idx:]

                hex_str = ' '.join(f'{b:02X}' for b in chunk)
                decoded_str = chunk.decode('utf-8', errors='replace')
                print(f"\n[HEX] {hex_str}")
                print(f"[TXT] {decoded_str}", end='')
                sys.stdout.flush()
    except serial.SerialException:
        print("\nSerial port closed or error.")


def serial_write_line_mode(ser: serial.Serial):
    while True:
        user_input = sys.stdin.readline()
        if not user_input:
            break
        ser.write(user_input.encode("utf-8"))


def serial_write_raw_mode(ser: serial.Serial):
    if os.name == "nt":
        import msvcrt

        while True:
            ch = msvcrt.getwch()
            if ch == "\x03":  # Ctrl+C
                raise KeyboardInterrupt
            # 处理回车键：串口发送 \n，本地回显 \r\n
            if ch == "\r":
                ser.write(b"\n")  # 串口发送换行符
                sys.stdout.buffer.write(b"\r\n")  # 本地回显：回车+换行
            else:
                b = ch.encode("utf-8", errors="replace")
                ser.write(b)
                sys.stdout.buffer.write(b)
            sys.stdout.flush()  # 立即刷新输出
    else:
        import termios
        import tty

        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setcbreak(fd)
            while True:
                b = os.read(fd, 1)
                if not b:
                    break
                if b == b"\x03":  # Ctrl+C
                    raise KeyboardInterrupt
                # 处理回车键：串口发送 \n，本地回显 \r\n
                if b == b"\r":
                    ser.write(b"\n")
                    sys.stdout.buffer.write(b"\r\n")
                else:
                    ser.write(b)
                    sys.stdout.buffer.write(b)
                sys.stdout.flush()
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)


# ── Main ───────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="UART console with optional program loading via UART bootloader"
    )
    parser.add_argument("-p", "--port", required=True,
                        help="Serial port (e.g., COM3, /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200,
                        help="Baud rate (default: 115200)")
    parser.add_argument("-f", "--file", default=None,
                        help="Program file to load (.hex or .bin); skip to enter console only")
    parser.add_argument("--load-addr", type=lambda x: int(x, 0),
                        default=0x80000000,
                        help="Load address in DDR3 (default: 0x80000000)")
    parser.add_argument("--entry", type=lambda x: int(x, 0),
                        default=0x80000000,
                        help="Entry address (default: 0x80000000)")
    parser.add_argument("--no-wait", action="store_true",
                        help="Skip bootloader ready-wait delay")
    parser.add_argument("--raw", action="store_true",
                        help="Send keystrokes immediately instead of line-buffered readline mode")

    args = parser.parse_args()

    ser = serial_init(args.port, args.baud)
    if not ser:
        sys.exit(1)

    if args.file:
        load_program(
            ser,
            file_path=args.file,
            load_addr=args.load_addr,
            entry_addr=args.entry,
            wait_ready=not args.no_wait,
        )
        print("-" * 60)

    mode = "raw" if args.raw else "line"
    print(f"Starting console in {mode} mode... (Ctrl+C to exit)")
    print("-" * 60)

    t = threading.Thread(target=serial_read_thread, args=(ser,), daemon=True)
    t.start()

    try:
        if args.raw:
            serial_write_raw_mode(ser)
        else:
            serial_write_line_mode(ser)
    except KeyboardInterrupt:
        print("\nExited.")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
