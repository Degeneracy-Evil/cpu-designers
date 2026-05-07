import sys

def convert(verilog_hex, output_hex):
    lines = open(verilog_hex).read().strip().split('\n')
    words = []
    for line in lines:
        line = line.strip()
        if line.startswith('@'):
            continue
        bytes_data = line.split()
        for i in range(0, len(bytes_data), 4):
            if i + 3 < len(bytes_data):
                b0 = int(bytes_data[i], 16)
                b1 = int(bytes_data[i+1], 16)
                b2 = int(bytes_data[i+2], 16)
                b3 = int(bytes_data[i+3], 16)
                word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
                words.append(f'{word:08x}')
    with open(output_hex, 'w') as f:
        f.write('\n'.join(words) + '\n')

if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2])
