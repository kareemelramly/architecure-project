# wave.s: short program for the report waveforms
    .text
_start:
    li   x2, 10
    li   x3, 3          # loop counter
loop:
    lw   x1, 0x300(x0)  # x1 = 10
    beq  x1, x2, skip   # load right before branch: ID mode stalls 1 slot
    addi x9, x0, 99     # skipped
skip:
    addi x3, x3, -1
    bne  x3, x0, loop   # backward branch: EX mode mispredicts cold, then predicted
    ebreak
    .data
    .word 10
