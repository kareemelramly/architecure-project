/*******************************************************************************
 * Module: HazardUnit.v
 * Project: femtoRV32
 * Author: Mohamed AboElfotouh
 * Description: ID-stage hazard detection (Bonus 4).
 *              loadUseStall : a load in EX feeds any instruction in ID
 *              branchStall  : a branch/JALR in ID (operands needed in ID)
 *                             depends on an ALU result still in EX, or on a
 *                             load that is in MEM
 *              stall freezes PC + IF_ID and inserts a bubble into ID_EX.
 *
 * Change history:
 *   11/13/26 - Created ID-stage load-use and branch stall detection
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module HazardUnit(
    input  [31:0] idInst,
    input         idValid,
    input         idExMemRead,
    input         idExRegWrite,
    input  [4:0]  idExRd,
    input         exMemMemRead,
    input  [4:0]  exMemRd,
    output        loadUseStall,
    output        branchStall,
    output        stall
);

    wire [4:0] opcode;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire       usesRs1;
    wire       usesRs2;
    wire       readsInId;
    wire       matchEx;
    wire       matchMem;

    assign opcode = idInst[6:2];
    assign rs1    = idInst[19:15];
    assign rs2    = idInst[24:20];

    // Only real source operands count (EBREAK has 1 in the rs2 field)
    assign usesRs1 = idValid &&
                     ((opcode == `OPC_OP)    || (opcode == `OPC_OP_IMM) ||
                      (opcode == `OPC_LOAD)  || (opcode == `OPC_STORE)  ||
                      (opcode == `OPC_BRANCH)|| (opcode == `OPC_JALR));
    assign usesRs2 = idValid &&
                     ((opcode == `OPC_OP)    || (opcode == `OPC_STORE)  ||
                      (opcode == `OPC_BRANCH));
    assign readsInId = idValid &&
                       ((opcode == `OPC_BRANCH) || (opcode == `OPC_JALR));

    assign matchEx  = (idExRd != 5'd0) &&
                      ((usesRs1 && (idExRd == rs1)) || (usesRs2 && (idExRd == rs2)));
    assign matchMem = (exMemRd != 5'd0) &&
                      ((usesRs1 && (exMemRd == rs1)) || (usesRs2 && (exMemRd == rs2)));

    assign loadUseStall = idExMemRead && matchEx;
    assign branchStall  = readsInId &&
                          ((idExRegWrite && matchEx) || (exMemMemRead && matchMem));
    assign stall        = loadUseStall | branchStall;

endmodule
