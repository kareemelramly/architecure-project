#!/bin/sh
# Usage: ./build.sh   (needs llvm-mc, ld.lld, llvm-objcopy, python3)
set -e
cd "$(dirname "$0")"
cat > link.ld <<'LD'
SECTIONS { . = 0x0; .text : { *(.text*) } . = 0x300; .data : { *(.data*) } }
LD
for p in all_instr hazards predictor nops_halt; do
  llvm-mc -triple=riscv32 -mattr=+m -filetype=obj $p.s -o $p.o
  ld.lld -m elf32lriscv -T link.ld $p.o -o $p.elf
  llvm-objcopy -O binary $p.elf $p.bin 2>/dev/null || llvm-objcopy -O binary $p.elf $p.bin
  python3 bin2hex.py $p.bin $p.hex
  echo "$p: $(wc -c < $p.bin) bytes"
  rm -f $p.o $p.elf $p.bin
done
