import os,sys,serial

ACK = bytes([0x6])
PACKET_LEN = 131
SIZE_INDEX = 1
CRC0_INDEX = 129
CRC1_INDEX = 130

serial_com = serial.Serial()

def serial_init():
    serial_com.port = sys.argv[1]
    serial_com.baudrate = 115200
    serial_com.bytesize = serial.EIGHTBITS
    serial_com.parity = serial.PARITY_NONE
    serial_com.stopbits = serial.STOPBITS_ONE
    serial_com.xonxoff = False
    serial_com.rtscts = False
    serial_com.dsrdtr = False

    if serial_com.is_open == False:
        serial_com.open()
        if serial_com.is_open:
            return 0
    else:
        return -1

def serial_deinit():
    if serial_com.is_open == True:
        serial_com.close()

def serial_write(b):
    if serial_com.is_open == True:
        serial_com.write(b)
        return len(b)
    else:
        return 0

def serial_read(length, timeout):
    if (timeout > 0):
        serial_com.timeout = timeout

    if serial_com.is_open == True:
        data = serial_com.read(length)
        if len(data) > 0:
            return data
        else:
            return -1
    else:
        return -1

def serial_print():
    while(True):
        data = serial_com.read(300)
        if data:
            print(data.decode('utf-8'))

def list_to_hex_string(list_data):
    list_str = '[ '
    for x in list_data:
        list_str += '0x{:02X},'.format(x)
    list_str += ' ]'
    return list_str

def calc_crc16(data):
    crc = 0xFFFF
    for pos in data:
        crc ^= pos
        for i in range(8):
            if ((crc & 1) != 0):
                crc >>= 1
                crc ^= 0xA001
            else:
                crc >>= 1
    return crc

def send_packets(filename,typename):
    bin_file_size = os.path.getsize(filename)
    print('bin file size: %d bytes' % bin_file_size)
    bin_file_name = os.path.basename(filename)
    print('bin file name: ' + bin_file_name)
    packet_num = int(bin_file_size / 128) + 1
    print('Total %d packets to be sent' % packet_num)
    print('send #0 packet')
    packet = [0] * PACKET_LEN
    packet[0] = typename
    packet[SIZE_INDEX] = (int(bin_file_size / 128) + 1) & 0xff
    crc = calc_crc16(packet[0:129])
    packet[CRC0_INDEX] = (crc >> 0) & 0xff
    packet[CRC1_INDEX] = (crc >> 8) & 0xff
    #print(list_to_hex_string(packet))
    serial_write(bytes(packet))
    ack = serial_read(1, 3)
    if (ack != ACK):
        print('packet0 NACK from slave')
        return
    bin_file = open(filename, 'rb')
    data = bin_file.read(bin_file_size)
    remain_data_len = bin_file_size
    remain_data_index = 0
    for i in range(packet_num):
        print('send #%d packet' % (i + 1))
        packet = [0] * PACKET_LEN
        packet[0] = i + 1
        j = 1
        k = remain_data_index
        if (remain_data_len >= 128):
            for r in range(1,128+1):
                packet[j] = data[k]
                j = j + 1
                k = k + 1
                if r % 4 == 0 :
                    t0 = packet[r-3]
                    t1 = packet[r-2]
                    packet[r - 3] = packet[r - 0]
                    packet[r - 2] = packet[r - 1]
                    packet[r - 1] = t1
                    packet[r - 0] = t0

            crc = calc_crc16(packet[0:129])
            packet[CRC0_INDEX] = (crc >> 0) & 0xff
            packet[CRC1_INDEX] = (crc >> 8) & 0xff
            #print(list_to_hex_string(packet))
            serial_write(bytes(packet))
            ack = serial_read(1, 3)
            if (ack != ACK):
                print('NACK1 from slave')
                return
            remain_data_len = remain_data_len - 128
            remain_data_index = remain_data_index + 128
        else:
            for r in range(1,remain_data_len+1):
                packet[j] = data[k]
                j = j + 1
                k = k + 1
                if r % 4 == 0 :
                    t0 = packet[r - 3]
                    t1 = packet[r - 2]
                    packet[r - 3] = packet[r - 0]
                    packet[r - 2] = packet[r - 1]
                    packet[r - 1] = t1
                    packet[r - 0] = t0
            crc = calc_crc16(packet[0:129])
            packet[CRC0_INDEX] = (crc >> 0) & 0xff
            packet[CRC1_INDEX] = (crc >> 8) & 0xff
            #print(list_to_hex_string(packet))
            serial_write(bytes(packet))
            ack = serial_read(1, 3)
            if (ack != ACK):
                print('NACK2 from slave')
                return
    bin_file.close()


def main():
    if serial_init() == 0:
        send_packets(sys.argv[2]+'.inst.bin',0x00)
        send_packets(sys.argv[2]+'.data.bin',0xFF)
        print('Send successfully...')
    else:
        print('!!! serial init failed !!!')
    serial_print()
    serial_deinit()

if __name__ == "__main__":
    if (len(sys.argv) != 3):
        print('Usage: python ' + sys.argv[0] + ' COMx ' + 'bin_file_name')
    else:
        main()
