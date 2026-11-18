```
femtoRV32 - 5-Stage Pipelined RISC-V Processor (RV32I + RV32M)
CSCE 3301 Computer Architecture, Fall 2026, Project 1, Milestone 3

Students

- Kareem Abdellatif
- Mohamed Aboelfotouh
- Moustafa Fayed

Overview

A 32-bit RV32I + RV32M processor in Verilog with a 5-stage pipeline (IF, ID, EX,
MEM, WB). One single-ported, byte-addressable memory holds instructions and data,
so fetch and data access cannot share a cycle. Every pipeline stage therefore
takes one slot of two cycles: C0 is the fetch cycle, C1 is the data cycle. One
instruction issues every 2 cycles (CPI = 2, a stall every second cycle).

    IF  : memory read at PC in C0, predictor lookup
    ID  : decode, register read, branch / jump resolution (Bonus 4)
    EX  : forwarding, ALU
    MEM : load / store through the shared memory port in C1
    WB  : register file write at the end of C0

Hazards:
- ALU results are forwarded from EX_MEM and MEM_WB to EX: 0 stalls.
- A load directly before its consumer costs 1 stall slot (load-use).
- Branches and jumps resolve in ID with forwarding from EX_MEM. A branch or JALR
  waits 1 slot for an ALU result still in EX and 2 slots for a load.
- A wrong next PC flushes IF_ID and costs 1 slot. The BTB + 2-bit BHT predictor
  (Bonus 3, BP_ENABLE = 1) removes this penalty on learned branches.

Bonuses claimed

- Bonus 3: 2-bit saturating-counter branch predictor with a 16-entry BTB.
- Bonus 4: branch and jump resolution in ID, with ID-stage forwarding and stall.
- RV32M (Bonus 2) is also implemented and tested, but it is not claimed.

Folders

- Verilog/: RTL, testbenches, constraints (const1.xdc) and the board top
  (datapath_board_pipelined.v).
- Testing/: test results, the assembly programs in Testing/programs, the
  waveforms in Testing/waveforms, and the mutation test.
- Design/: pipelined block diagram (Pipelined_5Stage_Block_Diagram.svg/png/pdf),
  the MS2 single-cycle diagrams, and the report and waveform scripts.
- Journal/: individual logs.
- report/femtoRV32_MS3_Report.pdf: MS3 report.

Run the simulations (WSL or Linux, Icarus Verilog 12)

cd Verilog
SRC=$(ls *.v | grep -v -e _tb -e datapath_board)
iverilog -g2012 -Wall -s pipeline_tb -o /tmp/p.out pipeline_tb.v $SRC && vvp /tmp/p.out | tail -3
iverilog -g2012 -Wall -s unit_tb -o /tmp/u.out unit_tb.v $SRC && vvp /tmp/u.out
iverilog -g2012 -Wall -s datapath_tb -o /tmp/d.out datapath_tb.v $SRC && vvp /tmp/d.out | tail -3
sh ../Testing/programs/run_all.sh      # assembles with llvm-mc / ld.lld / llvm-objcopy

The .hex files are committed, so programs_tb runs without the assembler:
iverilog -g2012 -s programs_tb -Pprograms_tb.PROG=\"../Testing/programs/hazards.hex\" -o /tmp/g.out programs_tb.v $SRC && vvp /tmp/g.out

Build for the FPGA (Nexys A7-100T, Vivado)

Add every Verilog/*.v file except the *_tb.v files, datapath.v,
datapath_board.v, InstMem.v and DataMem.v (those are the MS2 single-cycle design). Add const1.xdc and set datapath_board_pipelined as the top module.
Set the generic PROGRAM_FILE to the absolute path of a Testing/programs/*.hex file
(BP_ENABLE is also a generic).

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
- pipeline_tb: 160 / 160 checks. The predictor-on and predictor-off pipelines end
  with identical state, and both match the single-cycle reference on the MS2
  program.
- Assembly programs: all_instr, hazards, predictor and nops_halt pass with the
  predictor on and off (8 runs).
- Mutation test: see Testing/mutation_result.txt.
- Unit tests and the single-cycle testbench (40 RV32I + 8 RV32M) pass.
- EBREAK halts the CPU. ECALL, FENCE, FENCE.TSO and PAUSE run as NOPs.

Issues encountered and solutions
- ECALL halted the CPU from MS2 on. Now only EBREAK halts, and all tests end
  with EBREAK.
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
- The ID stage holds a register read, a comparator and an adder in series, which
  may limit the clock frequency on the board.

```
