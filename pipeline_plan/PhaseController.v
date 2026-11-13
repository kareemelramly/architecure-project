/*******************************************************************************
 * Module: PhaseController.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Two-state C0/C1 sequencer that shares the single memory port.
 *              Every instruction slot is two clock cycles (effective CPI = 2):
 *                C0 (phase = 0): memory serves IF   (addr = PC)
 *                                RegFile writes the WB value at the end of C0
 *                C1 (phase = 1): memory serves MEM  (addr = EX_MEM ALU result)
 *                                PC and all pipeline registers advance at the
 *                                end of C1
 *
 * Change history:
 *   11/13/26 - Created C0/C1 phase toggle for the unified memory
 ******************************************************************************/

`timescale 1ns / 1ps

module PhaseController(
    input  clk,
    input  rst,
    output phase,     // 0 = C0, 1 = C1
    output isFetch,   // high during C0
    output advance    // high during C1: pipeline registers load on this edge
);

    wire nextPhase;

    assign nextPhase = ~phase;

    DFlipFlop u_phaseFF(
        .clk(clk),
        .rst(rst),
        .D(nextPhase),
        .Q(phase)
    );

    assign isFetch = ~phase;
    assign advance = phase;

endmodule
