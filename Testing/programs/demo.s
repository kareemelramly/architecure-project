# demo.s: short program for the board demo (step it with BTNC).
# Shows every data-hazard case of the pipeline and a branch resolved in ID:
#   load -> ALU (distance 1)          forwarded from memory to ID
#   ALU  -> branch (distance 1)       forwarded from EX_MEM to ID
#   taken branch in ID                target fetched next, 0 lost cycles
#   ALU  -> store (distance 2)        read from the register file
#   load -> branch (distance 1)       forwarded from memory to ID
#   ALU  -> branch (distance 2)       written back in C0, read in ID in C1
# Ends with x31 = 0, x30 = 0xC0DE, x3 = x4 = x5 = 12 and mem[0x304] = 12.
    .text
    .globl _start
_start:
    addi x1, x0, 5
    lw   x2, 0x300(x0)     # x2 = 7
    add  x3, x2, x1        # x3 = 12, load result used at once
    beq  x3, x3, skip      # x3 used at once by the branch, taken
    addi x31, x0, 1        # never fetched
skip:
    sw   x3, 0x304(x0)     # mem[0x304] = 12, x3 written 2 instructions ago
    lw   x4, 0x304(x0)     # x4 = 12
    bne  x4, x3, fail      # load result used at once by the branch
    addi x5, x0, 12        # x5 = 12
    addi x6, x0, 1         # x6 = 1 (unrelated)
    beq  x5, x3, ok        # x5 written back in the C0 just before ID
fail:
    addi x31, x0, 1
ok:
    li   x30, 0xC0DE
    ebreak
    .data
    .word 7
    .word 0
