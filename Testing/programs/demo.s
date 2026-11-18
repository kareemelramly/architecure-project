# demo.s: short program for the board demo and the pipeline chart.
# Shows load-use forwarding, ALU -> branch forwarding, a taken branch that
# flushes the wrong-path instruction, a store, and EBREAK.
# Ends with x31 = 0, x30 = 0xC0DE, x3 = 12 and mem[0x304] = 12.
    .text
    .globl _start
_start:
    addi x1, x0, 5
    lw   x2, 0x300(x0)     # x2 = 7
    add  x3, x2, x1        # load result used at once (MEM_WB -> EX)
    beq  x3, x3, skip      # x3 forwarded to the branch, taken
    addi x31, x0, 1        # wrong path: flushed, never executes
skip:
    sw   x3, 0x304(x0)     # x3 is 2 slots old: read from the register file
    li   x30, 0xC0DE
    ebreak
    .data
    .word 7
    .word 0
