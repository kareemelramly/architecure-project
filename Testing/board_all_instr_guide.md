# Board test: all 50 instructions (PROGRAM_FILE = "all_instr")

Setup: SW15 up then down (= press 0). Press BTNC; at the press number in the
table set the view with SW3 SW2 SW1 and compare. Display is decimal;
`--------` = value too large (signed value given in brackets: check the
register number instead). A WB value stays on the display for 2 presses.

| Press | Instruction | View (SW3 SW2 SW1) | Expected |
|---|---|---|---|
| 5 | `ecall` | 001 Inst | 115; nothing written |
| 9 | `fence` | 001 Inst | -------- (0x0FF0000F); nothing written |
| 13 | `fence.tso` | 001 Inst | -------- (0x8330000F); nothing written |
| 17 | `pause` | 001 Inst | 16777231; nothing written |
| 36 | `add x3, x1, x2` | 110 WB data / 111 WB reg | 7 / 3 |
| 42 | `sub x3, x1, x2` | 110 WB data / 111 WB reg | 17 / 3 |
| 48 | `sll x3, x1, x1` | 110 WB data / 111 WB reg | 49152 / 3 |
| 54 | `slt x3, x2, x1` | 110 WB data / 111 WB reg | 1 / 3 |
| 60 | `sltu x3, x2, x1` | 110 WB data / 111 WB reg | 0 / 3 |
| 64 | `xor x3, x1, x2` | 110 WB data / 111 WB reg | -------- (0xFFFFFFF7 = -9) / 3 |
| 70 | `srl x3, x2, x4` | 110 WB data / 111 WB reg | 511 / 3 |
| 76 | `sra x3, x2, x1` | 110 WB data / 111 WB reg | -------- (0xFFFFFFFF = -1) / 3 |
| 82 | `or x3, x1, x2` | 110 WB data / 111 WB reg | -------- (0xFFFFFFFF = -1) / 3 |
| 88 | `and x3, x1, x2` | 110 WB data / 111 WB reg | 8 / 3 |
| 94 | `addi x3, x1, -0x2` | 110 WB data / 111 WB reg | 10 / 3 |
| 100 | `slti x3, x2, 0x0` | 110 WB data / 111 WB reg | 1 / 3 |
| 106 | `sltiu x3, x2, 0x1` | 110 WB data / 111 WB reg | 0 / 3 |
| 110 | `xori x3, x1, 0x5` | 110 WB data / 111 WB reg | 9 / 3 |
| 116 | `ori x3, x1, 0x3` | 110 WB data / 111 WB reg | 15 / 3 |
| 122 | `andi x3, x1, 0x6` | 110 WB data / 111 WB reg | 4 / 3 |
| 128 | `slli x3, x1, 0x2` | 110 WB data / 111 WB reg | 48 / 3 |
| 134 | `srli x3, x1, 0x2` | 110 WB data / 111 WB reg | 3 / 3 |
| 140 | `srai x3, x2, 0x1` | 110 WB data / 111 WB reg | -------- (0xFFFFFFFD = -3) / 3 |
| 146 | `lui x3, 0x12345` | 110 WB data / 111 WB reg | -------- (0x12345000 = 305418240) / 3 |
| 152 | `auipc x3, 0x0` | 110 WB data / 111 WB reg | 296 / 3 |
| 163 | `sw x6, 0x0(x20)` | 011 MemAddr / 101 Store | 768 / -------- (0x80F1F2F3) |
| 166 | `lw x3, 0x0(x20)` | 110 WB data / 111 WB reg | -------- (0x80F1F2F3 = -2131627277) / 3 |
| 170 | `lb x3, 0x0(x20)` | 110 WB data / 111 WB reg | -------- (0xFFFFFFF3 = -13) / 3 |
| 176 | `lbu x3, 0x0(x20)` | 110 WB data / 111 WB reg | 243 / 3 |
| 182 | `lh x3, 0x2(x20)` | 110 WB data / 111 WB reg | -------- (0xFFFF80F1 = -32527) / 3 |
| 190 | `lhu x3, 0x2(x20)` | 110 WB data / 111 WB reg | 33009 / 3 |
| 197 | `sb x1, 0x4(x20)` | 011 MemAddr / 101 Store | 772 / 12 |
| 199 | `sh x2, 0x6(x20)` | 011 MemAddr / 101 Store | 774 / -------- (0xFFFFFFFB) |
| 208 | `beq x1, x1, 0x1a4` | 000 PC | 420 (taken; branch at 412) |
| 210 | `bne x1, x2, 0x1ac` | 000 PC | 428 (taken; branch at 420) |
| 212 | `blt x2, x1, 0x1b4` | 000 PC | 436 (taken; branch at 428) |
| 214 | `bge x1, x2, 0x1bc` | 000 PC | 444 (taken; branch at 436) |
| 216 | `bltu x1, x2, 0x1c4` | 000 PC | 452 (taken; branch at 444) |
| 218 | `bgeu x2, x1, 0x1cc` | 000 PC | 460 (taken; branch at 452) |
| 220 | `jal x7, 0x1d4` | 000 PC | 468 (jump target) |
| 222 | `jal x7, 0x1d4` | 110 WB data / 111 WB reg | 464 / 7 (return address) |
| 226 | `jalr x9, 0x1(x8)` | 000 PC | 484 (jump target) |
| 228 | `jalr x9, 0x1(x8)` | 110 WB data / 111 WB reg | 480 / 9 (return address) |
| 240 | `mul x3, x10, x11` | 110 WB data / 111 WB reg | -------- (0xFFFFFFEB = -21) / 3 |
| 246 | `mulh x3, x10, x11` | 110 WB data / 111 WB reg | -------- (0xFFFFFFFF = -1) / 3 |
| 252 | `mulhu x3, x10, x11` | 110 WB data / 111 WB reg | 6 / 3 |
| 258 | `mulhsu x3, x11, x10` | 110 WB data / 111 WB reg | -------- (0xFFFFFFFF = -1) / 3 |
| 264 | `div x3, x10, x11` | 110 WB data / 111 WB reg | -------- (0xFFFFFFFE = -2) / 3 |
| 270 | `divu x3, x10, x1` | 110 WB data / 111 WB reg | 0 / 3 |
| 274 | `rem x3, x10, x11` | 110 WB data / 111 WB reg | 1 / 3 |
| 280 | `remu x3, x10, x1` | 110 WB data / 111 WB reg | 7 / 3 |
| 294 | `ebreak` | any | LD15 + all dots ON; PC stays 624 |

Pass: LD15 and the dots turn on at press 294, PC = 624 and never moves.
