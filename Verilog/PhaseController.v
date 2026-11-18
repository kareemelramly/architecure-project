/*******************************************************************************
 * Module: PhaseController.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Two-state C0/C1 sequencer (the "slow clock" sclk of the
 *              lecture drawn as an enable, so the whole CPU runs on one clock
 *              and no clock is gated). Each pipeline stage takes two cycles:
 *                C0 (isC0): IF of stage 0, EX of stage 1, WB of stage 2
 *                C1 (isC1): ID of stage 0, MEM of stage 1
 *              The memory serves IF in C0 and MEM in C1 only, so the single
 *              port is never shared in the same cycle.
 *
 * Change history:
 *   11/13/26 - Created C0/C1 phase toggle for the unified memory
 *   11/18/26 - Outputs renamed isC0 / isC1 for the 3-stage, 6-cycle pipeline
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module PhaseController(
    input  clk,
    input  rst,
    output phase,     // 0 = C0, 1 = C1
    output isC0,
    output isC1
);

    wire nextPhase;

    assign nextPhase = ~phase;

    DFlipFlop u_phaseFF(
        .clk(clk),
        .rst(rst),
        .D(nextPhase),
        .Q(phase)
    );

    assign isC0 = (phase == `PHASE_C0);
    assign isC1 = (phase == `PHASE_C1);

endmodule
