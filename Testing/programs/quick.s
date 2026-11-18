# quick.s: every RV32I and RV32M instruction once, for a short board test
# (about 112 BTNC presses). Operands are small so most results show on the
# decimal display. Taken branches and jumps skip one instruction (never
# fetched: branches are resolved in ID).
    .text
    .globl _start
_start:
    addi  x1, x0, 12        # x1 = 12
    addi  x2, x0, 5         # x2 = 5
    addi  x4, x0, 2         # x4 = 2
    # R-type
    add   x3, x1, x2        # 17
    sub   x3, x1, x2        # 7
    sll   x3, x2, x2        # 160
    slt   x3, x2, x1        # 1
    sltu  x3, x1, x2        # 0
    xor   x3, x1, x2        # 9
    srl   x3, x1, x4        # 3
    sra   x3, x1, x4        # 3
    or    x3, x1, x2        # 13
    and   x3, x1, x2        # 4
    # I-type
    slti  x3, x2, 6         # 1
    sltiu x3, x2, 4         # 0
    xori  x3, x1, 1         # 13
    ori   x3, x2, 8         # 13
    andi  x3, x1, 7         # 4
    slli  x3, x2, 3         # 40
    srli  x3, x1, 2         # 3
    srai  x3, x1, 1         # 6
    # U-type
    lui   x3, 1             # 4096
    auipc x3, 0             # its own address
    # stores and loads (data area 0x300)
    sw    x1, 0x300(x0)     # mem[0x300] = 12
    sh    x2, 0x304(x0)     # mem[0x304] = 5
    sb    x4, 0x306(x0)     # mem[0x306] = 2
    lw    x3, 0x300(x0)     # 12
    lh    x3, 0x304(x0)     # 5
    lb    x3, 0x306(x0)     # 2
    lhu   x3, 0x304(x0)     # 5
    lbu   x3, 0x306(x0)     # 2
    # branches, all taken, each skips one instruction
    beq   x1, x1, b1
    addi  x31, x0, 1
b1: bne   x1, x2, b2
    addi  x31, x0, 1
b2: blt   x2, x1, b3
    addi  x31, x0, 1
b3: bge   x1, x2, b4
    addi  x31, x0, 1
b4: bltu  x2, x1, b5
    addi  x31, x0, 1
b5: bgeu  x1, x2, b6
    addi  x31, x0, 1
b6: # jumps
    jal   x5, j1            # x5 = return address
    addi  x31, x0, 1
j1: auipc x6, 0             # x6 = address of this auipc
    jalr  x7, 12(x6)        # jump to x6 + 12, x7 = return address
    addi  x31, x0, 1
    # RV32M (Bonus 2)
    lui   x8, 0x10          # x8 = 65536
    mul   x3, x1, x2        # 60
    mulh  x3, x8, x8        # 1   (65536 * 65536 = 2^32, upper word)
    mulhsu x3, x8, x8       # 1
    mulhu x3, x8, x8        # 1
    div   x3, x1, x4        # 6
    divu  x3, x1, x2        # 2
    rem   x3, x1, x2        # 2
    remu  x3, x2, x4        # 1
    # NOP-like system instructions
    ecall
    fence
    .word 0x8330000f        # fence.tso
    .word 0x0100000f        # pause
    li    x30, 0xC0DE       # finished marker (x30 = 49374)
    ebreak
