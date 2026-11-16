/*******************************************************************************
 * Module: Debounce.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Debounces a push button and emits a one-cycle pulse on the
 *              press edge. Two-flop synchronizer, then the input must stay
 *              stable for 2^CNT_BITS sysClk cycles before it is accepted.
 *
 * Change history:
 *   11/16/26 - created for the MS3 board wrapper
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module Debounce #(parameter CNT_BITS = 20)(
    input  wire clk,
    input  wire in,
    output reg  pulse
);
    reg sync0 = 1'b0, sync1 = 1'b0, stable = 1'b0;
    reg [CNT_BITS-1:0] cnt = {CNT_BITS{1'b0}};

    always @(posedge clk) begin
        sync0 <= in;
        sync1 <= sync0;
        pulse <= 1'b0;
        if (sync1 == stable)
            cnt <= {CNT_BITS{1'b0}};
        else begin
            cnt <= cnt + 1'b1;
            if (&cnt) begin
                stable <= sync1;
                pulse  <= sync1;   // rising edge only
            end
        end
    end
    initial pulse = 1'b0;
endmodule

`default_nettype wire
