# timing.s: straight-line, independent instructions used by pipeline_tb to
# check the 3-stage / 6-cycle timing: instruction k must write its register
# in cycle 2k+4 (IF 2k, ID 2k+1, EX 2k+2, MEM 2k+3, WB 2k+4, 2k+5 unused).
    .text
    .globl _start
_start:
    addi x1, x0, 1
    addi x2, x0, 2
    addi x3, x0, 3
    addi x4, x0, 4
    addi x5, x0, 5
    addi x6, x0, 6
    addi x7, x0, 7
    addi x8, x0, 8
    li   x30, 0xC0DE
    ebreak
