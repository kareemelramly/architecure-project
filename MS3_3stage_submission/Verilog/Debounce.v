/*******************************************************************************
 * Module: Debounce.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Debounces a push button and emits a one-cycle pulse on the
 *              press edge. Two-flop synchronizer, then the input must stay
 *              stable for 2^CNT_BITS clk cycles before it is accepted.
 *
 * Change history:
 *   11/16/26 - created for the MS3 board wrapper
 *   11/18/26 - asynchronous reset instead of initial values (guidelines)
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module Debounce #(
    parameter CNT_BITS = 20       // 2^20 cycles at 100 MHz ~ 10 ms
)(
    input  wire clk,
    input  wire rst,
    input  wire in,
    output reg  pulse
);

    reg                sync0;
    reg                sync1;
    reg                stable;
    reg [CNT_BITS-1:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0  <= 1'b0;
            sync1  <= 1'b0;
            stable <= 1'b0;
            cnt    <= {CNT_BITS{1'b0}};
            pulse  <= 1'b0;
        end else begin
            sync0 <= in;
            sync1 <= sync0;
            if (sync1 == stable) begin
                cnt   <= {CNT_BITS{1'b0}};
                pulse <= 1'b0;
            end else if (&cnt) begin
                cnt    <= {CNT_BITS{1'b0}};
                stable <= sync1;
                pulse  <= sync1;          // press edge only
            end else begin
                cnt   <= cnt + 1'b1;
                pulse <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
