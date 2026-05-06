#!/usr/bin/env python3
import sys
import serial
import time

def serial_init(port, baudrate=115200):
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

def serial_read_loop(ser):
    print("Reading from serial... (Ctrl+C to exit)")
    print("-" * 60)
    try:
        while True:
            data = ser.read(ser.in_waiting or 1)
            if data:
                hex_str = ' '.join(f'0x{b:02X}' for b in data)
                try:
                    ascii_str = data.decode('ascii')
                except UnicodeDecodeError:
                    ascii_str = data.decode('ascii', errors='replace')
                print(f"[BIN ] {hex_str}")
                print(f"[ASCII] {ascii_str}")
                print("-" * 60)
    except KeyboardInterrupt:
        print("\nExited.")

def main():
    if len(sys.argv) < 2:
        print(f"Usage: python {sys.argv[0]} <serial_port> [baudrate]")
        print(f"Example: python {sys.argv[0]} /dev/ttyUSB0 115200")
        sys.exit(1)

    port = sys.argv[1]
    baudrate = int(sys.argv[2]) if len(sys.argv) > 2 else 115200

    ser = serial_init(port, baudrate)
    if ser:
        serial_read_loop(ser)
        ser.close()
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
