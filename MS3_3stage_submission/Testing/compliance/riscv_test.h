/*******************************************************************************
 * File: riscv_test.h
 * Project: femtoRV32
 * Description: Minimal test environment for the official riscv-tests rv32ui
 *              programs on femtoRV32 (no CSRs, no traps). A test ends with
 *              EBREAK and leaves the project signature:
 *                pass: x31 = 0,                  x30 = 0xC0DE
 *                fail: x31 = failing test number, x30 = 0x0BAD
 ******************************************************************************/
#ifndef FEMTORV32_RISCV_TEST_H
#define FEMTORV32_RISCV_TEST_H

#define RVTEST_RV64U
#define RVTEST_RV32U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN  .text; .globl _start; _start:
#define RVTEST_CODE_END

#define RVTEST_PASS        li x31, 0; li x30, 0xC0DE; ebreak;
#define RVTEST_FAIL        mv x31, TESTNUM; li x30, 0x0BAD; ebreak;

#define RVTEST_DATA_BEGIN  .data; .align 4;
#define RVTEST_DATA_END

#endif
