/*******************************************************************************
 * Module: UnifiedMem.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Single-ported, byte-addressable unified memory holding both
 *              instructions and data. One address, one read port, one write
 *              port. The datapath time-multiplexes the port: C0 = fetch,
 *              C1 = MEM-stage load/store (see PhaseController.v).
 *
 *              Memory map (MEM_BYTES = 1024):
 *                0x000 - 0x1FF : instructions (128 words)
 *                0x200 - 0x3FF : data         (DATA_BASE = 0x200)
 *
 * Change history:
 *   11/13/26 - Merged InstMem and DataMem into one byte-addressable array
 *   11/16/26 - PROGRAM_FILE parameter ($readmemh); demo image ends with EBREAK
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module UnifiedMem #(
    parameter ADDR_BITS    = 10,
    parameter PROGRAM_FILE = ""      // byte-per-line hex image; "" = built-in demo
)(
    input                  clk,
    input                  memRead,
    input                  memWrite,
    input  [2:0]           funct3,
    input  [ADDR_BITS-1:0] addr,
    input  [31:0]          dataIn,
    output [31:0]          dataOut
);

    localparam MEM_BYTES = 1 << ADDR_BITS;

    reg [7:0] mem [0:MEM_BYTES-1];
    wire [7:0] byte0;
    wire [7:0] byte1;
    wire [7:0] byte2;
    wire [7:0] byte3;
    reg  [31:0] loadData;
    integer i;

    // Writes one little-endian 32-bit word at a byte address (init only)
    task initWord;
        input [ADDR_BITS-1:0] byteAddr;
        input [31:0]          value;
        begin
            mem[byteAddr]     = value[7:0];
            mem[byteAddr + 1] = value[15:8];
            mem[byteAddr + 2] = value[23:16];
            mem[byteAddr + 3] = value[31:24];
        end
    endtask

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            mem[i] = 8'd0;
        end

        if (PROGRAM_FILE != "") begin
            // Same image for simulation and for the FPGA bitstream
            $readmemh(PROGRAM_FILE, mem);
        end else begin
        // --- INSTRUCTIONS (byte address = 4 * old InstMem index) ---
        // lw x1, 512(x0) -> x1 = 10
        initWord(10'h000, 32'b001000000000_00000_010_00001_0000011);
        // lw x2, 516(x0) -> x2 = 20
        initWord(10'h004, 32'b001000000100_00000_010_00010_0000011);
        // add x3, x1, x2 -> x3 = 30
        initWord(10'h008, 32'b0000000_00010_00001_000_00011_0110011);
        // sw x3, 520(x0) -> mem[0x208] = 30
        initWord(10'h00C, 32'b0010000_00011_00000_010_01000_0100011);
        // ebreak -> halt
        initWord(10'h010, 32'b000000000001_00000_000_00000_1110011);

        // --- DATA (DATA_BASE = 0x200) ---
        initWord(10'h200, 32'd10);
        initWord(10'h204, 32'd20);
        initWord(10'h208, 32'hFFFFFFFB);
        initWord(10'h214, 32'h7C8AF1B2);
        end
    end

    // Little-endian read of the 4 bytes starting at addr
    assign byte0 = mem[addr];
    assign byte1 = mem[addr + 1];
    assign byte2 = mem[addr + 2];
    assign byte3 = mem[addr + 3];

    always @* begin
        case (funct3)
            `MEM_LB:  loadData = {{24{byte0[7]}}, byte0};
            `MEM_LH:  loadData = {{16{byte1[7]}}, byte1, byte0};
            `MEM_LBU: loadData = {24'b0, byte0};
            `MEM_LHU: loadData = {16'b0, byte1, byte0};
            default:  loadData = {byte3, byte2, byte1, byte0};
        endcase
    end

    assign dataOut = (memRead) ? loadData : 32'd0;

    // Byte-granular stores: SB writes 1 byte, SH 2 bytes, SW 4 bytes
    always @(posedge clk) begin
        if (memWrite) begin
            mem[addr] <= dataIn[7:0];
            if (funct3[1:0] != 2'b00) begin
                mem[addr + 1] <= dataIn[15:8];
            end
            if (funct3[1:0] == 2'b10) begin
                mem[addr + 2] <= dataIn[23:16];
                mem[addr + 3] <= dataIn[31:24];
            end
        end
    end

endmodule
