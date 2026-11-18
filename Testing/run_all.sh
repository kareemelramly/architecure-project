#!/bin/sh
# Runs every femtoRV32 test. Run from the Verilog/ folder:
#     sh ../Testing/run_all.sh
# Needs Icarus Verilog 12 (iverilog, vvp). The .hex images are committed, so
# no RISC-V assembler is needed to run the tests (only to rebuild them with
# Testing/programs/build.sh and Testing/compliance/build.sh).
RTL="ALU.v alu_unit.v BranchUnit.v control_unit.v DFlipFlop.v ForwardingUnit.v
     ImmGen.v mux2x1.v N_bit_register.v Nbit_decoder.v PhaseController.v
     pipeline.v PipelineReg.v RegFile.v UnifiedMem.v"
BOARD="Debounce.v SevenSegHex8.v datapath_board_pipelined.v"
OUT=/tmp/femtorv32_sim.out

sim() {   # sim <top> <iverilog options...>
  top=$1; shift
  iverilog -g2012 -I. -s "$top" "$@" -o $OUT && vvp -n $OUT | grep -E "PASS|FAIL"
}

echo "== Unit tests"
for t in ALU UnifiedMem ForwardingUnit PhaseController PipelineReg; do
  sim ${t}_tb ${t}_tb.v $RTL
done

echo "== Project programs (1 KB memory, same images as the FPGA)"
for p in all_instr hazards nops_halt demo; do
  sim pipeline_tb -Ppipeline_tb.PROG=\"../Testing/programs/$p.hex\" \
      pipeline_tb.v $RTL
done
sim pipeline_tb -Ppipeline_tb.CHECK_TIMING=1 \
    -Ppipeline_tb.PROG=\"../Testing/programs/timing.hex\" pipeline_tb.v $RTL

echo "== Official riscv-tests rv32ui (8 KB memory)"
for f in ../Testing/compliance/*.hex; do
  sim pipeline_tb -Ppipeline_tb.ADDR_BITS=13 -Ppipeline_tb.PROG=\"$f\" \
      pipeline_tb.v $RTL
done

echo "== Board top (step mode with a bouncing button, display)"
sim datapath_board_pipelined_tb datapath_board_pipelined_tb.v $RTL $BOARD
