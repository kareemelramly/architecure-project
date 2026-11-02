/*******************************************************************************
 * Module: N_bit_register.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: N-bit parameterizable register with load enable.
 *
 * Change history:
 *   10/26/26 - Initial register design
 *   11/01/26 - Refactored submodules into standalone files per guidelines
 ******************************************************************************/

`timescale 1ns / 1ps

module N_bit_register #(
    parameter N = 32
)(
    input          clk,
    input          rst,
    input          Load,
    input  [N-1:0] D,
    output [N-1:0] Q
);

    genvar i;

    generate
        for (i = 0; i < N; i = i + 1) begin: Gen_Bits
            wire mux_out;

            mux2x1 u_mux(
                .a(Q[i]),
                .b(D[i]),
                .s(Load),
                .c(mux_out)
            );

            DFlipFlop u_dff(
                .clk(clk),
                .rst(rst),
                .D(mux_out),
                .Q(Q[i])
            );
        end
    endgenerate

endmodule