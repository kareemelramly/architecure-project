#!/bin/sh
# Assembles the project test programs into word-per-line hex images.
# Usage: ./build.sh   (needs llvm-mc, ld.lld, llvm-objcopy, python3)
# Code starts at 0x000, data at 0x300 (1 KB unified memory).
set -e
cd "$(dirname "$0")"
for p in all_instr hazards nops_halt demo quick; do
  llvm-mc -triple=riscv32 -mattr=+m,-c -filetype=obj $p.s -o /tmp/$p.o
  ld.lld -m elf32lriscv -T link.ld /tmp/$p.o -o /tmp/$p.elf
  llvm-objcopy -O binary /tmp/$p.elf /tmp/$p.bin
  python3 bin2hex.py /tmp/$p.bin $p.hex
  echo "$p: $(wc -c < /tmp/$p.bin) bytes"
done
# full_test (pipeline_tb): code at 0x0000, data at 0x1000 (8 KB memory)
llvm-mc -triple=riscv32 -mattr=+m,-c -filetype=obj full_test.s -o /tmp/full_test.o
ld.lld -m elf32lriscv -T full_test.ld /tmp/full_test.o -o /tmp/full_test.elf
llvm-objcopy -O binary /tmp/full_test.elf /tmp/full_test.bin
python3 bin2hex.py /tmp/full_test.bin full_test.hex
echo "full_test: $(wc -c < /tmp/full_test.bin) bytes"
