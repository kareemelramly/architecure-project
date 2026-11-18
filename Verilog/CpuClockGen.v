/*******************************************************************************
 * Module: CpuClockGen.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Produces the CPU clock from the 100 MHz board clock.
 *              runMode = 0 : step mode, one button pulse = one CPU clock cycle
 *              runMode = 1 : free run, slow (~12 Hz) or fast (~3 MHz)
 *              cpuClk comes straight from a flip-flop in the sysClk domain,
 *              so it has no glitches. It is held low while rst is high, so
 *              the CPU always leaves reset many sysClk cycles before its
 *              first rising clock edge.
 *
 * Change history:
 *   11/16/26 - created for the MS3 board wrapper
 *   11/18/26 - asynchronous reset instead of initial values (guidelines)
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module CpuClockGen #(
    parameter SLOW_BIT  = 22,     // 100 MHz / 2^23 ~ 12 Hz
    parameter FAST_BIT  = 4,      // 100 MHz / 2^5  ~ 3 MHz
    parameter STEP_HIGH = 4'd8    // sysClk cycles cpuClk stays high per step
)(
    input  wire sysClk,
    input  wire rst,
    input  wire stepPulse,
    input  wire runMode,
    input  wire fastMode,
    output reg  cpuClk
);

    reg  [31:0] div;
    reg  [3:0]  stepCnt;
    wire        tick;
    wire        stepHigh;

    assign tick     = (fastMode) ? div[FAST_BIT] : div[SLOW_BIT];
    assign stepHigh = (stepCnt != 4'd0);

    always @(posedge sysClk or posedge rst) begin
        if (rst) begin
            div     <= 32'd0;
            stepCnt <= 4'd0;
            cpuClk  <= 1'b0;
        end else begin
            div <= div + 1'b1;
            if (stepPulse) begin
                stepCnt <= STEP_HIGH;
            end else if (stepHigh) begin
                stepCnt <= stepCnt - 1'b1;
            end else begin
                stepCnt <= stepCnt;
            end
            if (runMode) begin
                cpuClk <= tick;
            end else begin
                cpuClk <= stepHigh;
            end
        end
    end

endmodule

`default_nettype wire
