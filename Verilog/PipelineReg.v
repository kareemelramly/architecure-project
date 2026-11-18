/*******************************************************************************
 * Module: PipelineReg.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Generic pipeline register (IF_ID, ID_EX, EX_MEM, MEM_WB)
 *              built on N_bit_register. load picks the phase (C0 or C1) in
 *              which the register captures; flush loads all zeros, which is
 *              a bubble (every control bit = 0).
 *
 * Change history:
 *   11/13/26 - Created load/flush pipeline register wrapper
 *   11/18/26 - Comments updated for the 3-stage, 6-cycle pipeline
 ******************************************************************************/

`timescale 1ns / 1ps

module PipelineReg #(
    parameter N = 32
)(
    input          clk,
    input          rst,
    input          load,    // phase in which the register captures
    input          flush,   // load a bubble instead of D (wins over load)
    input  [N-1:0] D,
    output [N-1:0] Q
);

    wire [N-1:0] dIn;
    wire         regLoad;

    assign dIn     = (flush) ? {N{1'b0}} : D;
    assign regLoad = load | flush;

    N_bit_register #(N) u_reg(
        .clk(clk),
        .rst(rst),
        .Load(regLoad),
        .D(dIn),
        .Q(Q)
    );

endmodule
