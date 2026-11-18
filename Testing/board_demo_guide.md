# Board demo: step-by-step expected values (Nexys A7-100T)

Program: PROGRAM_FILE = "demo" (default in datapath_board_pipelined.v).

```
addr  instruction              what it shows
0x00  addi x1, x0, 5           x1 = 5
0x04  lw   x2, 0x300(x0)       x2 = 7 (memory word at 0x300)
0x08  add  x3, x2, x1          x3 = 12   load -> ALU, forwarded from memory
0x0C  beq  x3, x3, skip        taken     ALU -> branch, forwarded from EX_MEM, decided in ID
0x10  addi x31, x0, 1          never fetched (branch decided before the next fetch)
0x14  sw   x3, 0x304(x0)       mem[0x304] = 12   x3 from the register file (distance 2)
0x18  lw   x4, 0x304(x0)       x4 = 12
0x1C  bne  x4, x3, fail        not taken  load -> branch, forwarded from memory
0x20  addi x5, x0, 12          x5 = 12
0x24  addi x6, x0, 1           x6 = 1
0x28  beq  x5, x3, ok          taken     x5 written back in the C0 just before this ID
0x2C  addi x31, x0, 1          never fetched (fail path)
0x30  lui  x30, 0xC            x30 = 49152
0x34  addi x30, x30, 0xDE      x30 = 49374 (0xC0DE)
0x38  ebreak                   CPU halts: LD15 and decimal points on
```

## Switches

| Switch | Use |
|---|---|
| SW15 | reset: up = held in reset, down = run |
| BTNC | one press = one CPU clock cycle |
| SW0 | LEDs: down = instruction bits 14..0, up = bits 30..16 |
| SW3 SW2 SW1 | display view (decimal), see below |

| SW3 SW2 SW1 | View | Meaning |
|---|---|---|
| down down down | 0 PC | address being fetched (C0); in C1 already the next address |
| down down up | 1 Inst | instruction in ID |
| down up down | 2 EX | EX result (ALU result, PC + 4 for jumps, imm for LUI) |
| down up up | 3 MemAddr | memory address: PC in C0, load/store address in C1 |
| up down down | 4 MemData | memory output: instruction in C0, load data in C1 |
| up down up | 5 Store | store data (meaningful only when a store is in MEM) |
| up up down | 6 WB data | value written to the register file |
| up up up | 7 WB reg | register number written (0 = no write) |

`--------` = value above 99,999,999 (most instruction words): read them on the LEDs.
LD15 and all decimal points = halted.

## Procedure

1. SW15 up, then down. You are at press 0.
2. Press BTNC once per row and compare. Choose the view with SW3..SW1.
3. Suggested views: PC at presses 6 to 8 and 18 to 20 (taken branches, 0x10
   and 0x2C skipped), MemAddr/MemData at 5 and 13 (loads), MemAddr/Store at 11
   (store), WB data + WB reg at even presses (register writes).
4. Pass: LD15 and the dots turn on at press 26 with WB data = 49374 and
   WB reg = 30, and PC stays 60.

## Expected values after each press

Values are what the display shows in each view. Odd presses are C1, even
presses C0. A value in a view that does not apply at that moment (for example
EX at press 26, store data when no store is in MEM) is leftover data: ignore
it.

| Press | Phase | Happening | 0 PC | 1 Inst | 2 EX | 3 MemAddr | 4 MemData | 5 Store | 6 WB data | 7 WB reg | LD15 | LD14..LD0 (SW0 down) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | C0 | IF addi | 0 | 0 | 0 | 0 | 5243027 | 0 | 0 | 0 | 0 | 000000000000000 |
| 1 | C1 | ID addi x1, x0, 5 | 4 | 5243027 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 000000010010011 |
| 2 | C0 | IF lw, EX addi | 4 | 5243027 | 5 | 4 | -------- | 0 | 0 | 0 | 0 | 000000010010011 |
| 3 | C1 | ID lw x2, 0x300(x0), MEM addi | 8 | -------- | 5 | 5 | 0 | 0 | 0 | 0 | 0 | 010000100000011 |
| 4 | C0 | IF add, EX lw, WB addi | 8 | -------- | 768 | 8 | 1114547 | 0 | 5 | 1 | 0 | 010000100000011 |
| 5 | C1 | ID add x3, x2, x1, MEM lw | 12 | 1114547 | 768 | 768 | 7 | 0 | 5 | 1 | 0 | 000000110110011 |
| 6 | C0 | IF beq, EX add, WB lw | 12 | 1114547 | 12 | 12 | 3245155 | 0 | 7 | 2 | 0 | 000000110110011 |
| 7 | C1 | ID beq x3, x3, skip, MEM add | 16 | 3245155 | 12 | 12 | 0 | 5 | 7 | 2 | 0 | 000010001100011 |
| 8 | C0 | IF sw, EX beq, WB add | 20 | 3245155 | 0 | 20 | -------- | 5 | 12 | 3 | 0 | 000010001100011 |
| 9 | C1 | ID sw x3, 0x304(x0), MEM beq | 24 | -------- | 0 | 0 | 0 | 12 | 12 | 3 | 0 | 010001000100011 |
| 10 | C0 | IF lw, EX sw, WB beq | 24 | -------- | 772 | 24 | -------- | 12 | 0 | 0 | 0 | 010001000100011 |
| 11 | C1 | ID lw x4, 0x304(x0), MEM sw | 28 | -------- | 772 | 772 | 0 | 12 | 0 | 0 | 0 | 010001000000011 |
| 12 | C0 | IF bne, EX lw, WB sw | 28 | -------- | 772 | 28 | 3283043 | 12 | 772 | 0 | 0 | 010001000000011 |
| 13 | C1 | ID bne x4, x3, fail, MEM lw | 32 | 3283043 | 772 | 772 | 12 | 0 | 772 | 0 | 0 | 001100001100011 |
| 14 | C0 | IF addi, EX bne, WB lw | 32 | 3283043 | 0 | 32 | 12583571 | 0 | 12 | 4 | 0 | 001100001100011 |
| 15 | C1 | ID addi x5, x0, 12, MEM bne | 36 | 12583571 | 0 | 0 | 0 | 12 | 12 | 4 | 0 | 000001010010011 |
| 16 | C0 | IF addi, EX addi, WB bne | 36 | 12583571 | 12 | 36 | 1049363 | 12 | 0 | 0 | 0 | 000001010010011 |
| 17 | C1 | ID addi x6, x0, 1, MEM addi | 40 | 1049363 | 12 | 12 | 0 | 0 | 0 | 0 | 0 | 000001100010011 |
| 18 | C0 | IF beq, EX addi, WB addi | 40 | 1049363 | 1 | 40 | 3310691 | 0 | 12 | 5 | 0 | 000001100010011 |
| 19 | C1 | ID beq x5, x3, ok, MEM addi | 44 | 3310691 | 1 | 1 | 0 | 5 | 12 | 5 | 0 | 000010001100011 |
| 20 | C0 | IF lui, EX beq, WB addi | 48 | 3310691 | 0 | 48 | 53047 | 5 | 1 | 6 | 0 | 000010001100011 |
| 21 | C1 | ID lui x30, 0xC, MEM beq | 52 | 53047 | 0 | 0 | 0 | 12 | 1 | 6 | 0 | 100111100110111 |
| 22 | C0 | IF addi, EX lui, WB beq | 52 | 53047 | 49152 | 52 | -------- | 12 | 0 | 0 | 0 | 100111100110111 |
| 23 | C1 | ID addi x30, x30, 0xDE, MEM lui | 56 | -------- | 49152 | 0 | 0 | 0 | 0 | 0 | 0 | 000111100010011 |
| 24 | C0 | IF ebreak, EX addi, WB lui | 56 | -------- | 49374 | 56 | 1048691 | 0 | 49152 | 30 | 0 | 000111100010011 |
| 25 | C1 | ID ebreak, MEM addi | 60 | 1048691 | 49374 | 222 | 0 | 49152 | 49152 | 30 | 0 | 000000001110011 |
| 26 | C0 | EX ebreak, WB addi | 60 | 1048691 | 5 | 60 | 0 | 49152 | 49374 | 30 | 1 | 000000001110011 |
| 27 | C1 | MEM ebreak | 60 | 0 | 5 | 5 | 0 | 5 | 49374 | 30 | 1 | 000000000000000 |
| 28 | C0 | WB ebreak | 60 | 0 | 0 | 60 | 0 | 5 | 5 | 0 | 1 | 000000000000000 |
