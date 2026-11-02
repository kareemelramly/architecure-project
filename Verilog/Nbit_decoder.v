/*******************************************************************************
 * Module: Nbit_decoder.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Parameterized N-to-(2^N) decoder for register selection.
 *
 * Change history:
 *   10/26/26 - Initial decoder implementation
 *   11/01/26 - Cleaned header and format per guidelines
 ******************************************************************************/

`timescale 1ns / 1ps

module Nbit_decoder #(
    parameter N = 5
)(
    input  [N-1:0]        in,
    output [(1 << N)-1:0] out
);

    assign out = (1'b1 << in);

endmodule