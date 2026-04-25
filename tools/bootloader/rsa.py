import sys
import signal
import serial
import time

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
    serial_com.stopbits = serial.STOPBITS_TWO
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
        serial_com.write(b.encode('ascii'))
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


def send_and_receive_packets(rsa_file_name):
    with open(rsa_file_name, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.split('=')
            if len(parts) == 2 and parts[0] == 'i_data':
                packet = parts[1][6:1030] + '\r\n'
                serial_write(packet)
                print('i_data=4096\'b' + packet)
                time.sleep(1)
                serial_print(4096)


def main():
    signal.signal(signal.SIGINT, signal_handler)

    if serial_init() == 0:
        print('Serial port opened successfully')
        send_and_receive_packets('rsa_data.txt')
    else:
        print('!!! serial init failed !!!')

    serial_deinit()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f'Usage: python {sys.argv[0]} COMx rsa_file_name')
    else:
        main()
