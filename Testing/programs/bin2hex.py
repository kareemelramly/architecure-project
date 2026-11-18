#!/usr/bin/env python3
"""Convert a flat binary into a $readmemh image for UnifiedMem: one 32-bit
little-endian word per line (word 0 = bytes 0..3). Pads to a whole word.
Usage: python3 bin2hex.py program.bin program.hex"""
import sys

data = open(sys.argv[1], "rb").read()
data += b"\0" * (-len(data) % 4)
with open(sys.argv[2], "w") as f:
    for i in range(0, len(data), 4):
        f.write("%08x\n" % int.from_bytes(data[i:i + 4], "little"))
