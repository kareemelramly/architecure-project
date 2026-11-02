/*******************************************************************************
 * Module: Nbit_mux2x1.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Parameterized N-bit 2-to-1 multiplexer.
 *
 * Change history:
 *   10/26/26 - Initial multiplexer design
 *   11/01/26 - Formatted to strictly follow coding guidelines
 ******************************************************************************/

`timescale 1ns / 1ps

module Nbit_mux2x1 #(
    parameter N = 32
)(
    input          s,
    input  [N-1:0] a,
    input  [N-1:0] b,
    output [N-1:0] c
);

    genvar i;

    generate
        for (i = 0; i < N; i = i + 1) begin: Gen_Muxes
            mux2x1 u_bit_mux(
                .s(s),
                .a(a[i]),
                .b(b[i]),
                .c(c[i])
            );
        end
    endgenerate

endmodule