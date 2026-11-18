#!/bin/sh
# Assembles the project test programs into word-per-line hex images.
# Usage: ./build.sh   (needs llvm-mc, ld.lld, llvm-objcopy, python3)
# Code starts at 0x000, data at 0x300 (1 KB unified memory).
set -e
cd "$(dirname "$0")"
for p in all_instr hazards nops_halt timing demo; do
  llvm-mc -triple=riscv32 -mattr=+m,-c -filetype=obj $p.s -o /tmp/$p.o
  ld.lld -m elf32lriscv -T link.ld /tmp/$p.o -o /tmp/$p.elf
  llvm-objcopy -O binary /tmp/$p.elf /tmp/$p.bin
  python3 bin2hex.py /tmp/$p.bin $p.hex
  echo "$p: $(wc -c < /tmp/$p.bin) bytes"
done
