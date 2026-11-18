# Quick board test: every instruction once (PROGRAM_FILE = "quick")

Setup: SW15 up then down (= press 0), SW0 any. At each press number set the
view with SW3 SW2 SW1 (1 = up). You can flip the view switches between
presses without pressing BTNC. Display is decimal. Views: 000 PC,
001 instruction in ID, 011 memory address, 101 store data, 110 write-back
data, 111 write-back register.

| Press | Instruction | SW3 SW2 SW1 | Expected |
|---|---|---|---|
| 4 | `li x1, 12` | 110 / 111 | 12 / x1 |
| 6 | `li x2, 5` | 110 / 111 | 5 / x2 |
| 8 | `li x4, 2` | 110 / 111 | 2 / x4 |
| 10 | `add x3, x1, x2` | 110 / 111 | 17 / x3 |
| 12 | `sub x3, x1, x2` | 110 / 111 | 7 / x3 |
| 14 | `sll x3, x2, x2` | 110 / 111 | 160 / x3 |
| 16 | `slt x3, x2, x1` | 110 / 111 | 1 / x3 |
| 18 | `sltu x3, x1, x2` | 110 / 111 | 0 / x3 |
| 20 | `xor x3, x1, x2` | 110 / 111 | 9 / x3 |
| 22 | `srl x3, x1, x4` | 110 / 111 | 3 / x3 |
| 24 | `sra x3, x1, x4` | 110 / 111 | 3 / x3 |
| 26 | `or x3, x1, x2` | 110 / 111 | 13 / x3 |
| 28 | `and x3, x1, x2` | 110 / 111 | 4 / x3 |
| 30 | `slti x3, x2, 6` | 110 / 111 | 1 / x3 |
| 32 | `sltiu x3, x2, 4` | 110 / 111 | 0 / x3 |
| 34 | `xori x3, x1, 1` | 110 / 111 | 13 / x3 |
| 36 | `ori x3, x2, 8` | 110 / 111 | 13 / x3 |
| 38 | `andi x3, x1, 7` | 110 / 111 | 4 / x3 |
| 40 | `slli x3, x2, 3` | 110 / 111 | 40 / x3 |
| 42 | `srli x3, x1, 2` | 110 / 111 | 3 / x3 |
| 44 | `srai x3, x1, 1` | 110 / 111 | 6 / x3 |
| 46 | `lui x3, 1` | 110 / 111 | 4096 / x3 |
| 48 | `auipc x3, 0` | 110 / 111 | 88 / x3 |
| 49 | `sw x1, 768(x0)` | 011 / 101 | 768 / 12 |
| 51 | `sh x2, 772(x0)` | 011 / 101 | 772 / 5 |
| 53 | `sb x4, 774(x0)` | 011 / 101 | 774 / 2 |
| 56 | `lw x3, 768(x0)` | 110 / 111 | 12 / x3 |
| 58 | `lh x3, 772(x0)` | 110 / 111 | 5 / x3 |
| 60 | `lb x3, 774(x0)` | 110 / 111 | 2 / x3 |
| 62 | `lhu x3, 772(x0)` | 110 / 111 | 5 / x3 |
| 64 | `lbu x3, 774(x0)` | 110 / 111 | 2 / x3 |
| 64 | `beq x1, x1 (taken)` | 000 | 132 (skips 128) |
| 66 | `bne x1, x2 (taken)` | 000 | 140 (skips 136) |
| 68 | `blt x2, x1 (taken)` | 000 | 148 (skips 144) |
| 70 | `bge x1, x2 (taken)` | 000 | 156 (skips 152) |
| 72 | `bltu x2, x1 (taken)` | 000 | 164 (skips 160) |
| 74 | `bgeu x1, x2 (taken)` | 000 | 172 (skips 168) |
| 78 | `jal x5, j1` | 110 / 111 | 176 / x5 (return address); PC at press 76 = 180 |
| 80 | `auipc x6, 0` | 110 / 111 | 180 / x6 |
| 82 | `jalr x7, 12(x6)` | 110 / 111 | 188 / x7 (return address); PC at press 80 = 192 |
| 84 | `lui x8, 16` | 110 / 111 | 65536 / x8 |
| 86 | `mul x3, x1, x2` | 110 / 111 | 60 / x3 |
| 88 | `mulh x3, x8, x8` | 110 / 111 | 1 / x3 |
| 90 | `mulhsu x3, x8, x8` | 110 / 111 | 1 / x3 |
| 92 | `mulhu x3, x8, x8` | 110 / 111 | 1 / x3 |
| 94 | `div x3, x1, x4` | 110 / 111 | 6 / x3 |
| 96 | `divu x3, x1, x2` | 110 / 111 | 2 / x3 |
| 98 | `rem x3, x1, x2` | 110 / 111 | 2 / x3 |
| 99 | `ecall` | 001 | 115 |
| 100 | `remu x3, x2, x4` | 110 / 111 | 1 / x3 |
| 101 | `fence` | 001 | -------- (0x0FF0000F) |
| 103 | `fence.tso` | 001 | -------- (0x8330000F) |
| 105 | `pause` | 001 | 16777231 |
| 110 | `lui x30, 12` | 110 / 111 | 49152 / x30 |
| 112 | `addi x30, x30, 222` | 110 / 111 | 49374 / x30 |
| 112 | `ebreak` | any | LD15 + all dots ON, PC = 256 and stays |

Pass: every row matches and LD15 + dots turn on at press 112 with PC = 256.
