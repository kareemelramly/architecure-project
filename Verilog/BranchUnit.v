/*******************************************************************************
 * Module: BranchUnit.v
 * Project: femtoRV32
 * Author: Mohamed AboElfotouh
 * Description: Dedicated comparator evaluating all RV32I conditional branches.
 *
 * Change history:
 *   10/27/26 - Created BranchUnit supporting BEQ, BNE, BLT, BGE, BLTU, BGEU
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module BranchUnit(
    input         branch,
    input  [2:0]  funct3,
    input  [31:0] readData1,
    input  [31:0] readData2,
    output reg    takeBranch
);

    always @* begin
        if (branch) begin
            case (funct3)
                `BR_BEQ: begin
                    takeBranch = (readData1 == readData2);
                end
                `BR_BNE: begin
                    takeBranch = (readData1 != readData2);
                end
                `BR_BLT: begin
                    takeBranch = ($signed(readData1) < $signed(readData2));
                end
                `BR_BGE: begin
                    takeBranch = ($signed(readData1) >= $signed(readData2));
                end
                `BR_BLTU: begin
                    takeBranch = (readData1 < readData2);
                end
                `BR_BGEU: begin
                    takeBranch = (readData1 >= readData2);
                end
                default: begin
                    takeBranch = 1'b0;
                end
            endcase
        end else begin
            takeBranch = 1'b0;
        end
    end

endmodule