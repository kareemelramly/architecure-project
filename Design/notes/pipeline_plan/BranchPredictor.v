/*******************************************************************************
 * Module: BranchPredictor.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: IF-stage dynamic branch predictor (Bonus 3).
 *              - BTB: direct-mapped, tagged, caches the taken target of
 *                branches and JAL.
 *              - BHT: one 2-bit saturating counter per entry
 *                (00 strong NT, 01 weak NT, 10 weak T, 11 strong T).
 *              Lookup is combinational on the IF PC. The update port is
 *              written by the EX stage once the real outcome is known.
 *
 * Change history:
 *   11/13/26 - Created BTB + 2-bit BHT with EX-stage update port
 ******************************************************************************/

`timescale 1ns / 1ps

module BranchPredictor #(
    parameter INDEX_BITS = 4                 // 16 entries
)(
    input         clk,
    input         rst,

    // IF-stage lookup
    input  [31:0] pcIF,
    output        predictTaken,
    output [31:0] predictTarget,

    // EX-stage update (updateEn must already be ANDed with `advance`)
    input         updateEn,
    input  [31:0] updatePC,
    input         actualTaken,
    input  [31:0] actualTarget
);

    localparam ENTRIES  = 1 << INDEX_BITS;
    localparam TAG_BITS = 30 - INDEX_BITS;   // PC[31:INDEX_BITS+2]

    reg                btbValid  [0:ENTRIES-1];
    reg [TAG_BITS-1:0] btbTag    [0:ENTRIES-1];
    reg [31:0]         btbTarget [0:ENTRIES-1];
    reg [1:0]          bht       [0:ENTRIES-1];

    wire [INDEX_BITS-1:0] lookupIdx;
    wire [TAG_BITS-1:0]   lookupTag;
    wire                  lookupHit;
    wire [INDEX_BITS-1:0] updateIdx;
    wire [TAG_BITS-1:0]   updateTag;
    wire                  updateHit;
    integer i;

    // ---------------- Lookup (IF) ----------------
    assign lookupIdx = pcIF[INDEX_BITS+1:2];
    assign lookupTag = pcIF[31:INDEX_BITS+2];
    assign lookupHit = btbValid[lookupIdx] && (btbTag[lookupIdx] == lookupTag);

    assign predictTaken  = lookupHit && bht[lookupIdx][1];
    assign predictTarget = btbTarget[lookupIdx];

    // ---------------- Update (EX) ----------------
    assign updateIdx = updatePC[INDEX_BITS+1:2];
    assign updateTag = updatePC[31:INDEX_BITS+2];
    assign updateHit = btbValid[updateIdx] && (btbTag[updateIdx] == updateTag);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                btbValid[i]  <= 1'b0;
                btbTag[i]    <= {TAG_BITS{1'b0}};
                btbTarget[i] <= 32'd0;
                bht[i]       <= 2'b01;       // weakly not taken
            end
        end else if (updateEn) begin
            if (actualTaken) begin
                btbTarget[updateIdx] <= actualTarget;
                if (updateHit) begin
                    if (bht[updateIdx] != 2'b11) begin
                        bht[updateIdx] <= bht[updateIdx] + 2'b01;
                    end
                end else begin
                    // Allocate (or replace an aliasing entry) as weakly taken
                    btbValid[updateIdx] <= 1'b1;
                    btbTag[updateIdx]   <= updateTag;
                    bht[updateIdx]      <= 2'b10;
                end
            end else if (updateHit) begin
                if (bht[updateIdx] != 2'b00) begin
                    bht[updateIdx] <= bht[updateIdx] - 2'b01;
                end
            end
        end
    end

endmodule
