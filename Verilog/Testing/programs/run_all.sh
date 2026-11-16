#!/bin/sh
# Run from the Verilog/ folder:  sh Testing/programs/run_all.sh
set -e
sh -c 'cd Testing/programs && ./build.sh' >/dev/null
SRC=$(ls *.v | grep -v -e _tb -e datapath_board)
for bp in 1 0; do
  for p in all_instr hazards predictor nops_halt; do
    iverilog -g2012 -s programs_tb -Pprograms_tb.BP=$bp -Pprograms_tb.PROG=\"Testing/programs/$p.hex\" -o /tmp/prog.out programs_tb.v $SRC
    vvp /tmp/prog.out | grep -E "PASS|FAIL"
  done
done
