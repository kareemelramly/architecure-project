/*******************************************************************************
 * Module: Debounce.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Debounces a push button. Two-flop synchronizer, then the
 *              input must stay stable for 2^CNT_BITS clk cycles before the
 *              output follows it. The output comes straight from a flip-flop
 *              (no glitches): it rises once per press and falls once per
 *              release, so it is used as the CPU clock in step mode
 *              (one press = one CPU clock cycle). It is 0 while rst is high.
 *
 * Change history:
 *   11/16/26 - created for the MS3 board wrapper
 *   11/18/26 - asynchronous reset instead of initial values (guidelines)
 *   11/18/26 - outputs the debounced level (the CPU clock) instead of a pulse;
 *              CpuClockGen removed
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module Debounce #(
    parameter CNT_BITS = 20       // 2^20 cycles at 100 MHz ~ 10 ms
)(
    input  wire clk,
    input  wire rst,
    input  wire in,
    output reg  out              // debounced button level
);

    reg                sync0;
    reg                sync1;
    reg [CNT_BITS-1:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
            cnt   <= {CNT_BITS{1'b0}};
            out   <= 1'b0;
        end else begin
            sync0 <= in;
            sync1 <= sync0;
            if (sync1 == out) begin
                cnt <= {CNT_BITS{1'b0}};       // input agrees: nothing to do
            end else if (&cnt) begin
                cnt <= {CNT_BITS{1'b0}};
                out <= sync1;                  // stable long enough: accept
            end else begin
                cnt <= cnt + 1'b1;             // still bouncing or settling
            end
        end
    end

endmodule

`default_nettype wire
