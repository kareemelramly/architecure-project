/*******************************************************************************
 * Module: control_unit.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Main Control Unit generating CPU datapath control signals.
 *
 * Change history:
 *   10/26/26 - Base control unit for R-type, loads, stores, BEQ
 *   10/27/26 - Added halt and SYSTEM decode
 *   10/29/26 - Added U-type and Jump control signals (LUI, AUIPC, JAL, JALR)
 *   10/30/26 - Merged I-type control decoding
 *   11/01/26 - Changed ALUSel to 5 bits to handle RV32M
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module control_unit(
    input  [31:0] inst,
    output reg    branch,
    output reg    memRead,
    output reg    memWrite,
    output reg    aluSource,
    output reg    aluSrcA,
    output reg    regWrite,
    output reg    isJal,
    output reg    isJalr,
    output reg    halt,
    output reg [1:0] memToReg,
    output reg [1:0] aluOp
);

    wire [4:0] opcode;
    assign opcode = inst[6:2];

    always @* begin
        branch    = 1'b0;
        memRead   = 1'b0;
        memWrite  = 1'b0;
        aluSource = 1'b0;
        aluSrcA   = 1'b0;
        regWrite  = 1'b0;
        isJal     = 1'b0;
        isJalr    = 1'b0;
        halt      = 1'b0;
        memToReg  = `WB_ALU;
        aluOp     = `ALUOP_ADD;

        case (opcode)
            `OPC_OP: begin
                regWrite = 1'b1;
                aluOp    = `ALUOP_RTYPE;
            end

            `OPC_OP_IMM: begin
                regWrite  = 1'b1;
                aluSource = 1'b1;
                aluOp     = `ALUOP_ITYPE;
            end

            `OPC_LOAD: begin
                memRead   = 1'b1;
                memToReg  = `WB_MEM;
                aluSource = 1'b1;
                regWrite  = 1'b1;
                aluOp     = `ALUOP_ADD;
            end

            `OPC_STORE: begin
                memWrite  = 1'b1;
                aluSource = 1'b1;
                aluOp     = `ALUOP_ADD;
            end

            `OPC_BRANCH: begin
                branch = 1'b1;
                aluOp  = `ALUOP_BRANCH;
            end

            `OPC_LUI: begin
                regWrite = 1'b1;
                memToReg = `WB_IMM;
            end

            `OPC_AUIPC: begin
                regWrite  = 1'b1;
                aluSrcA   = 1'b1;
                aluSource = 1'b1;
                aluOp     = `ALUOP_ADD;
                memToReg  = `WB_ALU;
            end

            `OPC_JAL: begin
                isJal    = 1'b1;
                regWrite = 1'b1;
                memToReg = `WB_PC4;
            end

            `OPC_JALR: begin
                isJalr   = 1'b1;
                regWrite = 1'b1;
                memToReg = `WB_PC4;
            end

            `OPC_SYSTEM: begin
                if ((inst[14:12] == 3'b000) &&
                    (inst[11:7]  == 5'b00000) &&
                    (inst[19:15] == 5'b00000) &&
                    (inst[31:21] == 11'b0)) begin
                    halt = 1'b1;
                end
            end

            `OPC_MISC_MEM: begin
                // FENCE / FENCE.TSO / PAUSE execute as safe NOP
            end

            default: begin
                // All defaults remain 0
            end
        endcase
    end

endmodule