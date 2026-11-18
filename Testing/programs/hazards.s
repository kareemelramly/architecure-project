# hazards.s: ALU and load results consumed by the very next instruction
# (branch, JALR, ALU, store data, load address), wrong-path flushes after
# taken branches/jumps, and x0 writes never forwarded.
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
h11: # load -> ALU (distance 1) -> store data (distance 1)
    lw   x18, 0(x20)
    addi x19, x18, 1
    sw   x19, 4(x20)
    lw   x21, 4(x20)
    li   x22, 0x12345679
    beq  x21, x22, h12
    addi x31, x31, 1
h12: # load -> store data directly, then load back
    lw   x23, 0(x20)
    sw   x23, 8(x20)
    lw   x24, 8(x20)
    beq  x24, x18, h13
    addi x31, x31, 1
h13: # a discarded write to x0 must not feed the branch
    li   x5, 0
    addi x0, x0, 7
    beq  x0, x5, h14
    addi x31, x31, 1
h14: # load result used as the address of the next load (pointer chase)
    sw   x20, 12(x20)
    lw   x25, 12(x20)
    lw   x26, 0(x25)
    li   x27, 0x12345678
    beq  x26, x27, h15
    addi x31, x31, 1
h15: # back-to-back dependent ALU chain (each uses the one just before)
    addi x28, x0, 1
    add  x28, x28, x28
    add  x28, x28, x28
    add  x28, x28, x28
    li   x29, 8
    beq  x28, x29, h16
    addi x31, x31, 1
h16: # store then load of the same address back to back
    sw   x28, 4(x20)
    lw   x29, 4(x20)
    addi x29, x29, -8
    beq  x29, x0, h17
    addi x31, x31, 1
h17: # taken branch: the wrong-path store and add must be flushed
    beq  x0, x0, h18
    sw   x0, 0(x20)
    addi x31, x31, 1
h18:
    lw   x26, 0(x20)
    beq  x26, x27, h19
    addi x31, x31, 1
h19: # JAL then JALR straight after a load of the return address
    jal  x1, h20
    j    h21
h20:
    sw   x1, 8(x20)
    lw   x2, 8(x20)
    jalr x0, 0(x2)
    addi x31, x31, 1
h21:
    li   x30, 0xC0DE
    ebreak
    .data
data:
    .word 0x12345678
    .word 0
    .word 0
    .word 0
