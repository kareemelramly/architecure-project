# hazards.s: ALU and load results consumed by a branch / JALR one slot later.
# x31 = failure count (0 = pass), x30 = 0xC0DE when finished.
    .text
    .globl _start
_start:
    li   x31, 0
    la   x20, data
    # ALU -> branch (taken)
    li   x1, 5
    addi x2, x1, -5
    beq  x2, x0, h1
    addi x31, x31, 1
h1: # ALU -> branch (not taken)
    addi x3, x0, 7
    beq  x3, x0, bad2
    j    h2
bad2:
    addi x31, x31, 1
h2: # lw -> branch (taken)
    lw   x4, 0(x20)
    bne  x4, x0, h3
    addi x31, x31, 1
h3: # lw -> branch (not taken)
    lw   x5, 4(x20)
    bne  x5, x0, bad4
    j    h4
bad4:
    addi x31, x31, 1
h4: # lw -> branch with an unrelated instruction between
    lw   x6, 0(x20)
    addi x7, x0, 1
    bne  x6, x0, h5
    addi x31, x31, 1
h5: # two ALU producers, branch uses the older one
    addi x8, x0, 3
    addi x9, x0, 4
    bne  x8, x9, h6
    addi x31, x31, 1
h6: # add -> branch comparing two fresh values
    add  x10, x8, x9
    addi x11, x0, 7
    beq  x10, x11, h7
    addi x31, x31, 1
h7: # ALU -> JALR
    la   x12, h8
    jalr x13, 0(x12)
    addi x31, x31, 1
h8: # lw -> JALR (pointer loaded from memory)
    la   x14, h9
    sw   x14, 8(x20)
    lw   x15, 8(x20)
    jalr x0, 0(x15)
    addi x31, x31, 1
h9: # jal link value used immediately by a branch
    jal  x16, h10
    addi x31, x31, 1
h10:
    la   x17, h10
    bne  x16, x17, h11
    addi x31, x31, 1
h11:
    li   x30, 0xC0DE
    ebreak
    .data
data:
    .word 0x12345678
    .word 0
    .word 0
