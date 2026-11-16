#!/bin/sh
# Run from the Verilog/ folder:  sh ../Testing/programs/run_all.sh
# Runs every program in the three pipeline configurations and checks the
# signature x31 = 0 (no failed self-checks), x30 = 0xC0DE (reached the end).
set -e
sh -c 'cd ../Testing/programs && ./build.sh' >/dev/null
SRC=$(ls *.v | grep -v -e _tb -e datapath_board)
for cfg in "1 1" "0 1" "0 0"; do      # BRANCH_IN_ID BP_ENABLE
  set -- $cfg
  for p in all_instr hazards predictor nops_halt; do
    iverilog -g2012 -s programs_tb -Pprograms_tb.BRANCH_IN_ID=$1 -Pprograms_tb.BP=$2 -Pprograms_tb.PROG=\"../Testing/programs/$p.hex\" -o /tmp/prog.out programs_tb.v $SRC
    vvp /tmp/prog.out | grep -E "PASS|FAIL"
  done
done
