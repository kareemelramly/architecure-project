#!/usr/bin/env python3
"""Convert a flat binary to a byte-per-line $readmemh file (UnifiedMem is byte addressable)."""
import sys
data = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    for b in data:
        f.write("%02x\n" % b)
