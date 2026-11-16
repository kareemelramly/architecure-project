# all_instr.s: one self-checked instance of every RV32I/M operation.
# x31 = failure count (0 = pass), x30 = 0xC0DE when finished.
    .text
    .globl _start
_start:
    li   x31, 0
    la   x20, data
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
    beq  x1, x1, b1
    j    fail
b1: bne  x1, x2, b2
    j    fail
b2: blt  x2, x1, b3
    j    fail
b3: bge  x1, x2, b4
    j    fail
b4: bltu x1, x2, b5
    j    fail
b5: bgeu x2, x1, b6
    j    fail
b6: # JAL / JALR link values
    jal  x7, b7
    j    fail
b7: la   x8, b8
    jalr x9, 0(x8)
    j    fail
b8: # RV32M
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
    j    done
fail:
    addi x31, x31, 1
done:
    li   x30, 0xC0DE
    ebreak
    .data
data:
    .word 0
    .word 0
