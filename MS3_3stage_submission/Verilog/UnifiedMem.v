/*******************************************************************************
 * Module: UnifiedMem.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Single-ported, byte-addressable unified memory holding both
 *              instructions and data: one address, one read port, one write
 *              port. The pipeline time-multiplexes the port:
 *                C0 : instruction fetch  (addr = PC)
 *                C1 : MEM stage load/store (addr = EX_MEM ALU result)
 *              Storage is 32-bit words with a write enable per byte, so the
 *              FPGA tools map it to LUT RAM instead of thousands of flip-
 *              flops. addr[ADDR_BITS-1:2] picks the word, addr[1:0] the byte.
 *              Reads are combinational; writes happen on the clock edge that
 *              ends C1. Loads sign/zero-extend by funct3, SB/SH/SW write
 *              1/2/4 bytes (little endian). Accesses must be aligned
 *              (halfword on an even address, word on a multiple of 4).
 *              The program is loaded with $readmemh from PROGRAM_FILE, one
 *              32-bit little-endian word per line (same image for simulation
 *              and the bitstream). Memory map (1 KB): code from 0x000,
 *              data from 0x300.
 *
 * Change history:
 *   11/13/26 - Merged InstMem and DataMem into one byte-addressable array
 *   11/16/26 - PROGRAM_FILE parameter ($readmemh); demo image ends with EBREAK
 *   11/18/26 - Word array with byte write enables (LUT RAM on the FPGA);
 *              removed the built-in demo image; size set by ADDR_BITS
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module UnifiedMem #(
    parameter ADDR_BITS    = `MEM_ADDR_BITS,
    parameter PROGRAM_FILE = ""      // word-per-line hex image
)(
    input                  clk,
    input                  memRead,
    input                  memWrite,
    input  [2:0]           funct3,
    input  [ADDR_BITS-1:0] addr,
    input  [31:0]          dataIn,
    output [31:0]          dataOut
);

    localparam WORDS = 1 << (ADDR_BITS - 2);

    reg  [31:0] mem [0:WORDS-1];
    wire [ADDR_BITS-3:0] wordAddr;
    wire [1:0]  byteSel;
    wire [31:0] word;
    wire [7:0]  loadByte;
    wire [15:0] loadHalf;
    reg  [31:0] loadData;
    reg  [3:0]  byteEn;
    reg  [31:0] storeData;
    integer i;

    // Memory initialisation (the doctor's $readmemh flow; Vivado turns this
    // into the bitstream's initial memory contents)
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem[i] = 32'd0;
        end
        if (PROGRAM_FILE != "") begin
            $readmemh(PROGRAM_FILE, mem);
        end
    end

    assign wordAddr = addr[ADDR_BITS-1:2];
    assign byteSel  = addr[1:0];
    assign word     = mem[wordAddr];

    // ---------------- Read ----------------
    assign loadByte = (byteSel == 2'd0) ? word[7:0]   :
                      (byteSel == 2'd1) ? word[15:8]  :
                      (byteSel == 2'd2) ? word[23:16] : word[31:24];
    assign loadHalf = (byteSel[1]) ? word[31:16] : word[15:0];

    always @* begin
        case (funct3)
            `MEM_LB:  loadData = {{24{loadByte[7]}}, loadByte};
            `MEM_LH:  loadData = {{16{loadHalf[15]}}, loadHalf};
            `MEM_LBU: loadData = {24'b0, loadByte};
            `MEM_LHU: loadData = {16'b0, loadHalf};
            default:  loadData = word;
        endcase
    end

    assign dataOut = (memRead) ? loadData : 32'd0;

    // ---------------- Write: byte enables and lane-aligned data -------------
    always @* begin
        case (funct3)
            `MEM_SB: begin
                byteEn    = 4'b0001 << byteSel;
                storeData = {4{dataIn[7:0]}};
            end
            `MEM_SH: begin
                byteEn    = (byteSel[1]) ? 4'b1100 : 4'b0011;
                storeData = {2{dataIn[15:0]}};
            end
            default: begin
                byteEn    = 4'b1111;
                storeData = dataIn;
            end
        endcase
    end

    always @(posedge clk) begin
        if (memWrite) begin
            if (byteEn[0]) begin
                mem[wordAddr][7:0] <= storeData[7:0];
            end
            if (byteEn[1]) begin
                mem[wordAddr][15:8] <= storeData[15:8];
            end
            if (byteEn[2]) begin
                mem[wordAddr][23:16] <= storeData[23:16];
            end
            if (byteEn[3]) begin
                mem[wordAddr][31:24] <= storeData[31:24];
            end
        end
    end

endmodule
