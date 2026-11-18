# full_test.s: program for pipeline_tb.v, built from all_instr.s,
# nops_halt.s and hazards.s plus extra branch cases.
# Part 1: ECALL, FENCE, FENCE.TSO, PAUSE execute as NOPs
# Part 2: every RV32I and RV32M (Bonus 2) instruction
# Part 3: every branch not taken, and a backward taken loop
#         (Bonus 4: branches resolved in ID, no lost cycle)
# Part 4: data hazards (ALU/load results used by the next instruction,
#         including branches and JALR resolved in ID)
# x31 = failure count (0 = pass), x30 = 0xC0DE when finished.
# Code at 0x0000, data at 0x1000 (full_test.ld); simulate with
# ADDR_BITS = 13.
    .text
    .globl _start
_start:
    li   x31, 0
    # ---- Part 1: NOP-like system instructions ----
    li   x1, 1
    ecall
    addi x1, x1, 1
    fence
    addi x1, x1, 1
    .word 0x8330000f   # fence.tso
    addi x1, x1, 1
    .word 0x0100000f   # pause
    addi x1, x1, 1
    li   x2, 5
    bne  x1, x2, fail
    # ---- Part 2: every instruction ----
    la   x20, adata
    li   x1, 12
    li   x2, -5
    # R-type
    add  x3, x1, x2      # 7
    li   x4, 7
    bne  x3, x4, fail
    sub  x3, x1, x2      # 17
    li   x4, 17
    bne  x3, x4, fail
    sll  x3, x1, x1      # 12<<12 = 49152
    li   x4, 49152
    bne  x3, x4, fail
    slt  x3, x2, x1      # 1
    li   x4, 1
    bne  x3, x4, fail
    sltu x3, x2, x1      # 0
    bne  x3, x0, fail
    xor  x3, x1, x2      # 12 ^ -5 = -9
    li   x4, -9
    bne  x3, x4, fail
    srl  x3, x2, x4      # shift amount -9&31 = 23 -> 0x1FF
    li   x4, 0x1FF
    bne  x3, x4, fail
    sra  x3, x2, x1      # -5 >> 12 = -1
    li   x4, -1
    bne  x3, x4, fail
    or   x3, x1, x2      # -1
    li   x4, -1
    bne  x3, x4, fail
    and  x3, x1, x2      # 8
    li   x4, 8
    bne  x3, x4, fail
    # I-type ALU
    addi x3, x1, -2
    li   x4, 10
    bne  x3, x4, fail
    slti x3, x2, 0
    li   x4, 1
    bne  x3, x4, fail
    sltiu x3, x2, 1
    bne  x3, x0, fail
    xori x3, x1, 5
    li   x4, 9
    bne  x3, x4, fail
    ori  x3, x1, 3
    li   x4, 15
    bne  x3, x4, fail
    andi x3, x1, 6
    li   x4, 4
    bne  x3, x4, fail
    slli x3, x1, 2
    li   x4, 48
    bne  x3, x4, fail
    srli x3, x1, 2
    li   x4, 3
    bne  x3, x4, fail
    srai x3, x2, 1
    li   x4, -3
    bne  x3, x4, fail
    # LUI / AUIPC
    lui  x3, 0x12345
    li   x4, 0x12345000
    bne  x3, x4, fail
    auipc x3, 0
    jal  x5, 4           # x5 = address of next instruction
    addi x5, x5, -8      # address of the auipc
    bne  x3, x5, fail
    # Loads / stores
    li   x6, 0x80F1F2F3
    sw   x6, 0(x20)
    lw   x3, 0(x20)
    bne  x3, x6, fail
    lb   x3, 0(x20)      # 0xF3 -> -13
    li   x4, -13
    bne  x3, x4, fail
    lbu  x3, 0(x20)
    li   x4, 0xF3
    bne  x3, x4, fail
    lh   x3, 2(x20)      # 0x80F1 sign-extended
    li   x4, 0xFFFF80F1
    bne  x3, x4, fail
    lhu  x3, 2(x20)
    li   x4, 0x80F1
    bne  x3, x4, fail
    sb   x1, 4(x20)
    sh   x2, 6(x20)
    lw   x3, 4(x20)      # bytes: 0C 00 FB FF
    li   x4, 0xFFFB000C
    bne  x3, x4, fail
    # Branches
    beq  x1, x1, a_b1
    j    fail
a_b1: bne  x1, x2, a_b2
    j    fail
a_b2: blt  x2, x1, a_b3
    j    fail
a_b3: bge  x1, x2, a_b4
    j    fail
a_b4: bltu x1, x2, a_b5
    j    fail
a_b5: bgeu x2, x1, a_b6
    j    fail
a_b6: # JAL / JALR link values
    jal  x7, a_b7
    j    fail
a_b7: la   x8, a_b8
    jalr x9, 1(x8)       # target a_b8 + 1: JALR must clear bit 0
a_ret9:
    j    fail
a_b8: la   x4, a_ret9        # link value = address after the jalr
    bne  x9, x4, fail
    # RV32M
    li   x10, 7
    li   x11, -3
    mul  x3, x10, x11
    li   x4, -21
    bne  x3, x4, fail
    mulh x3, x10, x11
    li   x4, -1
    bne  x3, x4, fail
    mulhu x3, x10, x11
    li   x4, 6
    bne  x3, x4, fail
    mulhsu x3, x11, x10
    li   x4, -1
    bne  x3, x4, fail
    div  x3, x10, x11
    li   x4, -2
    bne  x3, x4, fail
    divu x3, x10, x1
    bne  x3, x0, fail
    rem  x3, x10, x11
    li   x4, 1
    bne  x3, x4, fail
    remu x3, x10, x1
    li   x4, 7
    bne  x3, x4, fail
    # x0 is never written
    addi x0, x0, 5
    bne  x0, x0, fail
    # ---- Part 3: branches not taken, and a backward loop ----
    li   x1, 12
    li   x2, -5
    beq  x1, x2, fail
    bne  x1, x1, fail
    blt  x1, x2, fail
    bge  x2, x1, fail
    bltu x2, x1, fail
    bgeu x1, x2, fail
    li   x5, 0
    li   x6, 4
loop:
    addi x5, x5, 1
    blt  x5, x6, loop      # backward, taken 3 times
    bne  x5, x6, fail
    # ---- Part 4: data hazards ----
    la   x20, hdata
    # ALU -> branch (taken)
    li   x1, 5
    addi x2, x1, -5
    beq  x2, x0, z_h1
    addi x31, x31, 1
z_h1: # ALU -> branch (not taken)
    addi x3, x0, 7
    beq  x3, x0, z_bad2
    j    z_h2
z_bad2:
    addi x31, x31, 1
z_h2: # lw -> branch (taken)
    lw   x4, 0(x20)
    bne  x4, x0, z_h3
    addi x31, x31, 1
z_h3: # lw -> branch (not taken)
    lw   x5, 4(x20)
    bne  x5, x0, z_bad4
    j    z_h4
z_bad4:
    addi x31, x31, 1
z_h4: # lw -> branch with an unrelated instruction between
    lw   x6, 0(x20)
    addi x7, x0, 1
    bne  x6, x0, z_h5
    addi x31, x31, 1
z_h5: # two ALU producers, branch uses the older one
    addi x8, x0, 3
    addi x9, x0, 4
    bne  x8, x9, z_h6
    addi x31, x31, 1
z_h6: # add -> branch comparing two fresh values
    add  x10, x8, x9
    addi x11, x0, 7
    beq  x10, x11, z_h7
    addi x31, x31, 1
z_h7: # ALU -> JALR
    la   x12, z_h8
    jalr x13, 0(x12)
    addi x31, x31, 1
z_h8: # lw -> JALR (pointer loaded from memory)
    la   x14, z_h9
    sw   x14, 8(x20)
    lw   x15, 8(x20)
    jalr x0, 0(x15)
    addi x31, x31, 1
z_h9: # jal link value used immediately by a branch
    jal  x16, z_h10
    addi x31, x31, 1
z_h10:
    la   x17, z_h10
    bne  x16, x17, z_h11
    addi x31, x31, 1
z_h11: # load -> ALU (distance 1) -> store data (distance 1)
    lw   x18, 0(x20)
    addi x19, x18, 1
    sw   x19, 4(x20)
    lw   x21, 4(x20)
    li   x22, 0x12345679
    beq  x21, x22, z_h12
    addi x31, x31, 1
z_h12: # load -> store data directly, then load back
    lw   x23, 0(x20)
    sw   x23, 8(x20)
    lw   x24, 8(x20)
    beq  x24, x18, z_h13
    addi x31, x31, 1
z_h13: # a discarded write to x0 must not feed the branch
    li   x5, 0
    addi x0, x0, 7
    beq  x0, x5, z_h14
    addi x31, x31, 1
z_h14: # load result used as the address of the next load (pointer chase)
    sw   x20, 12(x20)
    lw   x25, 12(x20)
    lw   x26, 0(x25)
    li   x27, 0x12345678
    beq  x26, x27, z_h15
    addi x31, x31, 1
z_h15: # back-to-back dependent ALU chain (each uses the one just before)
    addi x28, x0, 1
    add  x28, x28, x28
    add  x28, x28, x28
    add  x28, x28, x28
    li   x29, 8
    beq  x28, x29, z_h16
    addi x31, x31, 1
z_h16: # store then load of the same address back to back
    sw   x28, 4(x20)
    lw   x29, 4(x20)
    addi x29, x29, -8
    beq  x29, x0, z_h17
    addi x31, x31, 1
z_h17: # taken branch: the wrong-path store and add must be flushed
    beq  x0, x0, z_h18
    sw   x0, 0(x20)
    addi x31, x31, 1
z_h18:
    lw   x26, 0(x20)
    beq  x26, x27, z_h19
    addi x31, x31, 1
z_h19: # JAL then JALR straight after a load of the return address
    jal  x1, z_h20
    j    z_h21
z_h20:
    sw   x1, 8(x20)
    lw   x2, 8(x20)
    jalr x0, 0(x2)
    addi x31, x31, 1
z_h21:
    j    done
fail:
    addi x31, x31, 1
done:
    li   x30, 0xC0DE
    ebreak
    addi x31, x31, 100     # must never execute
    .data
adata:
    .word 0
    .word 0
hdata:
    .word 0x12345678
    .word 0
    .word 0
    .word 0
