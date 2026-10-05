#!/usr/bin/env python3
import sys

def bin2hex(bin_path, hex_path, pad_to_words=0):
    with open(bin_path, 'rb') as f:
        data = f.read()

    # Pad data to multiple of 4 bytes
    rem = len(data) % 4
    if rem != 0:
        data += b'\x00' * (4 - rem)

    words = []
    for i in range(0, len(data), 4):
        w = data[i] | (data[i+1] << 8) | (data[i+2] << 16) | (data[i+3] << 24)
        words.append(f"{w:08x}\n")

    while len(words) < pad_to_words:
        words.append("00000013\n") # NOP

    with open(hex_path, 'w') as f:
        f.writelines(words)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: bin2hex.py <input.bin> <output.hex> [pad_to_words]")
        sys.exit(1)
    pad = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    bin2hex(sys.argv[1], sys.argv[2], pad)
