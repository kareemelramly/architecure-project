#!/bin/sh
# Runs every femtoRV32 test. Run from the Verilog/ folder:
#     sh ../Testing/run_all.sh
# Needs Icarus Verilog 12 (iverilog, vvp). The .hex images are committed, so
# no RISC-V assembler is needed to run the tests (only to rebuild them with
# Testing/programs/build.sh and Testing/compliance/build.sh).
RTL="ALU.v alu_unit.v BranchUnit.v control_unit.v DFlipFlop.v ForwardingUnit.v
     ImmGen.v mux2x1.v N_bit_register.v Nbit_decoder.v PhaseController.v
     pipeline.v PipelineReg.v RegFile.v UnifiedMem.v"
OUT=/tmp/femtorv32_sim.out

sim() {   # sim <top> <iverilog options...>
  top=$1; shift
  iverilog -g2012 -I. -s "$top" "$@" -o $OUT && vvp -n $OUT
}

echo "== Unit tests"
sim ALU_tb ALU_tb.v ALU.v | grep -E "PASS|FAIL"
sim UnifiedMem_tb UnifiedMem_tb.v UnifiedMem.v | grep -E "PASS|FAIL"

echo "== Full self-checking test (42 RV32I + 8 RV32M, hazards, Bonus 4)"
sim pipeline_tb pipeline_tb.v $RTL | grep -v readmemh

echo "== Board programs and riscv-tests rv32ui against the reference model"
for f in ../Testing/programs/all_instr.hex ../Testing/programs/hazards.hex \
         ../Testing/programs/nops_halt.hex ../Testing/programs/demo.hex \
         ../Testing/compliance/*.hex; do
  r=$(sim pipeline_tb -Ppipeline_tb.VERBOSE=0 -Ppipeline_tb.COVERAGE=0 \
      -Ppipeline_tb.PROG=\"$f\" pipeline_tb.v $RTL 2>/dev/null \
      | grep -E "TEST (PASSED|FAILED)")
  echo "$r  $(basename $f)"
done
