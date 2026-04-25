import os
import sys
import signal
import serial

ACK = bytes([0x6])
PACKET_LEN = 131
SIZE_INDEX = 1
CRC0_INDEX = 129
CRC1_INDEX = 130
DATA_PER_PACKET = 128

serial_com = serial.Serial()
running = True


def signal_handler(sig, frame):
    global running
    print('\nReceived Ctrl+C, exiting...')
    running = False


def serial_init():
    serial_com.port = sys.argv[1]
    serial_com.baudrate = 115200
    serial_com.bytesize = serial.EIGHTBITS
    serial_com.parity = serial.PARITY_NONE
    serial_com.stopbits = serial.STOPBITS_ONE
    serial_com.xonxoff = False
    serial_com.rtscts = False
    serial_com.dsrdtr = False

    if not serial_com.is_open:
        serial_com.open()
        if serial_com.is_open:
            return 0
    return -1


def serial_deinit():
    if serial_com.is_open:
        serial_com.close()


def serial_write(b):
    if serial_com.is_open:
        serial_com.write(b)
        return len(b)
    return 0


def serial_read(length, timeout):
    if timeout > 0:
        serial_com.timeout = timeout

    if serial_com.is_open:
        data = serial_com.read(length)
        if len(data) > 0:
            return data
    return None


def serial_print(bit):
    data = serial_read(bit, 2)
    if data is not None:
        try:
            print(data.decode('ascii'), end='')
        except UnicodeDecodeError:
            print(data.hex())
    else:
        print('no data arrive!!!')


def calc_crc16(data):
    crc = 0xFFFF
    for pos in data:
        crc ^= pos
        for _ in range(8):
            if crc & 1:
                crc >>= 1
                crc ^= 0xA001
            else:
                crc >>= 1
    return crc


def swap_endian4(packet, r):
    t0 = packet[r - 3]
    t1 = packet[r - 2]
    packet[r - 3] = packet[r]
    packet[r - 2] = packet[r - 1]
    packet[r - 1] = t1
    packet[r] = t0


def fill_packet_data(packet, data, data_index, length):
    for r in range(1, length + 1):
        packet[r] = data[data_index + r - 1]
        if r % 4 == 0:
            swap_endian4(packet, r)


def send_packets(filename, type_name):
    if not os.path.exists(filename):
        print(f'Error: file not found: {filename}')
        return False

    bin_file_size = os.path.getsize(filename)
    print(f'bin file size: {bin_file_size} bytes')
    print(f'bin file name: {os.path.basename(filename)}')
    packet_num = int(bin_file_size / DATA_PER_PACKET) + 1
    print(f'Total {packet_num} packets to be sent')

    if packet_num > 255:
        print(f'Error: packet count {packet_num} exceeds 255, cannot fit in 1 byte')
        return False

    print('send #0 packet')
    packet = [0] * PACKET_LEN
    packet[0] = type_name
    packet[SIZE_INDEX] = packet_num & 0xFF
    crc = calc_crc16(packet[0:129])
    packet[CRC0_INDEX] = crc & 0xFF
    packet[CRC1_INDEX] = (crc >> 8) & 0xFF
    serial_write(bytes(packet))

    ack = serial_read(1, 3)
    if ack != ACK:
        print('packet0 NACK from slave')
        return False

    with open(filename, 'rb') as bin_file:
        data = bin_file.read()

    remain_len = bin_file_size
    remain_index = 0

    for i in range(packet_num):
        if not running:
            print('\nTransfer interrupted by user')
            return False

        print(f'send #{i + 1} packet')
        packet = [0] * PACKET_LEN
        packet[0] = i + 1

        chunk_len = min(remain_len, DATA_PER_PACKET)
        fill_packet_data(packet, data, remain_index, chunk_len)

        crc = calc_crc16(packet[0:129])
        packet[CRC0_INDEX] = crc & 0xFF
        packet[CRC1_INDEX] = (crc >> 8) & 0xFF
        serial_write(bytes(packet))

        ack = serial_read(1, 3)
        if ack != ACK:
            print(f'NACK from slave at packet #{i + 1}')
            return False

        remain_len -= chunk_len
        remain_index += chunk_len

    return True


def main():
    signal.signal(signal.SIGINT, signal_handler)

    if serial_init() == 0:
        print('Serial port opened successfully')
        inst_ok = send_packets(sys.argv[2] + '.inst.bin', 0x00)
        if inst_ok:
            data_ok = send_packets(sys.argv[2] + '.data.bin', 0xFF)
            if data_ok:
                print('Send successfully...')

        while running:
            serial_print(300)
    else:
        print('!!! serial init failed !!!')

    serial_deinit()
    print('Serial port closed')


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f'Usage: python {sys.argv[0]} COMx bin_file_name')
    else:
        main()
