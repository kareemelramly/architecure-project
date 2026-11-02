/*******************************************************************************
 * Module: Nbit_shift_left.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Parameterized N-bit left-shift-by-1 module.
 *
 * Change history:
 *   09/22/26 - Initial module implementation
 *   11/01/26 - Renamed and reformatted per Verilog RTL modeling guidelines
 ******************************************************************************/

`timescale 1ns / 1ps

module Nbit_shift_left #(
    parameter N = 32
)(
    input  [N-1:0] a,
    output [N-1:0] c
);

    genvar i;

    generate
        for (i = 0; i < (N - 1); i = i + 1) begin: Gen_Shift_Bits
            assign c[i+1] = a[i];
        end
        assign c[0] = 1'b0;
    endgenerate

endmodule