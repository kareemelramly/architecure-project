/*******************************************************************************
 * Module: PipelineReg.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Generic pipeline boundary register (IF_ID, ID_EX, EX_MEM,
 *              MEM_WB) built on N_bit_register. Adds a synchronous flush that
 *              loads all zeros (a bubble: every control bit = 0).
 *              Callers must AND both load and flush with `advance` so the
 *              register only changes at the end of C1.
 *
 * Change history:
 *   11/13/26 - Created load/flush pipeline register wrapper
 ******************************************************************************/

`timescale 1ns / 1ps

module PipelineReg #(
    parameter N = 32
)(
    input          clk,
    input          rst,
    input          load,    // advance & ~stall
    input          flush,   // advance & (mispredict | halt), wins over stall
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
