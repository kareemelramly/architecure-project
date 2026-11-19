femtoRV32 - pipelined RISC-V processor (RV32I + RV32M)
CSCE 3301 Computer Architecture, Fall 2026, Project 1, Milestone 3

STUDENTS
  Kareem Abdellatif
  Mohamed AboElfotouh
  Mostafa Fayed

BONUS FEATURES CLAIMED
  Bonus 2: integer multiplication and division (RV32M: MUL, MULH, MULHSU,
           MULHU, DIV, DIVU, REM, REMU)
  Bonus 4: branch/jump outcome and target computed in the ID stage, with
           the resulting data hazards handled (forwarding into ID)
  (Bonus 3, the branch predictor, was started but is NOT part of the final
   design, see "Work distribution".)

SUBMISSION CONTENT
  readme.txt        this file
  report/           femtoRV32_Report.pdf (datapath schematic, implementation,
                    test waveforms, FPGA photos, issues, AI disclosure) and
                    its Overleaf source (main.tex, datapath_fig.tex, figures/)
  journal/          one journal file per team member
  Verilog/          all Verilog descriptions: RTL, FPGA top level
                    (datapath_board_pipelined.v), constraints (const1.xdc),
                    self-checking testbenches (*_tb.v)
  test/             everything used for testing: programs/ (assembly + hex),
                    compliance/ (official riscv-tests rv32ui as hex),
                    run_all.sh, mutation_test.py, wave/ (VCD generation for
                    the waveforms in the report), results/ (simulation
                    outputs), board_*_guide.md (expected values per button
                    press on the FPGA)
  (Some comments inside the Verilog files still call the test folder
   "Testing/"; it is the test/ folder.)

DESIGN
  Single single-ported byte-addressable memory (UnifiedMem.v) for
  instructions and data. One instruction is issued every 2 clock cycles
  (effective CPI = 2). Each instruction takes 6 cycles in 3 stages of 2
  cycles (C0, C1), as in the project description:
      Stage 0  IF (C0)  fetch from the memory         -> IF_ID
               ID (C1)  decode, register read, branch/jump decision
      Stage 1  EX (C0)  ALU                           -> EX_MEM
               MEM (C1) load / store
      Stage 2  WB (C0)  register file write; C1 unused
  The memory port is used by IF in C0 and by MEM in C1 only, so there is
  never a structural hazard. PhaseController.v toggles C0/C1; the pipeline
  registers load on the enables isC0/isC1 of one single clock.
  Hazards:
   - Data: when an instruction is in ID, the one before it is in MEM and the
     one before that was written back in the previous C0. ForwardingUnit.v
     (in ID) takes the value of the instruction in MEM from EX_MEM, or from
     the memory output when that instruction is a load. Values two
     instructions old come from the register file (written in C0, read in
     C1). No stalls at all, including load-use.
   - Control (Bonus 4): branches, JAL and JALR are decided in ID (C1). The
     PC loads the target at the end of that C1 and the next fetch (next C0)
     is already the right one: 0 cycles lost, no wrong-path instruction
     is ever fetched.
  EBREAK halts (PC never updated again, older instructions finish). ECALL,
  FENCE, FENCE.TSO and PAUSE are NOPs.

HOW TO RUN THE SIMULATIONS (Icarus Verilog 12, Linux or WSL)
    cd Verilog
    sh ../test/run_all.sh                 # unit tests, full test, 4 board
                                          # programs, 40 riscv-tests rv32ui
    python3 ../test/mutation_test.py      # 8 deliberate bugs must be caught
    cd ../test/wave && sh make_waves.sh   # VCD files for GTKWave
  Vivado: set pipeline_tb as the simulation top (built-in program, no file
  path, finishes at 485 ns, so the default 1000 ns run is enough).
  The .hex files are included, no RISC-V assembler is needed.
  Program pass signature: x31 = 0 and x30 = 0x0000C0DE.

HOW TO BUILD FOR THE FPGA (Nexys A7-100T, Vivado)
  Add every Verilog/*.v file except *_tb.v, plus defines.vh and const1.xdc.
  Top module: datapath_board_pipelined. Choose the program with the
  parameter PROGRAM_FILE (built into UnifiedMem.v): "quick" (default: every
  instruction once, halts at press 112), "all_instr", "demo", "hazards",
  "nops_halt".
  Controls: SW15 = reset (up = reset). BTNC = one CPU clock cycle (the
  debounced button is the clock, step mode only). SW0 = LED view
  (down: instruction bits 14..0, up: bits 30..16). SW3 SW2 SW1 = 8-digit
  decimal display: 000 PC, 001 instruction in ID, 010 EX result, 011 memory
  address, 100 memory data, 101 store data, 110 write-back data, 111
  write-back register. LD15 and all decimal points = halted (EBREAK).
  Expected value for every press: test/board_quick_guide.md,
  board_all_instr_guide.md, board_demo_guide.md.

WORK DISTRIBUTION (times are GitHub commit times, Cairo time)
  Kareem Abdellatif: UnifiedMem.v (single-ported byte-addressable memory),
    PhaseController.v (C0/C1, one instruction every 2 cycles), PipelineReg.v
    and the pipeline registers, BranchPredictor.v (Bonus 3 draft with BTB and
    2-bit counters). Nov 13 11:07 PM first pipeline (b9e6d04); Nov 16 1:45 PM
    3-stage conversion (7b8f46f).
  Mohamed AboElfotouh: Bonus 4. Branch/jump decision and target adders moved
    from EX to ID, ForwardingUnit.v for the ID stage, HazardUnit.v draft for
    branch stalls, datapath re-wiring. Nov 13 11:48 PM (f699ea8). Earlier
    work: branch/jump instructions, ALU unit, x0 handling, division by zero,
    coding-guideline refactor (Oct 27 to Nov 2).
  Mostafa Fayed: FPGA top level datapath_board_pipelined.v, I/O mapping
    const1.xdc, hazard and branch test programs. Nov 14 2:15 PM updated top
    module and testbench (ebfce75); Nov 18 4:43 PM reviewed and modified the
    pipeline top module, 4:48 and 4:50 PM updated log and pipeline file
    (ccd5f6f, 82386ab). Earlier work: XOR, shifts, I-type instructions, RV32M
    in the ALU (Oct 28 to Nov 2).
  Whole team: all work of 18 November (commits 04aee0e to fda933f, 10:23 AM
    to 4:27 PM: memory update, board clean-up, bonus features, renaming,
    testbench, hazard handling) was done by all three members and pushed from
    Kareem's GitHub account.
  Bonus 3 (predictor) and HazardUnit.v: written as drafts on Nov 13, removed
  from the final design. With the branch resolved in ID there is no
  misprediction penalty to remove and the pipeline never stalls, so neither
  module changes any result. The final design keeps only the ID-stage
  forwarding unit.

RELEASE NOTES - 19 November 2026
 What works
  - All 42 RV32I instructions plus the 8 RV32M instructions (simulation).
  - pipeline_tb.v (self-checking, reference RV32IM model inside the
    testbench): 238 of 238 instructions checked, 0 errors, TEST PASSED.
    Checks every instruction's PC, write-back value and timing (6 cycles),
    stores, forwarding on every RAW hazard, an instruction entering ID every
    2 cycles (no stalls), final registers and memory, coverage 42/42 RV32I
    and 8/8 RV32M.
  - Programs quick, all_instr, demo, hazards, nops_halt and the 40 official
    riscv-tests rv32ui programs: all TEST PASSED. ALU_tb 37152 checks,
    UnifiedMem_tb pass. Mutation test: 8 / 8 bugs caught.
  - FPGA: the design was run on the Nexys A7-100T and stepped with BTNC; the
    report shows four photos of the display (values 12, 5, 2, 17 = presses
    4, 6, 8, 10 of the quick program). Expected values per press are in the
    three board guides.
 Assumptions and limitations
  - Loads and stores must be aligned (no misaligned access); the riscv-tests
    ma_data test is not run. FENCE.I is not supported or tested.
  - Memory is 1 KB: code from 0x000, data from 0x300 (ADDR_BITS parameter).
  - No traps and no CSRs: illegal instructions are not detected.
  - Division and multiplication are combinational (one ALU operation in EX).
  - The CPU clock on the board is the BTNC button (step mode only), so
    nothing about 100 MHz timing is claimed; the programs need 112 (quick),
    294 (all_instr), 26 (demo) button presses to halt.
  - Display values above 99,999,999 show as "--------"; read instruction
    words on the LEDs.
 What does not work / not done
  - Bonus 3 (branch predictor) is not implemented in the final design.
  - A free-running clock mode on the board was removed (CpuClockGen).
 Issues met
  - The first pipelined version resolved branches in EX (2-cycle penalty) and
    had a hazard unit with stalls; moving the decision to ID and forwarding
    into ID removed both. Details in the report.
