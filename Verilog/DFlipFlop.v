/*******************************************************************************
 * Module: DFlipFlop.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: D Flip-Flop with asynchronous active-high reset.
 *
 * Change history:
 *   10/26/26 - Initial DFF implementation
 *   11/01/26 - Placed into standalone file per guidelines
 ******************************************************************************/

`timescale 1ns / 1ps

module DFlipFlop(
    input      clk,
    input      rst,
    input      D,
    output reg Q
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            Q <= 1'b0;
        end else begin
            Q <= D;
        end
    end

endmodule