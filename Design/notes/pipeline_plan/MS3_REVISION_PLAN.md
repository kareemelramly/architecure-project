# femtoRV32 MS3: Verification of Mostafa's Part and Spec Compliance Revision Plan

Checked against: `Project1Description_1.pdf` (Fall 2026) and the repo after the pull of Nov 14 (Mostafa's commit: `datapath_board_pipelined.v`, `pipeline_tb.v` Tests 20 to 22, journal).

## 0. Bottom line

1. **Simulation is solid.** The pulled `pipeline_tb` passes 149/149 in Icarus 12. Mostafa's predictor and hazard suites are well designed and they pass.
2. **The FPGA side does not build.** `datapath_board_pipelined` fails elaboration because `Four_Digit_Seven_Segment_Driver_Optimized` is not in the repo. The old `datapath_board.v` is fully commented out, so this path has never been synthesized. The board also has no program to run (memory holds 4 instructions and no halt).
3. **One spec violation exists since MS2, independent of the pipeline:** `control_unit` halts on **ECALL** as well as EBREAK. The spec says only EBREAK halts; ECALL, PAUSE, FENCE, FENCE.TSO are NOPs. Every testbench ends its programs with ECALL, so they all change.
4. **3 stages vs 5 stages.** The spec describes the CPI = 2 solution as 3 stages of 2 cycles (Stage 0 = IF C0 + ID C1, Stage 1 = EX C0 + MEM C1, Stage 2 = WB C0). The current design issues every 2 cycles (CPI = 2 is met) but uses 5 stages (10-cycle latency). The text frames the 3-stage organization as "one solution", so 5 stages is arguably legal, but the grader will compare against that figure. Recommendation: convert to 3 stages (Section 3). It is mostly deletions, and it removes the load-use stall entirely.
5. **Deadline.** MS3 is due today (Mon Nov 16). Late = -5% for one day. Do the P0 items in Section 4 first on the current design, commit, so a valid submission exists at every point. Do the 3-stage conversion on a branch and merge only if all tests pass.

Confidence: high on items 1 to 3 (reproduced). Medium on how the grader treats 5 stages (ask the TA today; one message settles it). The 3-stage numbers in Section 3 are derived by hand, not simulated; they are marked.

---

## 1. Verification of Mostafa's part

| Task | Status | Evidence | Problems |
| --- | --- | --- | --- |
| FPGA wrapper `datapath_board_pipelined.v` | **Fails to build** | `iverilog -s datapath_board_pipelined`: *Unknown module type: Four_Digit_Seven_Segment_Driver_Optimized* | (a) Driver module missing from repo. (b) The file is a 470-line copy of `pipeline.v` instead of an instance of it, so every fix to `pipeline.v` (ECALL, 3-stage) must be done twice and will drift. (c) Header says `Module: UnifiedMem.v`, typo "preious", header placed after `timescale` (coding-guideline risk). |
| I/O mapping `const1.xdc` | **Unchanged since MS2** (file date Nov 2) | Pins checked against Nexys A7: switches, LEDs, segments, AN0-3, E3 clock are correct, and port names match the new top. | (a) CPU clock is switch SW14 (U11) with no debounce: one flip can give several edges, and each instruction needs 2 clean edges (C0, C1). (b) Only AN0-AN3 driven; AN4-AN7 unconstrained, so those 4 digits show garbage. (c) SSD shows only 13 bits; no way to read a register's final value on the board. |
| Bonus validation suite (Test 20) | **Passes** | Branch B walks `10,11,11,10,01,00,00,01,10,11,11,10,11`: reaches 00 (SNT), saturates, returns to 11 (ST). Inner loop shows `10,11,11,10` then `11,11,11,10`. 15 mispredicts BP on vs 35 BP off. | Written as Verilog-encoded instructions inside the testbench, not as a RISC-V assembly program. Cannot run on the FPGA. Ends with ECALL. |
| Hazard validation suite (Tests 21, 22) | **Passes** | 15 add/lw-before-branch cases x 3 passes (cold and warm predictor), stale-value design (a wrong value flips the branch so a bug is visible), 42 stalls, 0 fail marks. | Same assembly/FPGA gap. Test 22 prints the stall count instead of asserting it (should assert 0). Comments on cases 4 and 11 say "MEM/WB forward"; in this design distance 3 is served by the register file (written in C0). |

Verdict: the validation logic is good and should be kept as is; it needs to be moved into real `.s` programs that run on both the simulator and the board (Section 5). The board top and XDC need rework before any FPGA proof is possible.

---

## 2. Spec compliance audit (whole project)

| # | Spec requirement | Status | Action |
| --- | --- | --- | --- |
| R1a | RV32I, 42 instructions | All 42 decoded. MS2 program covers 41/42 (no EBREAK). | Add EBREAK as the final instruction. |
| R1b | EBREAK halts, ECALL/PAUSE/FENCE/FENCE.TSO are NOPs | **ECALL halts** (`control_unit` ignores `inst[20]`). FENCE/PAUSE are NOPs (correct). | Fix decode: halt only when `inst[31:20] == 12'h001` (plus rs1, funct3, rd = 0). Fix applies to single-cycle and pipeline (shared module). |
| R2 | Pipelined, correct hazard handling | Met (5 stages). | 3-stage conversion recommended (Section 3). |
| R3 | One memory, single-ported, byte-addressable, issue every 2 cycles | Met (`UnifiedMem`, C0/C1). | None. |
| R4 | Tests for all instructions and all hazards | Simulation: yes. FPGA: none. | FPGA programs (Section 5). |
| D1 | MS3: pipelined datapath block diagram | Only the single-cycle schematic exists in `Design/`. | Draw the 3-stage (or 5-stage) pipelined diagram. |
| D2 | Report with FPGA proof covering all 42 instructions and hazards | Report is the MS2 one. | New report (Section 7). |
| D3 | Zip structure: readme.txt, journal folder, Verilog folder, test folder, PDF report | Extra folders (`tmp/`, `pipeline_plan/`), generated files in `Verilog/` (`pipeline.vcd` 11 MB, `simulation.out`, `.dot`). | Clean up (Section 7). -5% risk. |
| D4 | Journals | Kareem's and Mohamed's logs not updated since Nov 2. | Each member adds MS3 entries. |
| D5 | Coding guidelines (separate document) | Not available to me. Known risks: board header, `datapath_board.v` Vivado template header and commented-out body. | Check every file against the guideline document. |
| B | Max 2 bonuses count | Three exist: RV32M (Bonus 2), predictor (Bonus 3), ID resolution (Bonus 4). | State clearly in the report which 2 you claim (Section 3.5). |

---

## 3. The 3-stage issue

### 3.1 What the spec describes

| Slot (2 cycles) | C0 | C1 |
| --- | --- | --- |
| Stage 0 | IF (memory port: fetch at PC) | ID (decode, register read) |
| Stage 1 | EX (ALU) | MEM (memory port: load/store) |
| Stage 2 | WB (register write) | unused |

Memory port: C0 always fetch, C1 always data. This is exactly what `PhaseController`, `UnifiedMem`, and the memory mux already do. Only the register boundaries change.

### 3.2 Register map: current 5-stage vs 3-stage

| Element | Now | 3-stage | Loads at |
| --- | --- | --- | --- |
| PC | PC | PC | end of C1 (`advance`) |
| `instLatch` | holds fetch until IF_ID | **is** the IF to ID boundary inside Stage 0 | end of C0 (`isFetch`) |
| `IF_ID` | pipeline register | **deleted** (ID uses `instLatch` and `pcValue`, both stable in C1) | n/a |
| `ID_EX` | pipeline register | Stage 0 to Stage 1 register | end of C1 |
| `EX_MEM` | pipeline register | intra-stage latch inside Stage 1 (EX in C0, MEM in C1) | **end of C0** (`isFetch`) |
| `MEM_WB` | pipeline register | Stage 1 to Stage 2 register | end of C1 |
| RegFile write | end of C0 | end of C0 (unchanged) | |

Keep the names `ID_EX`, `EX_MEM`, `MEM_WB` so the testbench hierarchical paths mostly survive. The `EX_MEM` latch is optional in theory (EX outputs are stable through C1), but keep it: the spec puts ALU in C0 and memory in C1, and it keeps ALU plus memory out of one cycle.

### 3.3 Hazards in the 3-stage design (derived, not simulated)

Key fact: the instruction one ahead is in Stage 2 when you are in EX, and its value sits in `MEM_WB` (ALU result **or** load data). The instruction two ahead has already written the register file at the end of C0 before your ID read in C1.

| Case | 5-stage now | 3-stage, branch in EX (base) | 3-stage, branch in ID (Bonus 4) |
| --- | --- | --- | --- |
| ALU to ALU, distance 1 | forward EX_MEM | forward MEM_WB | forward MEM_WB |
| **load to ALU, distance 1** | 1 stall | **0 stalls** (forward MEM_WB load data) | 0 stalls |
| anything, distance 2+ | forward / regfile | register file | register file |
| ALU to branch, distance 1 | 1 stall | 0 (EX uses forwarded operands) | 0 (forward `EX_MEM_Result`, valid during C1) |
| load to branch, distance 1 | 2 stalls | 0 | **1 stall** (data arrives in the same C1) |
| load to branch, distance 2 | 1 stall | 0 | 0 |
| mispredict penalty | 1 slot | 1 slot, 0 if predicted right | **0** (next fetch is after resolution) |
| straight-line halt time | 2(N+2) cycles | 2(N+1) | 2(N+1) |

Consequences:
- EX forwarding has one source (`MEM_WB`). `ForwardingUnit` is reused with `exMemRegWrite` tied to 0, or simplified.
- In base mode there are no stalls at all. `HazardUnit` is needed only for Bonus 4 and reduces to one rule: `stall = readsInId & ID_EX_MemRead & (ID_EX_Rd != 0) & (ID_EX_Rd matches rs1/rs2)`.
- A stall needs no special hold of the fetched instruction: PC does not advance, so the next C0 refetches the same word.
- Base-mode mispredict: flush `ID_EX` at the end of C1 (the Stage 0 instruction is wrong path) and load PC with the resolved target. EBREAK in Stage 0 must not halt if the Stage 1 branch redirects (`haltSet & ~redirect`, as in the old EX version).
- ID-mode redirect: PC loads the resolved target at the end of C1. Nothing to flush.

### 3.4 Bonus 3 and Bonus 4 conflict in 3 stages

With branches resolved in ID (C1 of Stage 0), the next fetch happens after the outcome is known, so the predictor has nothing to predict. Penalty is 0 with or without it. Bonus 3 only shows a benefit when branches resolve in EX.

Recommended structure: one parameter `BRANCH_IN_ID` (0 or 1) plus the existing `BP_ENABLE`.

| Config | What it demonstrates |
| --- | --- |
| `BRANCH_IN_ID=0, BP_ENABLE=0` | spec baseline (1-slot penalty per taken branch) |
| `BRANCH_IN_ID=0, BP_ENABLE=1` | Bonus 3: predictor removes the penalty on learned branches |
| `BRANCH_IN_ID=1` | Bonus 4: zero penalty, load-to-branch stall, ID forwarding |

All three must end with identical architectural state; the testbench already has the twin-comparison machinery.

### 3.5 Which 2 bonuses to claim

Recommendation: claim **Bonus 3 and Bonus 4** (the pipeline bonuses, both tested, both demonstrable via the parameter), and list RV32M as an extra implemented feature. If the team prefers the safer pair, claim RV32M + Bonus 4. This decides the report structure, so settle it now.

### 3.6 If you keep 5 stages instead

Write one report paragraph: issue rate is one instruction per 2 cycles (CPI = 2), memory use C0 = fetch, C1 = data, identical to the suggested solution; the 5-stage organization is a design choice that gives 10-cycle latency instead of 6, at the cost of a load-use stall the 3-stage design does not need. Quote the CPI table. Everything else in this plan still applies.

---

## 4. Update list (priority order)

### P0: correctness and buildability (needed whichever pipeline you ship)

| # | Change | Files | Owner |
| --- | --- | --- | --- |
| 1 | EBREAK-only halt; ECALL is a NOP | `control_unit.v` | Kareem |
| 2 | Replace ECALL with EBREAK as terminator in all tests (32 uses in `pipeline_tb.v`, Test 8 becomes "wrong-path EBREAK", MS2 program: keep ECALL at `mem[117]` as a NOP test, add EBREAK after it) | `pipeline_tb.v`, `InstMem.v`, `datapath_tb.v` | Mostafa |
| 3 | New test: ECALL, FENCE, FENCE.TSO (`0x8330000F`), PAUSE (`0x0100000F`) execute as NOPs between dependent instructions; only EBREAK stops the PC | `pipeline_tb.v` | Mostafa |
| 4 | `pipeline` gets debug ports: `dbgRegSel[4:0]` in; `dbgRegData`, `dbgPC`, `dbgInst`, `dbgFlags[15:0]`, `dbgHalt` out. RegFile gets a third, debug-only read port (unconnected in `datapath.v`) | `pipeline.v`, `RegFile.v` | Kareem |
| 5 | Board top **instantiates** `pipeline` and only does muxing and display. Delete the copied datapath. Fix header. | `datapath_board_pipelined.v` | Mostafa |
| 6 | Add the seven-segment driver to the repo. Recommended: a new 8-digit hex driver (`SevenSegHex8.v`) showing full 32-bit values, instead of the 4-digit 13-bit lab driver. | new file | Mostafa |
| 7 | Debounced single-step clock on BTNC, reset on a switch, register viewer on switches, all 8 anodes driven (Section 6) | `const1.xdc`, board top, new `Debounce.v` | Mostafa |
| 8 | `UnifiedMem` loads its image with `$readmemh` from a hex file chosen by a parameter, so the same program runs in simulation and on the board | `UnifiedMem.v` | Kareem |
| 9 | Test 22: assert stall count = 0 instead of printing it; fix the two misleading comments | `pipeline_tb.v` | Mostafa |

### P1: spec structure

| # | Change | Owner |
| --- | --- | --- |
| 10 | 3-stage conversion per Section 3 (on a branch), with `BRANCH_IN_ID` parameter | Kareem (datapath), Mohamed (hazard/branch logic) |
| 11 | Re-baseline cycle/stall/mispredict expectations in Tests 1-22 for the 3-stage numbers. Register and memory checks stay unchanged. Tests 12-19 and 21 run in `BRANCH_IN_ID=1`; Test 20 and the predictor parts of 6, 7, 18 run in `BRANCH_IN_ID=0`. | Mohamed, Mostafa |
| 12 | `HazardUnit` reduced to the load-to-branch rule; its unit tests updated | Mohamed |

### P2: deliverables

Sections 5 to 7.

---

## 5. Test programs as real assembly (sim and FPGA)

Spec asks for "a targeted RISC-V assembly program". Turn Mostafa's suites into `.s` files so the same binary runs in `pipeline_tb` and on the board.

Folder: `Testing/programs/`

| Program | Content | Pass signature |
| --- | --- | --- |
| `all_instr.s` | every RV32I instruction + RV32M, self-checking (`bne got, expected, fail`) | `x31 = 0` and `x30 = 0xC0DE` |
| `hazards.s` | Test 21 cases (add/lw directly before branches, both outcomes), Test 22, EX forwarding cases, store-after-load | same |
| `predictor.s` | Test 20 data-driven branch B + nested loops; writes mispredict-sensitive counters to registers | same, plus counts in x20 to x23 |
| `nops_halt.s` | ECALL, FENCE, FENCE.TSO, PAUSE as NOPs, then EBREAK | same |

Layout rules: `.text` at 0x000, `.data` at 0x200, every program ends with `ebreak`.

Build (WSL):

```bash
sudo apt install gcc-riscv64-unknown-elf
riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 -o p.o hazards.s
riscv64-unknown-elf-ld -m elf32lriscv -Ttext=0x0 --section-start=.data=0x200 -o p.elf p.o
riscv64-unknown-elf-objcopy -O binary --pad-to=0x400 p.elf p.bin
python3 bin2hex.py p.bin > hazards.hex      # one byte per line, 1024 lines
```

`bin2hex.py` is a 5-line script. RARS or Venus can replace the toolchain if WSL install fails.

Testbench: add a task that does `$readmemh` into `dut.memory.mem` (all configs) and checks `x31 == 0` and `x30 == 0xC0DE` after halt. The existing directed tests stay; these four become the FPGA-proof tests.

---

## 6. FPGA plan (Nexys A7)

Proposed mapping. Verify every pin and IOSTANDARD against Digilent's `Nexys-A7-100T-Master.xdc` before building; SW8 (T8) and SW9 (U8) are on a 1.8 V bank and need `LVCMOS18`.

| Signal | Board | Pin |
| --- | --- | --- |
| `sysClk` (debouncer, SSD refresh) | 100 MHz | E3 |
| `stepBtn` (debounced, one press = one CPU clock edge) | BTNC | N17 |
| `reset` | SW15 | V10 |
| `runMode` (optional slow free-running clock, about 4 Hz) | SW14 | U11 |
| `ledSel[1:0]` | SW0-1 | J15, L16 |
| `ssdSel[3:0]` | SW2-5 | M13, R15, R17, T18 |
| `regSel[4:0]` (register viewer, used when `ssdSel = 15`) | SW6-10 | U18, R13, T8, U8, R16 |
| `Anode[7:0]` | AN0-7 | J17, J18, T9, J14, P14, T14, K2, U13 |
| `LED_out[6:0]` | CA-CG | T10, R10, K16, K13, P15, T11, L18 |
| `leds[15:0]` | LD0-15 | unchanged |

Display contents: `ssdSel` 0 PC, 1 instruction in ID, 2 ALU result, 3 memory data out, 4 write-back value, ..., 15 `x[regSel]`. LEDs: keep Mostafa's three views; put `dbgHalt` on LD15 in every view.

Demo script for each program: load the bitstream built with that hex file, set `runMode` on, wait for LD15 (halt), switch `regSel` to 31 and 30, photograph the display. That photo series is the FPGA proof the spec asks for. One bitstream per program (four builds), or a parameterized ROM select if time allows.

Clock note: the button as a clock needs `CLOCK_DEDICATED_ROUTE FALSE` (already present). It works at these speeds; mention in the report that a clock-enable scheme would be the production approach.

---

## 7. Report, readme, folder checklist

Report (new PDF, MS3):
1. Pipelined datapath block diagram (the 3-stage figure with C0/C1 annotations, memory mux, forwarding paths, hazard unit, predictor).
2. C0/C1 timing table and how the structural hazard is removed.
3. Hazard handling table (Section 3.3, with your simulated numbers).
4. Bonus sections for the two claimed bonuses, with the CPI/mispredict table from the three configurations.
5. Test strategy: directed testbench (number of checks), assembly programs, mutation testing (list the injected bugs and that each was caught).
6. Waveforms: one load-to-branch stall, one mispredict squash (EX mode), one predicted branch, one EBREAK halt.
7. FPGA photos per program.
8. Issues and fixes: ECALL halt bug found in MS3, the 5-to-3 stage restructure, missing SSD driver, Lab 8 bugs not carried over.

`readme.txt`: names, IDs, release notes (what works, known limits: 1 KB memory, 128-instruction programs, button clock), how to run sim and build the bitstream, which 2 bonuses are claimed.

Folder cleanup before zipping:
- Delete `tmp/`; move `pipeline_plan/` out of the submission (or into `Design/notes/`).
- Remove generated files from `Verilog/`: `pipeline.vcd`, `simulation.out`, `datapath_schematic.dot`. Add a `.gitignore` for `*.out`, `*.vcd`.
- Rename `Testing/` to the name the spec template uses if the TA specifies one.
- `datapath_board.v` (commented-out MS2 board) delete or restore; do not ship a file that is entirely a comment.
- Every member's journal has MS3 entries.

---

## 8. Agent prompts

### Prompt A: P0 fixes (current 5-stage design, ship-safe)

```text
Repo: femtoRV32 (Verilog/). pipeline.v (5-stage, C0/C1) passes pipeline_tb
(149 checks) and unit_tb. Read pipeline_plan/MS3_REVISION_PLAN.md Sections 0-2,
4 (P0 only), 5 and 6. Do not change pipeline architecture in this task.

1. control_unit.v: halt only for EBREAK (inst[31:20]==12'h001, rs1==0,
   funct3==0, rd==0). ECALL/FENCE/FENCE.TSO/PAUSE stay NOPs.
2. Replace every ECALL used as a program terminator with EBREAK in
   pipeline_tb.v, datapath_tb.v and InstMem.v (keep the ECALL at mem[117] as a
   NOP and put EBREAK right after it). Rename Test 8 to wrong-path EBREAK.
3. Add a pipeline_tb test: ECALL, FENCE, FENCE.TSO (0x8330000F), PAUSE
   (0x0100000F) placed between dependent instructions act as NOPs; only EBREAK
   halts. Make Test 22 assert stall count 0.
4. RegFile.v: add a debug read port (dbgReadReg in, dbgReadData out).
   pipeline.v: add ports dbgRegSel[4:0] in; dbgRegData, dbgPC, dbgInst,
   dbgAluResult, dbgMemOut, dbgWbData (32-bit) and dbgFlags[15:0], dbgHalt out.
5. Rewrite datapath_board_pipelined.v to INSTANTIATE pipeline (no copied
   logic). Inputs per Section 6 (sysClk, stepBtn, reset, runMode, ledSel,
   ssdSel, regSel). Add Debounce.v and SevenSegHex8.v (8-digit hex, 32-bit).
   Update const1.xdc per Section 6; check every pin and IOSTANDARD against the
   Digilent Nexys-A7-100T master XDC and report any difference.
6. UnifiedMem.v: parameter PROGRAM_FILE; if non-empty, $readmemh it into mem
   (byte per line), else keep the current initial image.
7. Testing/programs/: write all_instr.s, hazards.s (from Test 21/22),
   predictor.s (from Test 20), nops_halt.s, plus bin2hex.py and a build script.
   Each ends with ebreak and is self-checking (x31 = 0, x30 = 0xC0DE on pass).
   Add a pipeline_tb task that $readmemh's each .hex and checks the signature.

Style: existing header block (Module/Project/Author/Description/Change
history), camelCase, named ports, 4-space indent, `default_nettype none in new
files. Fix the header of datapath_board_pipelined.v.

Done when: iverilog -g2012 -Wall -s pipeline_tb ... *.v passes all checks,
unit_tb passes, datapath_tb passes, and
iverilog -g2012 -s datapath_board_pipelined $(ls *.v | grep -v _tb) elaborates
with no errors. Report every change.
```

### Prompt B: 3-stage conversion (after Prompt A is merged)

```text
Repo: femtoRV32. Read pipeline_plan/MS3_REVISION_PLAN.md Section 3 fully; it
is the spec. Work on a git branch named three-stage.

Convert pipeline.v from 5 stages to the 3-stage organization of the project
description: Stage 0 = IF (C0) + ID (C1), Stage 1 = EX (C0) + MEM (C1),
Stage 2 = WB (C0).
- Delete IF_ID; ID uses instLatch and pcValue. Keep instLatch (load=isFetch).
- ID_EX and MEM_WB load at end of C1 (advance). EX_MEM becomes an intra-stage
  latch loaded at end of C0 (isFetch). RegFile still writes at end of C0.
- EX forwarding: single source MEM_WB (regWriteData). No load-use stall.
- Add parameter BRANCH_IN_ID (default 1). Use generate blocks.
  BRANCH_IN_ID=0: resolve in EX with forwarded operands; on redirect flush
  ID_EX and load PC at end of C1; predictor used; haltSet includes ~redirect.
  BRANCH_IN_ID=1: resolve in ID (C1) using EX_MEM_Result forwarded when the
  Stage 1 instruction writes rs1/rs2 and is not a load; stall 1 slot when it
  is a load (HazardUnit reduced to this rule); redirect loads PC, no flush.
- Keep signal names used by the testbench where they still exist; expose
  bpUpdatePC and bpActualTaken wires for Test 20's logger.

pipeline_tb: instantiate three configs (ID; EX+BP; EX no BP). All must end
with identical registers and memory. Re-baseline every cycle, stall and
mispredict expectation using Section 3.3; do not change register/memory
expectations. Predictor tests (6, 7, 18, 20) use the EX configs. Keep the
regression against the single-cycle datapath and the structural monitors.
Update unit_tb for the new HazardUnit. Re-run the mutation checks listed in
BONUS4_PLAN.md Section 3 adapted to the new design and report results.

Done when all benches pass with no -Wall warnings from changed files and the
board top still elaborates. List every expectation you re-baselined with the
old and new value and a one-line reason.
```

---

## 9. Open questions and risks

1. **Ask the TA today:** "Is a 5-stage pipeline that issues every 2 cycles (CPI = 2, C0 fetch / C1 data) acceptable, or must it be the 3-stage organization in the description?" If acceptable, skip Prompt B and use Section 3.6.
2. **Coding guidelines document:** not in my hands. Each member should check their files against it before the zip.
3. **Synthesis untested:** nothing has been through Vivado yet. Expect at least one round of fixes (memory initialization style, the button clock route, multi-driven nets). Build the bitstream as early as possible.
4. **Memory size:** 1 KB = 128 instructions at 0x000-0x1FF. `all_instr.s` with self-checks may exceed that. Raise `ADDR_BITS` to 11 or 12 and move `.data` up if needed; nothing else changes.
5. **Timing at 100 MHz** is irrelevant with a button clock, but if you add a fast run mode, keep it divided (a few Hz is enough to watch, a few MHz is enough to finish instantly).
