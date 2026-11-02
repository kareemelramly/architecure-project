/*******************************************************************************
 * Module: mux2x1.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: 1-bit 2-to-1 multiplexer.
 *
 * Change history:
 *   10/26/26 - Initial 1-bit mux implementation
 *   11/01/26 - Placed into standalone file per guidelines
 ******************************************************************************/

`timescale 1ns / 1ps

module mux2x1(
    input  s,
    input  a,
    input  b,
    output c
);

    assign c = (s) ? b : a;

endmodule