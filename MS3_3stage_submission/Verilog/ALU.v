/*******************************************************************************
 * Module: ALU.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: 32-bit ALU supporting RV32I and RV32M extensions.
 *              Signed multiply / divide work on magnitudes: the operands are
 *              made positive, one unsigned multiplier and one unsigned divider
 *              do the work, and the sign is put back on the result. This
 *              keeps $signed() only around >>> and < (coding guidelines)
 *              and shares one multiplier and one divider between all
 *              RV32M operations.
 *
 * Change history:
 *   10/26/26 - Initial ALU with ADD, SUB, AND, OR
 *   10/28/26 - Added XOR, shifts (SLL, SRL, SRA), comparisons (SLT, SLTU)
 *   10/30/26 - Merged RV32M multiplication, division, and remainder
 *   11/01/26 - Handled division by zero and signed overflow edge cases
 *   11/18/26 - RV32M on magnitudes (no $signed around * / %), one shared
 *              multiplier and divider
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

    wire           in1Signed;   // in1 is read as a signed number
    wire           in2Signed;   // in2 is read as a signed number
    wire           in1Neg;
    wire           in2Neg;
    wire [N-1:0]   in1Mag;
    wire [N-1:0]   in2Mag;
    wire [2*N-1:0] prodMag;
    wire [2*N-1:0] product;
    wire [N-1:0]   quotMag;
    wire [N-1:0]   remMag;
    wire [N-1:0]   quotient;
    wire [N-1:0]   remainder;
    wire           divByZero;

    // MULH, DIV, REM: both signed. MULHSU: in1 signed only.
    assign in1Signed = (aluSel == `ALU_MULH) || (aluSel == `ALU_MULHSU) ||
                       (aluSel == `ALU_DIV)  || (aluSel == `ALU_REM);
    assign in2Signed = (aluSel == `ALU_MULH) ||
                       (aluSel == `ALU_DIV)  || (aluSel == `ALU_REM);

    assign in1Neg = in1Signed & in1[N-1];
    assign in2Neg = in2Signed & in2[N-1];
    assign in1Mag = (in1Neg) ? (~in1 + 1'b1) : in1;
    assign in2Mag = (in2Neg) ? (~in2 + 1'b1) : in2;

    // One unsigned multiplier, sign restored afterwards
    assign prodMag = in1Mag * in2Mag;
    assign product = (in1Neg ^ in2Neg) ? (~prodMag + 1'b1) : prodMag;

    // One unsigned divider. Quotient sign = sign(in1) xor sign(in2),
    // remainder sign = sign(in1). -2^31 / -1 gives 0x80000000, rem 0.
    assign divByZero = (in2 == {N{1'b0}});
    assign quotMag   = (divByZero) ? {N{1'b0}} : (in1Mag / in2Mag);
    assign remMag    = (divByZero) ? {N{1'b0}} : (in1Mag % in2Mag);
    assign quotient  = (in1Neg ^ in2Neg) ? (~quotMag + 1'b1) : quotMag;
    assign remainder = (in1Neg) ? (~remMag + 1'b1) : remMag;

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
                result = product[N-1:0];
            end
            `ALU_MULH, `ALU_MULHSU, `ALU_MULHU: begin
                result = product[2*N-1:N];
            end
            `ALU_DIV, `ALU_DIVU: begin
                result = (divByZero) ? {N{1'b1}} : quotient;
            end
            `ALU_REM, `ALU_REMU: begin
                result = (divByZero) ? in1 : remainder;
            end
            default: begin
                result = 32'd0;
            end
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
