# nops_halt.s: ECALL, FENCE, FENCE.TSO and PAUSE execute as NOPs; EBREAK halts.
    .text
    .globl _start
_start:
    li   x31, 0
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
    j    done
fail:
    addi x31, x31, 1
done:
    li   x30, 0xC0DE
    ebreak
    addi x31, x31, 100        # must never execute
