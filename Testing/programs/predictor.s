# predictor.s: drives the 2-bit predictor through its state transitions.
# x31 = failure count (0 = pass), x30 = 0xC0DE when finished.
    .text
    .globl _start
_start:
    li   x31, 0
    # Loop A: backward branch taken 15 times, then falls through
    # (Weakly NT -> Strongly Taken, then one not-taken drops to Weakly Taken)
    li   x5, 0
    li   x6, 16
loopA:
    addi x5, x5, 1
    nop
    bne  x5, x6, loopA
    li   x7, 16
    beq  x5, x7, okA
    addi x31, x31, 1
okA:
    # Loop B: alternating outcome (taken / not taken) defeats the counter
    li   x8, 0
    li   x9, 0
    li   x10, 20
loopB:
    addi x8, x8, 1
    andi x11, x8, 1
    beq  x11, x0, skipB
    addi x9, x9, 1
skipB:
    bne  x8, x10, loopB
    li   x7, 10
    beq  x9, x7, okB
    addi x31, x31, 1
okB:
    # Nested loops: inner 4 iterations, outer 5 -> inner exit mispredicts
    li   x12, 0
    li   x13, 0
outer:
    li   x14, 0
inner:
    addi x13, x13, 1
    addi x14, x14, 1
    li   x15, 4
    bne  x14, x15, inner
    addi x12, x12, 1
    li   x15, 5
    bne  x12, x15, outer
    li   x7, 20
    beq  x13, x7, okC
    addi x31, x31, 1
okC:
    # Forward branch never taken (Strongly NT stays NT)
    li   x16, 0
    li   x17, 8
loopD:
    beq  x0, x17, never
    addi x16, x16, 1
    addi x17, x17, -1
    bne  x17, x0, loopD
never:
    li   x7, 8
    beq  x16, x7, okD
    addi x31, x31, 1
okD:
    li   x30, 0xC0DE
    ebreak
