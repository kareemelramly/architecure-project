femtoRV32 - 3-Stage Pipelined RISC-V Processor (RV32I + RV32M)
CSCE 3301 Computer Architecture, Fall 2026, Project 1, Milestone 3

Students

- Kareem Abdellatif
- Mohamed Aboelfotouh
- Moustafa Fayed

Overview

A 32-bit RV32I + RV32M processor in Verilog. One single-ported, byte-addressable
memory holds instructions and data. Every pipeline stage takes one slot of two
cycles: C0 is the fetch cycle, C1 is the data cycle. One instruction issues every
2 cycles (CPI = 2).

    Stage 0: IF (C0) + ID (C1)
    Stage 1: EX (C0) + MEM (C1)
    Stage 2: WB (C0)

Data hazards need no stalls. The instruction directly ahead is forwarded from
MEM_WB to EX, and it can be an ALU result or load data. Older instructions are
already in the register file, which is written at the end of C0 and read in C1.

The parameter BRANCH_IN_ID selects where branches and jumps resolve:
- BRANCH_IN_ID = 1 (default, Bonus 4): branches and jumps resolve in ID, with no
  branch penalty. A load directly before a branch or JALR costs 1 stall slot.
- BRANCH_IN_ID = 0: branches and jumps resolve in EX, and a wrong next PC costs
  1 slot. The BTB + 2-bit BHT predictor (Bonus 3, BP_ENABLE = 1) removes the
  penalty on learned branches.

Bonuses claimed

- Bonus 3: 2-bit saturating-counter branch predictor with a 16-entry BTB.
- Bonus 4: branch and jump resolution in ID, with ID-stage forwarding and stall.
- RV32M (Bonus 2) is also implemented and tested, but it is not claimed.

Folders

- Verilog/: RTL, testbenches, constraints (const1.xdc) and the board top
  (datapath_board_pipelined.v).
- Testing/: test results, the assembly programs in Testing/programs, the
  waveforms in Testing/waveforms, and the mutation test.
- Design/: pipelined block diagram (Pipelined_3Stage_Block_Diagram.svg/png/pdf),
  the MS2 single-cycle diagrams, and the report and waveform scripts.
- Journal/: individual logs.
- report/femtoRV32_MS3_Report.pdf: MS3 report.

Run the simulations (WSL or Linux, Icarus Verilog 12)

cd Verilog
SRC=$(ls *.v | grep -v -e _tb -e datapath_board)
iverilog -g2012 -Wall -Ppipeline_tb.BRANCH_IN_ID=1 -s pipeline_tb -o /tmp/p.out pipeline_tb.v $SRC && vvp /tmp/p.out | tail -3
iverilog -g2012 -Wall -Ppipeline_tb.BRANCH_IN_ID=0 -s pipeline_tb -o /tmp/p.out pipeline_tb.v $SRC && vvp /tmp/p.out | tail -3
iverilog -g2012 -Wall -s unit_tb -o /tmp/u.out unit_tb.v $SRC && vvp /tmp/u.out
iverilog -g2012 -Wall -s datapath_tb -o /tmp/d.out datapath_tb.v $SRC && vvp /tmp/d.out | tail -3
sh ../Testing/programs/run_all.sh      # assembles with llvm-mc / ld.lld / llvm-objcopy

The .hex files are committed, so programs_tb runs without the assembler:
iverilog -g2012 -s programs_tb -Pprograms_tb.PROG=\"../Testing/programs/hazards.hex\" -o /tmp/g.out programs_tb.v $SRC && vvp /tmp/g.out

Build for the FPGA (Nexys A7-100T, Vivado)

Add every Verilog/*.v file except the *_tb.v files, datapath.v,
datapath_board.v, InstMem.v and DataMem.v (those are the MS2 single-cycle design). Add const1.xdc and set datapath_board_pipelined as the top module.
Set the generic PROGRAM_FILE to the absolute path of a Testing/programs/*.hex file
(BRANCH_IN_ID and BP_ENABLE are also generics).

Board controls
- BTNC: step one CPU clock cycle.
- SW15: reset.
- SW6: free run. SW7: fast free run.
- SW0-1: LED view.
- SW2-5: display view (0 PC, 1 next PC, 2 instruction in ID, 3 ALU result,
  4 memory address, 5 memory data, 6 write-back value, 7 store data,
  15 register x[SW8-12]).
- LD15 and the decimal points light when EBREAK halts the CPU.

Program pass signature: x31 = 00000000 and x30 = 0000C0DE.

Release notes - 16 November 2026

What works (simulation)
- pipeline_tb: 160 / 160 checks with BRANCH_IN_ID = 1 and 160 / 160 with
  BRANCH_IN_ID = 0. The predictor-on and predictor-off pipelines end with
  identical state, and both match the single-cycle reference on the MS2 program.
- Assembly programs: all_instr, hazards, predictor and nops_halt pass in 3
  configurations (ID; EX + predictor; EX, no predictor).
- Mutation test: 17 of 18 injected bugs are detected. The surviving mutant is
  equivalent.
- Unit tests and the single-cycle testbench (40 RV32I + 8 RV32M) pass.
- EBREAK halts the CPU. ECALL, FENCE, FENCE.TSO and PAUSE run as NOPs.

Issues encountered and solutions
- ECALL halted the CPU from MS2 on. Now only EBREAK halts, and all tests end
  with EBREAK.
- The first MS3 pipeline had 5 stages. It was converted to the 3-stage
  organization, and every cycle and stall expectation was re-baselined.
- The board top was a copy of the pipeline and used a missing display driver.
  It now instantiates the pipeline and adds an 8-digit hex display, a debounced
  step button and a glitch-free CPU clock.

Known limitations / what is not done
- The bitstream has not been built and the board demonstration has not been
  done. The pins in const1.xdc must be checked against Digilent's master XDC.
- The memory is 1 KB: code below 0x300, data at 0x300. Raise ADDR_BITS in
  UnifiedMem for larger programs.
- There are no traps for misaligned or illegal instructions, and RV32M division
  is combinational.
- Bonus 3 and Bonus 4 cannot both pay off at once in 3 stages: with resolution
  in ID the predictor has nothing to hide. Both are shown through BRANCH_IN_ID.
