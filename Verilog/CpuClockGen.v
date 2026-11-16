/*******************************************************************************
 * Module: CpuClockGen.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Produces the CPU clock from the 100 MHz board clock.
 *              runMode = 0 : step mode, one button pulse = one full CPU clock cycle
 *              runMode = 1 : free run, slow (~12 Hz) or fast (~3 MHz)
 *              cpuClk is a registered signal in the sysClk domain, so it is glitch free.
 *
 * Change history:
 *   11/16/26 - created for the MS3 board wrapper
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module CpuClockGen #(parameter SLOW_BIT = 22, parameter FAST_BIT = 4)(
    input  wire sysClk,
    input  wire stepPulse,
    input  wire runMode,
    input  wire fastMode,
    output reg  cpuClk
);
    reg [31:0] div = 32'd0;
    reg        prevTick = 1'b0;
    reg        stepHigh = 1'b0;   // step mode: pulse -> high for a few cycles
    reg [3:0]  stepCnt  = 4'd0;

    wire tick = fastMode ? div[FAST_BIT] : div[SLOW_BIT];

    always @(posedge sysClk) begin
        div <= div + 1'b1;
        if (runMode)
            cpuClk <= tick;
        else begin
            if (stepPulse) begin
                stepHigh <= 1'b1;
                stepCnt  <= 4'd8;
            end else if (stepCnt != 4'd0) begin
                stepCnt <= stepCnt - 1'b1;
                if (stepCnt == 4'd1) stepHigh <= 1'b0;
            end
            cpuClk <= stepHigh;
        end
    end
    initial cpuClk = 1'b0;
endmodule

`default_nettype wire
