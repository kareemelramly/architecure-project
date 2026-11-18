femtoRV32 - 3-Stage Pipelined RISC-V Processor (RV32I + RV32M)
CSCE 3301 Computer Architecture, Fall 2026, Project 1, Milestone 3

Students
- Kareem Abdellatif
- Mohamed Aboelfotouh
- Moustafa Fayed

Overview
A pipelined RV32I processor (plus RV32M) in Verilog with ONE single-ported,
byte-addressable memory for instructions and data. One instruction is issued
every 2 clock cycles (CPI = 2). Each instruction takes 6 cycles in 3 stages
of 2 cycles (C0, C1), as in the project description:

    Stage 0: IF  (C0)  memory read at PC      -> IF_ID  (end of C0)
             ID  (C1)  decode, register read  -> ID_EX  (end of C1)
    Stage 1: EX  (C0)  ALU, branch decision   -> EX_MEM (end of C0)
             MEM (C1)  load / store           -> MEM_WB (end of C1)
    Stage 2: WB  (C0)  register write; C1 unused

The memory serves IF in C0 and MEM in C1 only, so there is no structural
hazard. The register file is written in C0 and read in C1.

Hazards
- Data: the only value not yet in the register file is the one of the
  instruction just before, which is in WB while the consumer is in EX.
  A single MEM_WB -> EX forwarding path handles ALU and load results.
  No stalls at all (load-use included).
- Control: branches and jumps are decided in EX. A taken branch/jump loads
  the target into the PC and flushes the one wrong-path instruction in
  IF_ID (2-cycle penalty). Not-taken branches cost nothing.
- EBREAK halts (the PC is never updated again). ECALL, FENCE, FENCE.TSO and
  PAUSE execute as NOPs.

Bonus claimed
- Bonus 2: RV32M (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU),
  tested by all_instr.s and ALU_tb (37,152 checks against a reference).

Folders
- Verilog/  RTL, testbenches (*_tb.v), const1.xdc, FPGA top
            datapath_board_pipelined.v
- Testing/  programs/ (assembly + hex), compliance/ (official riscv-tests
            rv32ui as hex), run_all.sh, mutation_test.py, results
- Journal/  individual logs
- femtoRV32_MS3_Implementation_Guide.pdf: design, datapath schematic,
  pipeline chart from simulation, every file explained, test results

Run the simulations (Linux or WSL, Icarus Verilog 12)
    cd Verilog
    sh ../Testing/run_all.sh          # 51 runs, prints PASS / FAIL
    python3 ../Testing/mutation_test.py
The .hex images are included, so no RISC-V assembler is needed. To rebuild
them: Testing/programs/build.sh and Testing/compliance/build.sh <riscv-tests/isa>
(need clang, llvm-mc, ld.lld, llvm-objcopy).

Program pass signature: x31 = 00000000 and x30 = 0000C0DE.

Build for the FPGA (Nexys A7-100T, Vivado)
- Add every Verilog/*.v file except *_tb.v, plus defines.vh and const1.xdc.
- Top module: datapath_board_pipelined.
- Choose the program in datapath_board_pipelined.v, parameter PROGRAM_FILE:
  "all_instr", "hazards", "nops_halt" or "demo". These four programs are
  written inside UnifiedMem.v (with the assembly as comments), so no .hex
  file is needed on the board. A .hex path also works.

Board controls
- SW15 reset. BTNC = one CPU clock cycle (the debounced button is the CPU
  clock; there is no free-run mode).
- SW5-SW2 display: 0 PC, 1 instruction in ID, 2 EX result, 3 memory address,
  4 memory data, 5 write-back data, 6 store data.
- SW1-SW0 LEDs: 00 inst[14:0], 10 inst[30:16], 01 pipeline flags.
- LD15 and the decimal points light when EBREAK has halted the CPU.

Release notes - 18 November 2026
What works (simulation)
- 51 / 51 runs pass: 5 unit testbenches, 5 project programs, 40 official
  riscv-tests rv32ui programs, and the board-level testbench.
- pipeline_tb checks every cycle that the memory is written only in C1,
  fetched at the PC in C0, the register file is written only in C0, and
  the PC never moves after EBREAK; timing.s checks the 6-cycle timing.
- Mutation test: 7 / 7 deliberate bugs are caught.
- Yosys synthesis for Xilinx 7-series: no latches, no combinational loops,
  about 10k LUTs; the 1 KB memory maps to LUT RAM.

Assumptions / limitations
- Loads and stores must be aligned (misaligned access is not supported;
  riscv-tests ma_data is skipped). FENCE.I is not required and not tested.
- Memory is 1 KB: code from 0x000, data from 0x300 (ADDR_BITS parameter).
- No traps for illegal instructions. RV32M division is combinational; the
  CPU clock on the board is the BTNC button (one press = one cycle), so
  all_instr needs 292 presses, hazards 196, nops_halt 34, demo 18.
- Not yet done: Vivado bitstream build and board run in this version.
