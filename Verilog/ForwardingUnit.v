/*******************************************************************************
 * Module: ForwardingUnit.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: ID-stage forwarding for the 3-stage pipeline (Bonus 4:
 *              branches and jumps are resolved in ID, so their operands
 *              must already be correct in ID).
 *              An instruction is issued every 2 cycles. When an instruction
 *              is in ID (C1):
 *                - the instruction 2 before it was written back in the
 *                  previous C0, so the register file already holds it
 *                - the instruction just before it is in MEM (same C1):
 *                    ALU, AUIPC, LUI, JAL, JALR: its result is already in
 *                    EX_MEM (exMemResult)
 *                    load: its data is being read from memory in this same
 *                    C1 (memReadData, the memory output)
 *              So one path from MEM to ID removes every RAW hazard with no
 *              stall. This unit detects the hazard (forwardA/B, internal) and
 *              outputs the correct register values (rs1Data/rs2Data).
 *              Examples (instruction in MEM, then instruction in ID):
 *                add x5, x3, x2 / beq x5, x4, L1
 *                    exMemRd = 5 = rs1  -> rs1Data = exMemResult
 *                lw  x1, 0(x2)  / beq x1, x2, L1
 *                    exMemRd = 1 = rs1, load -> rs1Data = memReadData
 *                    (x2 is not written by the lw: read from the reg file)
 *              x0 is never forwarded (it is never written).
 *
 * Change history:
 *   11/10/26 - Lab 8 version
 *   11/13/26 - Fixed widths, default assignments (no latch), x0 guard
 *   11/18/26 - Reduced to the single MEM_WB source of the 3-stage pipeline
 *   11/18/26 - Moved to ID (Bonus 4): compares the ID source registers
 *              with EX_MEM and selects the forwarded value (ALU result or
 *              load data)
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module ForwardingUnit(
    input  [4:0]  idRs1,          // rs1 of the instruction in ID
    input  [4:0]  idRs2,          // rs2 of the instruction in ID
    input  [31:0] regData1,       // rs1 value from the register file
    input  [31:0] regData2,       // rs2 value from the register file
    input  [4:0]  exMemRd,        // rd of the instruction in MEM
    input         exMemRegWrite,  // the instruction in MEM writes rd
    input         exMemIsLoad,    // the instruction in MEM is a load
    input  [31:0] exMemResult,    // its EX result (ALU, PC + 4, imm)
    input  [31:0] memReadData,    // memory output in this C1 (load data)
    output [31:0] rs1Data,        // correct rs1 value for ID
    output [31:0] rs2Data         // correct rs2 value for ID
);

    wire        memWritesReg;
    wire        forwardA;         // 1: rs1 comes from the instruction in MEM
    wire        forwardB;         // 1: rs2 comes from the instruction in MEM
    wire [31:0] memValue;

    // ---- Hazard detection ----
    assign memWritesReg = exMemRegWrite && (exMemRd != `REG_ZERO);

    assign forwardA = memWritesReg && (exMemRd == idRs1);
    assign forwardB = memWritesReg && (exMemRd == idRs2);

    // ---- Value of the instruction in MEM: loaded data or EX result ----
    assign memValue = (exMemIsLoad) ? memReadData : exMemResult;

    assign rs1Data = (forwardA) ? memValue : regData1;
    assign rs2Data = (forwardB) ? memValue : regData2;

endmodule
