from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
log=(root/'Testing/documentation_test_results.txt').read_text()
checks=log.count('[ OK ]')
text='''# femtoRV32 - Single-Cycle RISC-V Processor

## Students

- Kareem Abdellatif
- [Mohamed Aboelfotouh](https://aucegypt.instructure.com/courses/17790/users/10714)
- [Moustafa Fayed](https://aucegypt.instructure.com/courses/17790/users/4886)

## Overview

A 32-bit single-cycle educational processor in Verilog. The current testbench covers 40 RV32I instructions and eight RV32M instructions, plus FENCE.TSO and PAUSE. ECALL and EBREAK halt the PC. Synchronization instructions execute as side-effect-free NOPs in this memory model. This is the project's implemented behavior, not a privileged execution environment.

## Files

- `Verilog/`: RTL, shared constants, instruction ROM and self-checking testbench.
- `Testing/`: fresh simulation results, optional waveform-capture module and VCD traces.
- `Testing/waveforms/`: original GTKWave screenshot saved by the team.
- `Design/`: block diagrams, generated Yosys schematic and report generation scripts.
- `Journal/`: individual contribution logs.
- `output/pdf/femtoRV32_Design_Report.pdf`: design report with diagrams, schematic and waveform evidence.

## Implemented instructions

| Group | Instructions |
| --- | --- |
| Upper immediate / jumps (4) | LUI, AUIPC, JAL, JALR |
| Branches (6) | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Loads (5) | LB, LH, LW, LBU, LHU |
| Stores (3) | SB, SH, SW |
| Immediate ALU (9) | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Register ALU (10) | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Base system / synchronization (3) | FENCE, ECALL, EBREAK |
| RV32M (8) | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| Additional synchronization / hint (2) | FENCE.TSO, PAUSE |

The 40-instruction base count includes FENCE, ECALL and EBREAK. FENCE.TSO and PAUSE are additional checks. Directed instruction coverage is not an exhaustive ISA-compliance proof.

## Build and run in WSL

Required: Icarus Verilog (`iverilog`, `vvp`), Yosys and Graphviz (`dot`). Verified using Icarus Verilog 12.0 and Yosys 0.52.

```bash
cd "/mnt/d/New folder/architecure-project/Verilog"
iverilog -g2012 -Wall -s datapath_tb -o ../Testing/simulation.out *.v
vvp ../Testing/simulation.out | tee ../Testing/testbench_result.txt
```

Compile all sources together. Compiling only the datapath and testbench produces unknown-module errors. Run from `Verilog/` so `defines.vh` is found.

### Capture waveforms

```bash
iverilog -g2012 -Wall -s datapath_tb -s waveform_capture \\
  -o ../Testing/waveform_sim.out *.v ../Testing/waveform_capture.v
vvp ../Testing/waveform_sim.out | tee ../Testing/documentation_test_results.txt
# Optional, if GTKWave is installed:
gtkwave ../Testing/datapath.vcd
```

The separate `waveform_capture.v` module observes signals without changing the RTL or testbench. The report uses the existing GTKWave screenshot in Testing/waveforms/waveform.png, together with the original block diagram and datapath schematic from Design/.

### Generate the schematic

```bash
yosys -p '
read_verilog datapath.v DataMem.v InstMem.v RegFile.v Nbit_decoder.v N_bit_register.v DFlipFlop.v mux2x1.v ImmGen.v control_unit.v alu_unit.v ALU.v BranchUnit.v
hierarchy -check -top datapath
proc
show -format dot -prefix ../Design/report_datapath_schematic datapath
'
dot -Tpdf ../Design/report_datapath_schematic.dot -o ../Design/report_datapath_schematic.pdf
dot -Tpng -Gdpi=130 ../Design/report_datapath_schematic.dot -o ../Design/report_datapath_schematic.png
```

This generates a hierarchical RTL schematic, not a placed-and-routed FPGA netlist or a timing report. The top exposes only clock/reset. Avoid aggressive cleanup solely for illustration: an output-less top can be optimized away.

## Release notes - 2 November 2026

### What works

- Fresh simulation: 110 cycles to ECALL, PASSING_CHECKS passing checks and zero failed checks; all 48 coverage bits set.
- Branch score 70, trap count 0; six branch conditions, an unsigned not-taken branch, jump links and skipped traps checked.
- Signed/unsigned byte and halfword loads; all four byte-store lanes; both halfword-store positions; word readback.
- Register x0 hardwired to zero; transient register results captured before later writes.
- All eight RV32M operations, including divide-by-zero and signed-overflow cases.
- FENCE/FENCE.TSO/PAUSE decode with no register, memory or branch side effects. ECALL halts at byte PC 468; EBREAK is checked in a separate reset phase.
- Yosys hierarchy elaboration and datapath schematic generation complete successfully.

### Issues encountered and solutions

- Duplicate `cu_memToReg`: keep one two-bit declaration and explicitly declare two-bit `cu_aluOp`.
- Writeback-width drift: compare the complete ten-bit no-side-effect control vector.
- Unknown module errors: compile all RTL dependencies, including `RegFile.v`, `DFlipFlop.v` and `mux2x1.v`.
- Missing SUB/AND/OR/JAL checks: add directed instructions and cycle-by-cycle result/next-PC checks.
- Overwritten registers: capture transient LB/SLT/SLTU/SLTI results at the relevant instruction boundary.
- x0 writes: current register file generates writable storage only for x1-x31; x0 is constant zero.
- RV32M corner cases: explicit division-by-zero and signed-overflow handling supplies deterministic expected results.

### Assumptions and limitations / what does not work

- Little-endian memory; 64 data words (256 bytes), 128 instruction words (512 bytes). High address bits are discarded, so higher addresses alias.
- Aligned halfword/word accesses and aligned 32-bit instructions assumed. Misalignment traps and cross-word accesses are not implemented.
- Combinational memory reads; rising-edge register/memory writes. PC/register reset is asynchronous. Data memory is initialized once and is not cleared by CPU reset.
- FENCE/FENCE.TSO/PAUSE do not implement caches, multi-hart ordering or low-power waiting; they are NOPs in this model.
- ECALL/EBREAK halt instead of entering a trap handler. CSRs, interrupts, privilege modes, virtual memory and OS support are absent.
- Unsupported encodings do not cause an illegal-instruction trap. Decoding uses `inst[6:2]` and does not fully validate all encodings.
- No compressed, atomic or floating-point extensions, pipeline or stall interface.
- RV32M division is combinational. FPGA clock rate, resource use, board execution and place-and-route timing are not validated. `datapath_board.v` is commented out.
- Passing directed tests does not prove exhaustive correctness or timing closure.

## Verification evidence

See `Testing/documentation_test_results.txt`, `Testing/datapath.vcd`, `Testing/documentation_yosys.log` and the PDF report. The final EBREAK phase resets the CPU after main-program checks. The saved GTKWave screenshot retains its original bus-display formats and time labels.

## Kareem Abdellatif's assigned contribution

- Remaining loads: LB, LH, LBU, LHU.
- Remaining stores: SB, SH.
- System and synchronization: FENCE, FENCE.TSO, PAUSE, ECALL, EBREAK.

See `Journal/Kareem_Abdellatif_Log.txt`. The existing team journals are preserved.
'''.replace('PASSING_CHECKS',str(checks))
(root/'README.md').write_text(text,encoding='utf-8')
plain=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'\1 (\2)',text)
plain=re.sub(r'^#{1,6}\s*','',plain,flags=re.M).replace('```bash\n','').replace('```\n','').replace('`','')
(root/'readme.txt').write_text(plain,encoding='utf-8')
(root/'Journal/Kareem_Abdellatif_Log.txt').write_text('''For my role in the project, I was responsible for the following instructions:

- Remaining Load Instructions: lb, lh, lbu, lhu
- Remaining Store Instructions: sb, sh
- System & Synchronization Instructions: FENCE, FENCE.TSO, PAUSE, ECALL, EBREAK.

To do this, I mainly focused on DataMem.v and control_unit.v, with corresponding instruction sequences in InstMem.v and validation in datapath_tb.v. For the remaining loads, I selected the addressed byte or halfword from a 32-bit little-endian word and applied sign extension for lb/lh and zero extension for lbu/lhu. I used addr[7:2] to select the word, addr[1:0] to select the byte, and addr[1] to select the halfword.

For sb and sh, I implemented partial-word updates so that only the addressed byte or halfword changes while the other bytes remain unchanged. I validated all four byte positions and both halfword positions, then checked the resulting words through lw readback. The test word 0x7C8AF1B2 checks negative and positive signed loads as well as unsigned extension.

For synchronization, I implemented FENCE, FENCE.TSO and PAUSE as safe NOPs in the project's single-cycle memory model, without register, memory or branch side effects. For ECALL and EBREAK, I decoded the SYSTEM instruction fields and asserted halt so the PC remains frozen. This is a project-specific stopping mechanism rather than a privileged trap implementation. I also checked that another SYSTEM encoding, CSRRW, does not incorrectly halt the processor.

During integration, I checked testbench control connections and message widths, including the two-bit memToReg signal, and verified memory results and halt behavior. I kept the implementation consistent with the team's shared datapath and coding style. The current team testbench also validates the complete base instruction set and RV32M extension; those broader instruction groups are shared integration work and are not part of my assigned instruction ownership.

November 2, 2026: documentation and verification record.
Prepared the README files, release notes and design report. Recorded a fresh passing simulation, generated a Yosys datapath schematic and captured actual load/store and system/synchronization waveforms. This entry records the current documentation activity; earlier implementation dates and exact work-session times are not asserted here.
''',encoding='utf-8')
print('README.md, readme.txt and Kareem journal created; checks:',checks)
