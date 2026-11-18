/*******************************************************************************
 * Module: ForwardingUnit.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: EX-stage forwarding for the 3-stage pipeline.
 *              An instruction is issued every 2 cycles, so the only result
 *              not yet in the register file when an instruction reads it is
 *              the one of the instruction directly before it. That result
 *              (ALU value or loaded value) sits in MEM_WB while the consumer
 *              is in EX, so a single MEM_WB -> EX path removes every RAW
 *              hazard, load-use included, with no stall.
 *              forwardX = 1: take the MEM_WB write-back value
 *              forwardX = 0: take the value read from the register file
 *
 * Change history:
 *   11/10/26 - Lab 8 version
 *   11/13/26 - Fixed widths, default assignments (no latch), x0 guard
 *   11/18/26 - Reduced to the single MEM_WB source of the 3-stage pipeline
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module ForwardingUnit(
    input  [4:0] exRs1,
    input  [4:0] exRs2,
    input  [4:0] memWbRd,
    input        memWbRegWrite,
    output       forwardA,
    output       forwardB
);

    wire wbWritesReg;

    assign wbWritesReg = memWbRegWrite && (memWbRd != `REG_ZERO);

    assign forwardA = wbWritesReg && (memWbRd == exRs1);
    assign forwardB = wbWritesReg && (memWbRd == exRs2);

endmodule
