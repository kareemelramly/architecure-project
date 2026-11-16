# femtoRV32 Milestone 3: Kareem's Part (Unified Memory, C0/C1, Pipeline Registers, Branch Predictor)

## 0. Bottom line

Build the pipeline as a new top module `pipeline.v` next to the single-cycle `datapath.v`. Do not convert Lab 8 directly: it has five real bugs (Section 1) and only supports 7 instructions, while the project already supports all of RV32I + RV32M. Reuse the project's `control_unit`, `ImmGen`, `alu_unit`, `ALU`, `BranchUnit`, `RegFile` unchanged, and add five new files:

| File | Status | Purpose |
| --- | --- | --- |
| `UnifiedMem.v` | written, unit-tested | single-port byte-addressable memory, replaces `InstMem` + `DataMem` |
| `PhaseController.v` | written, unit-tested | C0/C1 toggle, gives `phase`, `isFetch`, `advance` |
| `PipelineReg.v` | written, compiles | generic load/flush register used for IF_ID, ID_EX, EX_MEM, MEM_WB |
| `BranchPredictor.v` | written, unit-tested | BTB + 2-bit BHT with EX update port (Bonus 3) |
| `ForwardingUnit.v` | written, compiles | corrected Lab 8 forwarding unit |
| `pipeline.v` | to do (Section 4 + prompt) | top level wiring |

Confidence: high on the four modules (self-checking tests pass in Icarus 12). Medium on the full top until you run the testbench, because the wiring is where bugs live.

---

## 1. What is wrong in Lab 8 (do not copy these)

| # | Bug | Effect | Fix |
| --- | --- | --- | --- |
| 1 | `Forwarding_Unit(... EX_MEM_RD, MEM_WB_RD ...)`, but the declared wires are `EX_MEM_Rd`, `MEM_WB_Rd` | Verilog silently creates 1-bit implicit nets, so forwarding compares a 5-bit register number with 1 bit. Forwarding is effectively broken. | Named port connections, add `` `default_nettype none `` at the top of new files to catch this. |
| 2 | `forwardA/forwardB` not assigned at the start of `always @(*)` | Inferred latch: once set to `10` it never returns to `00`. | Default both to `2'b00` first (done in `ForwardingUnit.v`). |
| 3 | `EX_MEM_REGWRITE`, `MEM_WB_REGWRITE` declared `[4:0]`; literals `10`/`01` written as decimal | Works by accident (decimal 10 truncates to `2'b10`). | 1-bit inputs, `2'b10` literals. |
| 4 | forwardB applied **after** the ALUSrc mux (`aluInputData2New`) | For `lw`/`sw`/`addi` whose rs2 field matches a recent rd, the immediate is replaced by forwarded data. | Forward on rs2 first, then the ALUSrc mux. |
| 5 | `EX_MEM` stores `aluInputData2New` as the store data | `sw` stores the immediate offset instead of rs2. | Store the forwarded rs2 value (pre-mux). |
| 6 | Branch resolved in MEM with no flush; relies on 3 NOPs in the program | Any real program breaks. | Resolve in EX, flush IF_ID and ID_EX on mispredict. |
| 7 | `Nbit_shift_left` on the immediate | Project `ImmGen` already appends the `0` LSB; shifting again doubles the offset. | Target = `PC + imm` directly. |
| 8 | No load-use hazard detection | Relies on manual NOPs. | Hazard unit (Section 4.4). |
| 9 | Lab InstMem `mem[5]` comment says `beq x4, x3` but rs2 field is `00101` (x5) | Test does not test what it claims. | Not carried over; noted for the report. |

---

## 2. Design decision: how C0/C1 works

One clock, no clock divider. A 1-bit `phase` register toggles every cycle. Everything that belongs to "the pipeline" (PC, IF_ID, ID_EX, EX_MEM, MEM_WB) loads only when `advance = phase = 1`, i.e. at the end of C1. So each pipeline stage lasts 2 cycles and an instruction is issued every 2 cycles (CPI = 2).

| Phase | Memory port used by | Address | Other events at the end of this cycle |
| --- | --- | --- | --- |
| C0 (`phase=0`) | IF | `PC` | `instLatch` captures the fetched word; **RegFile writes the WB value** |
| C1 (`phase=1`) | MEM | `EX_MEM_Result` | store is written; PC and all four pipeline registers advance |

Why this order:
- Load data is read in C1 and goes straight into MEM_WB at the same edge. No extra latch for data.
- The instruction is read in C0 but IF_ID only loads at the end of C1, so a 32-bit `instLatch` (an `N_bit_register` with `Load = isFetch`) holds it.
- Writing the RegFile at the end of C0 means the instruction in ID reads the new value during C1. This removes the WB-to-ID hazard without a negedge RegFile (Lab 8 used `N_bit_register_neg` for this). Mention this in the report: it is a free benefit of the 2-phase scheme.
- Stores write only in C1 (`memWrite = EX_MEM_MemWrite & phase`), so a store never writes twice.

Why not a divided clock: a derived clock on an FPGA creates a second clock domain and gated-clock warnings in Vivado. An enable (`advance`) on a single clock gives identical behaviour and is the standard method.

Timing of three instructions (port never has two users in the same cycle):

```
cycle :  0    1    2    3    4    5    6    7    8    9
phase :  C0   C1   C0   C1   C0   C1   C0   C1   C0   C1
I1    : [ IF    ][ ID    ][ EX    ][ MEM   ][ WB    ]
I2    :           [ IF    ][ ID    ][ EX    ][ MEM   ][ WB ...
I3    :                     [ IF    ][ ID    ][ EX    ][ MEM ...
port  :  F1   -    F2   -    F3   -    F4   M1   F5   M2
```

`F` = fetch in C0, `M` = load/store in C1.

---

## 3. Your four parts, step by step

### Step 1: Unified memory (`UnifiedMem.v`)

1. Array is `reg [7:0] mem [0:1023]` (byte-addressable, `ADDR_BITS = 10`).
2. Memory map: instructions `0x000-0x1FF` (same 128 words as the old `InstMem`), data `0x200-0x3FF`.
3. Reads are little-endian `{mem[a+3], mem[a+2], mem[a+1], mem[a]}` with LB/LH/LBU/LHU extension (same `funct3` cases as old `DataMem`).
4. Stores write 1, 2 or 4 bytes depending on `funct3[1:0]`. Simpler than the old read-modify-write masking.
5. Initialisation keeps your existing commented style through a task: `initWord(10'h004, 32'b..._0000011);  // comment`.
6. **Port the test program:** copy each `mem[i] = ...` from `InstMem.v` to `initWord(4*i, ...)`, copy each `mem[k]` from `DataMem.v` to `initWord(10'h200 + 4*k, ...)`, then add `512` to the immediate of every load/store that uses `x0` as base (e.g. `lw x1, 0(x0)` becomes `lw x1, 512(x0)`, imm `001000000000`). If a load/store uses another base register, adjust the instruction that sets that register instead.
7. The memory has one address input. The mux is in the top, which makes the "single port" requirement visible in the schematic:

```verilog
assign memAddr     = (isFetch) ? pcValue[9:0] : EX_MEM_Result[9:0];
assign memReadEn   = (isFetch) ? 1'b1         : EX_MEM_MemRead;
assign memWriteEn  = (isFetch) ? 1'b0         : EX_MEM_MemWrite;   // so only in C1
assign memFunct3   = (isFetch) ? `MEM_LW      : EX_MEM_Funct3;
```

### Step 2: C0/C1 controller (`PhaseController.v`)

A `DFlipFlop` with `D = ~Q`, reset to 0 (so the first cycle after reset is a fetch of PC = 0). Outputs:
- `isFetch = ~phase`: drives the memory mux and `instLatch` load.
- `advance = phase`: AND it into **every** pipeline load, flush, PC load and predictor update.
- RegFile write enable in the top: `regWriteEn = MEM_WB_RegWrite & isFetch`.

Common mistake: forgetting to gate one signal with `advance`. Then that signal acts twice per instruction (e.g. a BHT counter moves by 2, or a store writes in both phases).

### Step 3: Pipeline registers (`PipelineReg.v`)

One generic module, instantiated four times. `flush` loads zeros (all control bits 0 = bubble) and wins over stall. Callers pass `load = advance & ...` and `flush = advance & ...`.

Bubble detail: an all-zero instruction decodes as opcode `00000` (LOAD). Harmless (rd = x0) but confusing in waveforms, so in the top gate the ID control signals with `idValid = (IF_ID_Inst != 32'd0)`.

Field layouts (MSB first). Carrying the full instruction into ID_EX means `alu_unit` and `BranchUnit` keep their current ports.

| Register | Fields | Bits |
| --- | --- | --- |
| IF_ID | `PC[32], Inst[32], PredNextPC[32], PredTaken[1]` | 97 |
| ID_EX | ctrl `{regWrite, memToReg[2], memRead, memWrite, branch, isJal, isJalr, aluSource, aluSrcA, aluOp[2]}` (12), `PC, PredNextPC, RegR1, RegR2, Imm, Inst` (6x32), `PredTaken` (1) | 205 |
| EX_MEM | ctrl `{regWrite, wbFromMem, memRead, memWrite}` (4), `Result[32], StoreData[32], Funct3[3], Rd[5]` | 76 |
| MEM_WB | ctrl `{regWrite, wbFromMem}` (2), `MemOut[32], Result[32], Rd[5]` | 71 |

Key simplification: in EX, compute the final non-memory result once:

```verilog
assign exResult = (ID_EX_MemToReg == `WB_PC4) ? ID_EX_PC + 32'd4 :
                  (ID_EX_MemToReg == `WB_IMM) ? ID_EX_Imm        : aluOutput;
```

and store it as `EX_MEM_Result`. Then forwarding from EX_MEM is correct for JAL, JALR and LUI too (Lab-style forwarding of `ALU_out` would forward the wrong value for those), and EX_MEM/MEM_WB stay as small as in Lab 8. Loads/stores still use `aluOutput` as the address, which equals `exResult` for them.

Load/flush table:

| Register | load | flush |
| --- | --- | --- |
| PC | `advance & (redirect \| (~stall & ~haltNow))` | none |
| IF_ID | `advance & ~stall` | `advance & (redirect \| haltNow)` |
| ID_EX | `advance` | `advance & (redirect \| stall)` |
| EX_MEM | `advance` | 0 |
| MEM_WB | `advance` | 0 |

### Step 4: Branch predictor (`BranchPredictor.v`, Bonus 3)

- 16 entries, direct-mapped, index `PC[5:2]`, tag `PC[31:6]` (full tag, so a hit can only be a real branch/JAL).
- BTB entry: `valid`, `tag`, `target`. BHT entry: 2-bit counter, reset to `01` (weakly not taken).
- Prediction (combinational, IF): `predictTaken = hit & counter[1]`.
- Update (EX, at `advance`): taken and hit: counter +1 (saturate at 11) and refresh target; taken and miss: allocate with counter `10`; not taken and hit: counter -1 (saturate at 00); not taken and miss: no change (avoids corrupting an aliasing entry).
- JALR is excluded from updates (its target depends on a register), so it always resolves in EX.

IF-stage next PC:

```verilog
assign predNextPC = (predictTaken) ? predictTarget : pcValue + 32'd4;
assign pcInput    = (redirect)     ? actualNextPC  : predNextPC;
```

EX-stage resolution (operands must be the **forwarded** values):

```verilog
assign actualTaken  = exTakeBranch | ID_EX_IsJal | ID_EX_IsJalr;
assign actualTarget = (ID_EX_IsJalr) ? ((fwdRs1 + ID_EX_Imm) & ~32'd1)
                                     : (ID_EX_PC + ID_EX_Imm);
assign actualNextPC = (actualTaken) ? actualTarget : ID_EX_PC + 32'd4;
assign isCtrlFlow   = ID_EX_Branch | ID_EX_IsJal | ID_EX_IsJalr;
assign redirect     = isCtrlFlow & (actualNextPC != ID_EX_PredNextPC);
assign bpUpdateEn   = advance & (ID_EX_Branch | ID_EX_IsJal);
```

Comparing `actualNextPC` with the predicted next PC catches every case in one compare: wrong direction, wrong target, and JALR. `isCtrlFlow` keeps bubbles (PC = 0) from triggering false redirects. Mispredict penalty: 2 squashed instructions = 4 cycles.

---

## 4. Integration points that touch teammates' parts

1. **Forwarding** (`ForwardingUnit.v`): forward into `fwdRs1`/`fwdRs2` (pre-ALUSrc mux). Sources: `2'b10` = `EX_MEM_Result`, `2'b01` = MEM_WB write-back value. `fwdRs2` is also the store data and a BranchUnit operand.
2. **ALU input A**: `aluInputData1 = ID_EX_AluSrcA ? ID_EX_PC : fwdRs1` (AUIPC).
3. **RegFile**: `readreg1/2` from `IF_ID_Inst`, `writereg = MEM_WB_Rd`, `regwrite = MEM_WB_RegWrite & isFetch`.
4. **Load-use hazard**: `stall = ID_EX_MemRead & (ID_EX_Rd != 0) & ((ID_EX_Rd == IF_ID_Inst[19:15]) | (ID_EX_Rd == IF_ID_Inst[24:20]))`. Stall and redirect cannot occur together (a load is not a branch).
5. **Halt (ECALL/EBREAK)**: `haltNow = idHalt | haltLatch`. Set the 1-bit `haltLatch` at `advance & idHalt & ~redirect`. While halting, PC holds and IF_ID is flushed, so older instructions drain and nothing younger enters. The `~redirect` term stops a wrong-path ECALL from halting the CPU.
6. **FPGA top** (`datapath_board.v`): instantiate `pipeline` instead of `datapath`; the LED/SSD debug muxes need the new signal names.

---

## 5. Verification checklist

1. Unit tests (provided `unit_tb.v`): phase toggle, byte/half/word loads and stores, BHT state sequence `01→10→11→10→01→00`, alias protection. Run:
   `iverilog -g2012 -Wall -I. -o u.out ../Testing/unit_tb.v UnifiedMem.v PhaseController.v PipelineReg.v BranchPredictor.v N_bit_register.v DFlipFlop.v mux2x1.v && vvp u.out`
2. Directed hazard programs, each self-checking on final register values:
   - EX-EX forward: `add x3,x1,x2; add x5,x3,x2`
   - MEM-EX forward: one independent instruction between producer and consumer
   - load-use: `lw x6,..; and x7,x6,x1` (expect one bubble)
   - store after load: `lw x5,..; sw x5,..` (checks forwarded store data, Lab 8 bug 5)
   - JAL/LUI result forwarded to the next instruction (checks `exResult`)
   - loop with `bne` taken 5 times then falls through (predictor learns; count mispredicts)
   - ECALL after a mispredicted branch (must not halt)
3. Run the full existing 40-instruction program ported to `UnifiedMem` and compare the final register file with the single-cycle `datapath_tb` results.
4. CPI evidence for the report: cycles / retired instructions, with predictor on vs. off (tie `predictTaken` to 0). No-branch code should give exactly 2.0 plus fill cycles.

---

## 6. Prompt for the coding agent (paste as-is)

```text
You are working in a Verilog repo for femtoRV32, a RISC-V RV32I+RV32M processor.
Folder Verilog/ holds a working single-cycle design (datapath.v, control_unit.v,
ImmGen.v, alu_unit.v, ALU.v, BranchUnit.v, RegFile.v, N_bit_register.v,
DFlipFlop.v, mux2x1.v, defines.vh, datapath_tb.v). Do NOT modify those files.

New, already-tested files (do not rewrite, only fix if a test proves a bug):
UnifiedMem.v, PhaseController.v, PipelineReg.v, BranchPredictor.v,
ForwardingUnit.v. Read PIPELINE_PLAN.md fully before starting; Sections 2-4 are
the spec.

TASK: create Verilog/pipeline.v (module pipeline(input clk, input reset)), a
5-stage pipelined version of datapath.v with:
1. One UnifiedMem shared by IF and MEM. Address mux in the top:
   isFetch ? pcValue[9:0] : EX_MEM_Result[9:0]. memWrite only when !isFetch.
   Fetch uses funct3 = `MEM_LW and memRead = 1.
2. PhaseController: pipeline registers and PC load only when advance=1
   (end of C1). A 32-bit instLatch (N_bit_register, Load=isFetch) holds the
   fetched word until IF_ID loads. RegFile regwrite = MEM_WB_RegWrite & isFetch.
3. Four PipelineReg instances named IF_ID, ID_EX, EX_MEM, MEM_WB with exactly
   the field layouts and load/flush equations in PIPELINE_PLAN.md Section 3.
   Use concatenations {..} on D and Q like the Lab 8 style.
4. ID control signals gated by idValid = (IF_ID_Inst != 0).
5. EX stage: ForwardingUnit into fwdRs1/fwdRs2 BEFORE the ALUSrc mux;
   aluSrcA mux for AUIPC; BranchUnit on fwdRs1/fwdRs2 with ID_EX_Inst[14:12];
   alu_unit gets ID_EX_Inst; exResult mux (ALU / PC+4 / Imm) stored as
   EX_MEM_Result; fwdRs2 stored as EX_MEM_StoreData.
6. BranchPredictor in IF, update from EX with the exact redirect / actualNextPC
   / bpUpdateEn equations in Section 3 Step 4. JALR not written to the BTB.
7. Load-use hazard stall and ECALL/EBREAK halt latch as in Section 4.
8. Put `default_nettype none at the top of pipeline.v and `default_nettype wire
   at the bottom. Use named port connections only.

Coding style (match existing files exactly): the /*** header block with Module,
Project, Author (Kareem Elramly), Description, Change history; `timescale 1ns/1ps;
`include "defines.vh"; camelCase wires, STAGE_Field names for pipeline outputs
(e.g. ID_EX_Rd, EX_MEM_Result); always @* with defaults first; 4-space indent.

TESTS: create Verilog/pipeline_tb.v, self-checking like datapath_tb.v (print
PASS/FAIL per check and a final count). Each test loads its own program into
UnifiedMem via hierarchical access to dut.memory.initWord(...) or by a
separate program include, runs until halt, then checks registers via
dut.RegisterFile.Gen_Regs[n].u_reg.Q and memory bytes. Cover every item in
PIPELINE_PLAN.md Section 5.2, then port the full program from InstMem.v /
DataMem.v (data moved to 0x200, x0-based load/store immediates +512) and check
that final registers match the single-cycle run. Print total cycles, retired
instructions, CPI, and mispredict count, with the predictor enabled and
disabled (add a parameter BP_ENABLE to pipeline).

Build: cd Verilog && iverilog -g2012 -Wall -s pipeline_tb -o ../Testing/pipeline.out *.v
       vvp ../Testing/pipeline.out
Iterate until 0 failures and no -Wall warnings from new files. Then update
datapath_board.v into pipeline_board.v that instantiates pipeline (keep the old
file). Finally list every change and any spec deviation with the reason.
```

---

## 7. Order to do it in (about one working session each)

1. Drop the five files into `Verilog/`, run `unit_tb.v`.
2. Port the program into `UnifiedMem.v` (Step 1.6). Do this by hand or let the agent do it, but check three load/store immediates yourself.
3. Give the prompt to the agent for `pipeline.v` + `pipeline_tb.v`.
4. Review the generated top against Section 3's load/flush table and Section 3 Step 4 equations line by line. Those 10 lines decide correctness.
5. Waveform screenshot for the report: show `phase`, `memAddr`, `isFetch`, `IF_ID_Inst`, `redirect`, `bpUpdateEn` around one mispredicted branch.

Open risks:
- The 1024-byte memory caps programs at 128 instructions. Raise `ADDR_BITS` to 11 or 12 if the final test program is longer; nothing else changes.
- If the course requires load-use forwarding without a stall: load data appears in C1 of the load's MEM step, while the dependent ALU op runs in EX in the same step, so a combinational memory-to-ALU forward is possible and would remove the stall, at the cost of a long critical path. Stay with the stall unless the spec asks for this.
