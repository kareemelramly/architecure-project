/*******************************************************************************
 * Module: alu_unit.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: ALU Control Decoder for R-type, I-type, M-extension, and branches.
 *
 * Change history:
 *   10/26/26 - Initial ALU decoder
 *   10/28/26 - Added shift, comparison, and I-type decoding
 *   10/30/26 - Merged RV32M opcode checking
 *   11/01/26 - Cleaned up redundant decoder cases
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module alu_unit(
    input  [1:0]  aluOp,
    input  [31:0] inst,
    output reg [4:0] aluSelection
);

    wire [2:0] funct3;
    wire [6:0] funct7;

    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];

    always @* begin
        aluSelection = `ALU_ADD;

        case (aluOp)
            `ALUOP_ADD: begin
                aluSelection = `ALU_ADD;
            end

            `ALUOP_BRANCH: begin
                aluSelection = `ALU_SUB;
            end

            `ALUOP_RTYPE: begin
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000:  aluSelection = `ALU_MUL;
                        3'b001:  aluSelection = `ALU_MULH;
                        3'b010:  aluSelection = `ALU_MULHSU;
                        3'b011:  aluSelection = `ALU_MULHU;
                        3'b100:  aluSelection = `ALU_DIV;
                        3'b101:  aluSelection = `ALU_DIVU;
                        3'b110:  aluSelection = `ALU_REM;
                        3'b111:  aluSelection = `ALU_REMU;
                        default: aluSelection = `ALU_ADD;
                    endcase
                end else begin
                    case (funct3)
                        3'b000:  aluSelection = (inst[30]) ? `ALU_SUB : `ALU_ADD;
                        3'b001:  aluSelection = `ALU_SLL;
                        3'b010:  aluSelection = `ALU_SLT;
                        3'b011:  aluSelection = `ALU_SLTU;
                        3'b100:  aluSelection = `ALU_XOR;
                        3'b101:  aluSelection = (inst[30]) ? `ALU_SRA : `ALU_SRL;
                        3'b110:  aluSelection = `ALU_OR;
                        3'b111:  aluSelection = `ALU_AND;
                        default: aluSelection = `ALU_ADD;
                    endcase
                end
            end

            `ALUOP_ITYPE: begin
                case (funct3)
                    3'b000:  aluSelection = `ALU_ADD;
                    3'b001:  aluSelection = `ALU_SLL;
                    3'b010:  aluSelection = `ALU_SLT;
                    3'b011:  aluSelection = `ALU_SLTU;
                    3'b100:  aluSelection = `ALU_XOR;
                    3'b101:  aluSelection = (inst[30]) ? `ALU_SRA : `ALU_SRL;
                    3'b110:  aluSelection = `ALU_OR;
                    3'b111:  aluSelection = `ALU_AND;
                    default: aluSelection = `ALU_ADD;
                endcase
            end

            default: begin
                aluSelection = `ALU_ADD;
            end
        endcase
    end

endmodule