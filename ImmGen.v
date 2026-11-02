/*******************************************************************************
 * Module: ImmGen.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Immediate Generator decoding I, S, B, U, and J formats.
 *
 * Change history:
 *   10/26/26 - Initial multiplexer-based I, S, B extraction
 *   10/29/26 - Upgraded to full 32-bit sign extension for I, S, B, U, J types
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module ImmGen(
    input  [31:0] inst,
    output reg [31:0] genOut
);

    wire [4:0] opcode;
    assign opcode = inst[6:2];

    always @* begin
        case (opcode)
            `OPC_LOAD, `OPC_OP_IMM, `OPC_JALR: begin
                genOut = {{20{inst[31]}}, inst[31:20]};
            end

            `OPC_STORE: begin
                genOut = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end

            `OPC_BRANCH: begin
                genOut = {{19{inst[31]}}, inst[31], inst[7],
                          inst[30:25], inst[11:8], 1'b0};
            end

            `OPC_LUI, `OPC_AUIPC: begin
                genOut = {inst[31:12], 12'b0};
            end

            `OPC_JAL: begin
                genOut = {{11{inst[31]}}, inst[31], inst[19:12],
                          inst[20], inst[30:21], 1'b0};
            end

            default: begin
                genOut = 32'd0;
            end
        endcase
    end

endmodule