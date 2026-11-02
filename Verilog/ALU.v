/*******************************************************************************
 * Module: ALU.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: 32-bit ALU supporting RV32I and RV32M extensions.
 *
 * Change history:
 *   10/26/26 - Initial ALU with ADD, SUB, AND, OR
 *   10/28/26 - Added XOR, shifts (SLL, SRL, SRA), comparisons (SLT, SLTU)
 *   10/30/26 - Merged RV32M multiplication, division, and remainder
 *   11/01/26 - Handled division by zero and signed overflow edge cases
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module ALU #(
    parameter N = 32
)(
    input  [4:0]   aluSel,
    input  [N-1:0] in1,
    input  [N-1:0] in2,
    output reg [N-1:0] result,
    output         zero
);

    wire signed [63:0] mul_ss;
    wire signed [63:0] mul_su;
    wire [63:0]        mul_uu;

    assign mul_ss = $signed(in1) * $signed(in2);
    assign mul_su = $signed(in1) * $signed({1'b0, in2});
    assign mul_uu = in1 * in2;

    always @* begin
        case (aluSel)
            `ALU_ADD: begin
                result = in1 + in2;
            end
            `ALU_SUB: begin
                result = in1 - in2;
            end
            `ALU_AND: begin
                result = in1 & in2;
            end
            `ALU_OR: begin
                result = in1 | in2;
            end
            `ALU_XOR: begin
                result = in1 ^ in2;
            end
            `ALU_SLL: begin
                result = in1 << in2[4:0];
            end
            `ALU_SRL: begin
                result = in1 >> in2[4:0];
            end
            `ALU_SRA: begin
                result = $signed(in1) >>> in2[4:0];
            end
            `ALU_SLT: begin
                result = ($signed(in1) < $signed(in2)) ? 32'd1 : 32'd0;
            end
            `ALU_SLTU: begin
                result = (in1 < in2) ? 32'd1 : 32'd0;
            end
            `ALU_MUL: begin
                result = in1 * in2;
            end
            `ALU_MULH: begin
                result = mul_ss[63:32];
            end
            `ALU_MULHSU: begin
                result = mul_su[63:32];
            end
            `ALU_MULHU: begin
                result = mul_uu[63:32];
            end
            `ALU_DIV: begin
                if (in2 == 32'd0) begin
                    result = 32'hFFFFFFFF;
                end else if ((in1 == 32'h80000000) && (in2 == 32'hFFFFFFFF)) begin
                    result = 32'h80000000;
                end else begin
                    result = $signed(in1) / $signed(in2);
                end
            end
            `ALU_DIVU: begin
                if (in2 == 32'd0) begin
                    result = 32'hFFFFFFFF;
                end else begin
                    result = in1 / in2;
                end
            end
            `ALU_REM: begin
                if (in2 == 32'd0) begin
                    result = in1;
                end else if ((in1 == 32'h80000000) && (in2 == 32'hFFFFFFFF)) begin
                    result = 32'd0;
                end else begin
                    result = $signed(in1) % $signed(in2);
                end
            end
            `ALU_REMU: begin
                if (in2 == 32'd0) begin
                    result = in1;
                end else begin
                    result = in1 % in2;
                end
            end
            default: begin
                result = 32'd0;
            end
        endcase
    end

    assign zero = (result == 32'd0);

endmodule