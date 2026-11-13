/*******************************************************************************
 * Module: ForwardingUnit.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: EX-stage forwarding. 2'b00 = register file (ID_EX),
 *              2'b10 = EX_MEM result, 2'b01 = MEM_WB write-back value.
 *
 * Change history:
 *   11/10/26 - Lab 8 version
 *   11/13/26 - Fixed widths, default assignments (no latch), x0 guard
 ******************************************************************************/

`timescale 1ns / 1ps

module ForwardingUnit(
    input  [4:0] idExRs1,
    input  [4:0] idExRs2,
    input  [4:0] exMemRd,
    input  [4:0] memWbRd,
    input        exMemRegWrite,
    input        memWbRegWrite,
    output reg [1:0] forwardA,
    output reg [1:0] forwardB
);

    always @* begin
        forwardA = 2'b00;
        forwardB = 2'b00;

        if (exMemRegWrite && (exMemRd != 5'd0) && (exMemRd == idExRs1)) begin
            forwardA = 2'b10;
        end else if (memWbRegWrite && (memWbRd != 5'd0) && (memWbRd == idExRs1)) begin
            forwardA = 2'b01;
        end

        if (exMemRegWrite && (exMemRd != 5'd0) && (exMemRd == idExRs2)) begin
            forwardB = 2'b10;
        end else if (memWbRegWrite && (memWbRd != 5'd0) && (memWbRd == idExRs2)) begin
            forwardB = 2'b01;
        end
    end

endmodule
