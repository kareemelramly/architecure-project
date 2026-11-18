#!/bin/sh
# Builds the official riscv-tests rv32ui programs into word-per-line hex
# images for femtoRV32. Usage: ./build.sh <path to riscv-tests/isa>
# Needs clang, llvm-mc, ld.lld, llvm-objcopy and python3.
# Skipped: fence_i (FENCE.I is not one of the 42 instructions) and ma_data
# (misaligned loads/stores; the memory needs aligned accesses).
set -e
T=${1:-../../../riscv-tests/isa}
cd "$(dirname "$0")"
for f in "$T"/rv32ui/*.S; do
  t=$(basename "$f" .S)
  [ "$t" = fence_i ] && continue   # FENCE.I is not required
  [ "$t" = ma_data ] && continue   # misaligned access is not supported
  clang --target=riscv32 -march=rv32i -E -P -x assembler-with-cpp \
        -I. -I"$T/macros/scalar" -I"$T/rv32ui" "$f" -o "/tmp/$t.s"
  llvm-mc -triple=riscv32 -mattr=-c -filetype=obj "/tmp/$t.s" -o "/tmp/$t.o"
  ld.lld -m elf32lriscv -T link.ld "/tmp/$t.o" -o "/tmp/$t.elf"
  llvm-objcopy -O binary "/tmp/$t.elf" "/tmp/$t.bin"
  python3 ../programs/bin2hex.py "/tmp/$t.bin" "$t.hex"
  echo "$t: $(wc -c < /tmp/$t.bin) bytes"
done
