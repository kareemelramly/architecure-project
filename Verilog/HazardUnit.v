/*******************************************************************************
 * Module: HazardUnit.v
 * Project: femtoRV32
 * Author: Mohamed AboElfotouh
 * Description: ID-stage hazard detection for Bonus 4 (branches resolved in ID)
 *              in the 3-stage pipeline. The only hazard left is a branch or
 *              JALR in ID (C1 of Stage 0) whose operand is being loaded by
 *              the Stage 1 instruction: the load data is read from memory in
 *              that same C1, so the branch waits one slot. ALU results are
 *              forwarded from EX_MEM and need no stall, and ordinary
 *              instructions never stall (EX forwards load data from MEM_WB).
 *              stall keeps the PC (same word refetched) and puts a bubble
 *              into ID_EX.
 *
 * Change history:
 *   11/13/26 - Created ID-stage load-use and branch stall detection (5 stages)
 *   11/16/26 - 3-stage pipeline: reduced to the load -> branch/JALR rule
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module HazardUnit(
    input  [31:0] idInst,
    input         idValid,
    input         stage1MemRead,
    input  [4:0]  stage1Rd,
    output        stall
);

    wire [4:0] opcode;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire       isBranch;
    wire       isJalr;
    wire       match;

    assign opcode   = idInst[6:2];
    assign rs1      = idInst[19:15];
    assign rs2      = idInst[24:20];
    assign isBranch = idValid && (opcode == `OPC_BRANCH);
    assign isJalr   = idValid && (opcode == `OPC_JALR);

    assign match = (stage1Rd != 5'd0) &&
                   (((isBranch || isJalr) && (stage1Rd == rs1)) ||
                    (isBranch && (stage1Rd == rs2)));

    assign stall = stage1MemRead && match;

endmodule
