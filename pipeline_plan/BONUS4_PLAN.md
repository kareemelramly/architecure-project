# femtoRV32 Milestone 3: Mohamed's Part (Bonus 4: ID-Stage Branch Resolution)

## 0. Bottom line

Move branch/jump resolution from EX into ID inside the existing `pipeline.v`. Do not touch `datapath.v`: it is the single-cycle golden reference that `pipeline_tb` compares against. If the TA insists the top must be called `datapath.v`, rename at the very end (`datapath.v` → `datapath_single.v`, `pipeline.v` → `datapath.v`) and update the testbench instance names.

Status: I prototyped every change below on a copy of the current code. The existing 67 checks plus 16 new Bonus 4 checks all pass (124/124), the full program still matches the single-cycle core, and mutation tests confirm the new tests catch a missing branch stall, missing ID forwarding, and redirecting while stalled. The prototype is in `pipeline_plan/bonus4_reference/` so the agent's output can be diffed against it.

What changes, in one line each:

| Change | File | Size |
| --- | --- | --- |
| New hazard unit (load-use + branch stalls) | `HazardUnit.v` (new) | ~70 lines |
| Second `ForwardingUnit` instance feeding ID | `pipeline.v` | 10 lines + 2 muxes |
| `BranchUnit`, target adders, redirect moved EX → ID | `pipeline.v` | move ~15 lines |
| Predictor update port driven from ID | `pipeline.v` | 3 connections |
| ID_EX no longer flushed on redirect | `pipeline.v` | 1 line |
| Retired-instruction counter in testbench | `pipeline_tb.v` | 1 line |
| New Test 12 (branch hazards) | `pipeline_tb.v` | ~90 lines |

No changes to `UnifiedMem`, `PhaseController`, `PipelineReg`, `BranchPredictor`, `ForwardingUnit`, `BranchUnit`, or any single-cycle module.

---

## 1. How the C0/C1 scheme changes Bonus 4 (read this first)

The textbook ID-branch design (Patterson & Hennessy 4.8) assumes one cycle per stage. Here each stage is two cycles, and the register file writes at the end of C0. Consequences:

| Older instruction position when branch is in ID | Textbook | This design | Why |
| --- | --- | --- | --- |
| WB (3 ahead) | regfile write/read split | no action | RegFile writes at end of C0, ID reads during C1 |
| MEM, ALU result (2 ahead) | forward EX/MEM | forward `EX_MEM_Result` | value is stable all step |
| MEM, load (2 ahead) | 1 stall | 1 stall | load data appears only in C1; forwarding it would put memory → compare → PC in one cycle |
| EX, ALU (1 ahead) | 1 stall | 1 stall | result is still being computed |
| EX, load (1 ahead) | 2 stalls | 2 stalls | stall once (load in EX), again (load in MEM) |

The MEM/WB forward into ID that the task asks for is therefore redundant in this design (the register file already holds the value by C1). Keep it anyway: it is required by the spec, costs two mux inputs, and keeps the design correct if someone later removes the C0 write. Say this explicitly in the report; it shows you understood the timing.

Penalties after the change:
- Mispredict: 1 squashed slot (2 cycles) instead of 2 slots (4 cycles).
- New cost: an ALU result right before a branch now costs 1 stall slot, and a load right before a branch costs 2.

Measured trade-off (prototype, predictor on):

| Program | EX resolution | ID resolution | Note |
| --- | --- | --- | --- |
| `bne` loop (`addi x2,x2,-1; bne x2,x0`) | 52 cycles | 60 cycles | ALU-use stall every iteration outweighs cheaper mispredicts |
| `jal`/`beq` loop | 50 | 48 | |
| Full 129-word program | 252 | 238 | 7 mispredicts now cost 2 cycles each |

Bonus 4 is not a free win. Report the `bne` loop result honestly and point out that a compiler would schedule an independent instruction between `addi` and `bne` to remove the stall.

---

## 2. Step by step

### Step 1: `HazardUnit.v` (new)

Inputs: `idInst`, `idValid`, `idExMemRead`, `idExRegWrite`, `idExRd`, `exMemMemRead`, `exMemRd`. Outputs: `loadUseStall`, `branchStall`, `stall`.

```verilog
assign usesRs1   = idValid && (OP | OP_IMM | LOAD | STORE | BRANCH | JALR);
assign usesRs2   = idValid && (OP | STORE | BRANCH);
assign readsInId = idValid && (BRANCH | JALR);   // JAL needs no register

assign matchEx  = (idExRd  != 0) && ((usesRs1 && idExRd  == rs1) || (usesRs2 && idExRd  == rs2));
assign matchMem = (exMemRd != 0) && ((usesRs1 && exMemRd == rs1) || (usesRs2 && exMemRd == rs2));

assign loadUseStall = idExMemRead && matchEx;
assign branchStall  = readsInId && ((idExRegWrite && matchEx) || (exMemMemRead && matchMem));
assign stall        = loadUseStall | branchStall;
```

`usesRs1/usesRs2` replace the old check that compared rd with both rs fields of every instruction. Side benefit: EBREAK (`0x00100073`) has `1` in the rs2 field and used to stall spuriously behind a write to x1.

The existing `assign stall = ...` in `pipeline.v` is deleted; `stall` now comes from this module.

### Step 2: ID-stage forwarding (second `ForwardingUnit` instance)

Reuse `ForwardingUnit.v` unchanged with ID operands:

```verilog
assign exMemFwdEn = EX_MEM_RegWrite & ~EX_MEM_WbFromMem;   // never forward a load address

ForwardingUnit idForwarding(
    .idExRs1(IF_ID_Inst[19:15]), .idExRs2(IF_ID_Inst[24:20]),
    .exMemRd(EX_MEM_Rd),         .memWbRd(MEM_WB_Rd),
    .exMemRegWrite(exMemFwdEn),  .memWbRegWrite(MEM_WB_RegWrite),
    .forwardA(idForwardA),       .forwardB(idForwardB)
);

assign idRs1Val = (idForwardA == 2'b10) ? EX_MEM_Result :
                  (idForwardA == 2'b01) ? regWriteData  : readData1;
assign idRs2Val = (idForwardB == 2'b10) ? EX_MEM_Result :
                  (idForwardB == 2'b01) ? regWriteData  : readData2;
```

`exMemFwdEn` is defensive: the hazard unit already stalls whenever a load in EX_MEM feeds the branch, so the mutation test shows it never changes results. Keep it so the forwarding path is safe by itself. The port names say `idEx...` because the module was written for EX; leave them (renaming would touch Kareem's file) and comment the instance.

Do not feed `idRs1Val/idRs2Val` into ID_EX. ID_EX keeps `readData1/readData2`; the EX forwarding unit already corrects them a step later. Only the branch comparator and the JALR target use the ID-forwarded values.

### Step 3: Move resolution into ID

Delete from EX: the `BranchUnit` instance, and the `actualTaken / actualTarget / actualNextPC / isCtrlFlow / redirect / bpUpdateEn` assigns. Add in ID:

```verilog
BranchUnit branchComparator(
    .branch(idBranch), .funct3(IF_ID_Inst[14:12]),
    .readData1(idRs1Val), .readData2(idRs2Val),
    .takeBranch(idTakeBranch)
);

assign idActualTaken  = idTakeBranch | idIsJal | idIsJalr;
assign idActualTarget = (idIsJalr) ? ((idRs1Val + immGenOut) & ~32'd1)
                                   : (IF_ID_PC + immGenOut);
assign idActualNextPC = (idActualTaken) ? idActualTarget : (IF_ID_PC + 32'd4);
assign idIsCtrlFlow   = idBranch | idIsJal | idIsJalr;
assign redirect       = idIsCtrlFlow & ~stall & (idActualNextPC != IF_ID_PredNextPC);
assign bpUpdateEn     = advance & ~stall & (idBranch | idIsJal);
```

`~stall` in `redirect` is critical: while stalled, the operands are stale and the comparison is garbage. The mutation test without it hangs the CPU in a loop.

The EX stage keeps `exResult` (JAL/JALR still write PC+4 through it), so nothing else in EX changes.

### Step 4: Rewire the predictor and the PC

```verilog
assign pcInput = (redirect) ? idActualNextPC : predNextPC;

BranchPredictor predictor(
    ...
    .updateEn(bpUpdateEn),
    .updatePC(IF_ID_PC),
    .actualTaken(idActualTaken),
    .actualTarget(idActualTarget)
);
```

### Step 5: Stall/flush table (new)

| Register | load | flush | Changed? |
| --- | --- | --- | --- |
| PC | `advance & (redirect \| (~stall & ~haltNow))` | none | no |
| IF_ID | `advance & ~stall` | `advance & (redirect \| haltNow)` | no |
| ID_EX | `advance` | `advance & stall` | **yes**: redirect removed. The branch in ID is on the correct path and must reach EX (JAL/JALR still write their link register). |
| EX_MEM, MEM_WB | `advance` | 0 | no |

Halt: `haltSet = advance & idHalt & ~stall` (drop `~redirect`). With ID resolution a wrong-path ECALL can only be in IF when the redirect fires, and the IF_ID flush already discards it. Test 8 still checks this.

### Step 6: Testbench updates

1. `PerfMonitor`: count retired as `advance && idValid && !stall` (remove `&& !redirect`). With EX resolution a redirect squashed the instruction in ID; now the instruction in ID is the branch itself, and it retires.
2. Add Test 12 with six programs (the prototype's numbers, all confirmed):

| Case | Program | Expect |
| --- | --- | --- |
| a | `addi x2; beq x1,x2` | 1 stall, taken, target executed |
| b | `addi x2; nop; beq x1,x2` | 0 stalls (EX/MEM → ID forward) |
| c | `lw x3; beq x3,x2` | 2 stalls |
| d | `lw x3; nop; bne x3,x2` | 1 stall, not taken |
| e | `addi x1,16; jalr x2,0(x1)` | 1 stall, jumps to 16 |
| f | cold `beq x0,x0,+8` followed by `ecall` | 1 mispredict, 8 total cycles (penalty = 1 slot) |

3. Existing expectations that stay valid: all register/memory values, mispredict counts (2/5 for both loops), CPI = 2 straight-line count of 84 cycles, the full-program regression.

---

## 3. Verification and report evidence

Run from `Verilog/`:

```bash
iverilog -g2012 -Wall -s pipeline_tb -o ../Testing/pipeline.out *.v
vvp ../Testing/pipeline.out | tee ../Testing/pipeline_result.txt      # expect: ALL 124 CHECKS PASSED
iverilog -g2012 -Wall -s unit_tb -o ../Testing/unit.out *.v && vvp ../Testing/unit.out
vvp ../Testing/pipeline.out +vcd && gtkwave pipeline.vcd
```

Waveform for the report: in Test 12(c) show `IF_ID_Inst`, `branchStall`, `stall`, `idForwardA`, `redirect`, `pcValue` across the 2 stall slots. Second capture: Test 12(f) showing a 1-slot squash.

Mutation checks worth repeating after the agent finishes (each must make the testbench fail):
- `branchStall = 0` → 17 failures in the prototype
- remove the `EX_MEM_Result` input of `idRs1Val` → 13 failures
- remove `~stall` from `redirect` → simulation hangs

---

## 4. Prompt for the coding agent (paste as-is)

```text
You are working in the femtoRV32 Verilog repo (folder Verilog/). It contains a
working 5-stage pipeline (pipeline.v) with a unified memory, C0/C1 phase
controller, BTB+BHT predictor, and branch resolution in EX. pipeline_tb.v passes
67 checks. datapath.v is the single-cycle golden reference: do NOT modify it or
any single-cycle module (control_unit, ImmGen, alu_unit, ALU, BranchUnit,
RegFile, N_bit_register, DFlipFlop, mux2x1, InstMem, DataMem), and do NOT modify
UnifiedMem.v, PhaseController.v, PipelineReg.v, BranchPredictor.v,
ForwardingUnit.v.

Read pipeline_plan/BONUS4_PLAN.md fully. Sections 1-2 are the spec.

TASK (Bonus 4, ID-stage branch resolution):
1. Create Verilog/HazardUnit.v exactly per Section 2 Step 1 (usesRs1/usesRs2/
   readsInId decode, loadUseStall, branchStall, stall). Replace the existing
   stall assign in pipeline.v with an instance of it.
2. Add a second ForwardingUnit instance named idForwarding feeding idRs1Val /
   idRs2Val (Step 2), with exMemRegWrite = EX_MEM_RegWrite & ~EX_MEM_WbFromMem.
   Do not change what goes into ID_EX.
3. Move BranchUnit and the target/next-PC/redirect/bpUpdateEn logic from EX to
   ID using the exact equations in Step 3. redirect must include ~stall.
   Delete the old EX versions and their wire declarations.
4. Rewire pcInput and the BranchPredictor update port to the ID signals (Step 4).
5. Apply the stall/flush table in Step 5: ID_EX flush = advance & stall only;
   haltSet = advance & idHalt & ~stall.
6. pipeline_tb.v: change PerfMonitor's retire condition per Step 6.1 and add
   task test12_id_branch_hazards covering cases a-f in Step 6.2 with the stated
   expected stall / mispredict / cycle counts, called after test11_regression.

Coding style (match existing files exactly): /*** header block with Module,
Project, Author (Mohamed AboElfotouh), Description, Change history (add a dated
line to pipeline.v and pipeline_tb.v); `timescale 1ns / 1ps; `include
"defines.vh"; camelCase wires; STAGE_Field names for pipeline register outputs;
id-prefix for new ID-stage signals; named port connections only; 4-space indent;
section banners like the existing ones.

Build and iterate until "ALL 124 CHECKS PASSED" with no -Wall warnings from new
or changed files:
  cd Verilog
  iverilog -g2012 -Wall -s pipeline_tb -o ../Testing/pipeline.out *.v
  vvp ../Testing/pipeline.out
  iverilog -g2012 -Wall -s unit_tb -o ../Testing/unit.out *.v && vvp ../Testing/unit.out

Then compare your pipeline.v and HazardUnit.v with
pipeline_plan/bonus4_reference/ and explain every difference. Finally run the
three mutation checks in Section 3 on a scratch copy and report that each one
makes the testbench fail. List all changes and any deviation from the plan
with the reason.
```

---

## 5. Order of work

1. Read Section 1 and agree with the team on reporting the `bne` loop slowdown.
2. Give the prompt to the agent (or do Steps 1-6 by hand; it is about 150 changed lines).
3. Check the 10 critical lines yourself: `redirect`, `bpUpdateEn`, `idExFlush`, `haltSet`, `pcInput`, the two `idRsXVal` muxes, `exMemFwdEn`, `branchStall`, and the predictor's `updatePC`.
4. Run the three mutation checks.
5. Capture the two waveforms for the report.

Open risks:
- Critical path: ID now has regfile read → forward mux → 32-bit compare → PC mux in one cycle (C1). At the Basys-3's 100 MHz this should fit, but check the Vivado timing report; if it fails, run the core from a slower clock in `pipeline_board.v`.
- `datapath.v` naming in the task list (see Section 0). Decide before the agent starts, since renaming changes the testbench.
