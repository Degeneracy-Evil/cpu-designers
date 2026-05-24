#!/usr/bin/env python3
import sys
import serial
import threading
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

def serial_read_thread(ser):
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
                        # 遇到 ASCII 字符，无需截断
                        break
                    elif b >= 0xC0:
                        # 遇到多字节字符的起始字节
                        expected_len = 2 if b < 0xE0 else (3 if b < 0xF0 else 4)
                        if i < expected_len:
                            split_idx = len(buffer) - i
                        break
                
                if split_idx == 0:
                    continue  # 等待更多数据以凑齐字符
                
                chunk = buffer[:split_idx]
                buffer = buffer[split_idx:]
                
                hex_str = ' '.join(f'{b:02X}' for b in chunk)
                decoded_str = chunk.decode('utf-8', errors='replace')
                print(f"\n[HEX] {hex_str}")
                print(f"[TXT] {decoded_str}", end='')
                sys.stdout.flush()
    except serial.SerialException:
        print("\nSerial port closed or error.")

def main():
    if len(sys.argv) < 2:
        print(f"Usage: python {sys.argv[0]} <serial_port> [baudrate]")
        print(f"Example: python {sys.argv[0]} /dev/ttyUSB0 115200")
        sys.exit(1)

    port = sys.argv[1]
    baudrate = int(sys.argv[2]) if len(sys.argv) > 2 else 115200

    ser = serial_init(port, baudrate)
    if ser:
        print("Starting console... (Ctrl+C to exit)")
        print("-" * 60)
        
        # Start a background thread to read from the serial port
        t = threading.Thread(target=serial_read_thread, args=(ser,), daemon=True)
        t.start()
        
        # Main thread reads from stdin and writes to the serial port
        try:
            while True:
                user_input = sys.stdin.readline()
                if not user_input:
                    break
                # Send the input directly (can add \r if needed by specific devices)
                ser.write(user_input.encode('utf-8'))
        except KeyboardInterrupt:
            print("\nExited.")
        finally:
            ser.close()
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
