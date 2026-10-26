`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/06/2026 07:43:38 AM
// Design Name: 
// Module Name: InstMem
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module InstMem (input [5:0] addr, output [31:0] data_out);
reg [31:0] mem [0:63];
integer i;
initial begin
        for (i = 0; i < 64; i = i + 1) mem[i] = 32'd0;

        // --- SETUP REGISTERS ---
        mem[0]  = 32'b000000000000_00000_010_00001_0000011; // lw x1, 0(x0)   -> x1 = 10
        mem[1]  = 32'b000000000100_00000_010_00010_0000011; // lw x2, 4(x0)   -> x2 = 20
        mem[2]  = 32'b000000001000_00000_010_00011_0000011; // lw x3, 8(x0)   -> x3 = -5 (0xFFFFFFFB)
        mem[3]  = 32'b0000000_00000_00000_000_00100_0110011; // add x4, x0, x0 -> x4 = 0 (Pass Score)
        mem[4]  = 32'b0000000_00000_00000_000_00101_0110011; // add x5, x0, x0 -> x5 = 0 (Fail/Trap Count)

        // --- TEST 1: BEQ (funct3 = 000) | 10 == 10 (TAKEN, +8) ---
        mem[5]  = 32'b0_000000_00001_00001_000_0100_0_1100011; // beq x1, x1, +8 (Jump to mem[7])
        mem[6]  = 32'b0000000_00001_00101_000_00101_0110011; // TRAP: add x5, x5, x1 (Skipped!)
        mem[7]  = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (x4 = 10)

        // --- TEST 2: BNE (funct3 = 001) | 10 != 20 (TAKEN, +8) ---
        mem[8]  = 32'b0_000000_00010_00001_001_0100_0_1100011; // bne x1, x2, +8 (Jump to mem[10])
        mem[9]  = 32'b0000000_00001_00101_000_00101_0110011; // TRAP: add x5, x5, x1 (Skipped!)
        mem[10] = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (x4 = 20)

        // --- TEST 3: BLT (funct3 = 100) | -5 < 10 Signed (TAKEN, +8) ---
        mem[11] = 32'b0_000000_00001_00011_100_0100_0_1100011; // blt x3, x1, +8 (Jump to mem[13])
        mem[12] = 32'b0000000_00001_00101_000_00101_0110011; // TRAP: add x5, x5, x1 (Skipped!)
        mem[13] = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (x4 = 30)

        // --- TEST 4: BGE (funct3 = 101) | 10 >= -5 Signed (TAKEN, +8) ---
        mem[14] = 32'b0_000000_00011_00001_101_0100_0_1100011; // bge x1, x3, +8 (Jump to mem[16])
        mem[15] = 32'b0000000_00001_00101_000_00101_0110011; // TRAP: add x5, x5, x1 (Skipped!)
        mem[16] = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (x4 = 40)

        // --- TEST 5: BLTU (funct3 = 110) | 10 < 0xFFFFFFFB Unsigned (TAKEN, +8) ---
        mem[17] = 32'b0_000000_00011_00001_110_0100_0_1100011; // bltu x1, x3, +8 (Jump to mem[19])
        mem[18] = 32'b0000000_00001_00101_000_00101_0110011; // TRAP: add x5, x5, x1 (Skipped!)
        mem[19] = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (x4 = 50)

        // --- TEST 6: BGEU (funct3 = 111) | 0xFFFFFFFB >= 20 Unsigned (TAKEN, +8) ---
        mem[20] = 32'b0_000000_00010_00011_111_0100_0_1100011; // bgeu x3, x2, +8 (Jump to mem[22])
        mem[21] = 32'b0000000_00001_00101_000_00101_0110011; // TRAP: add x5, x5, x1 (Skipped!)
        mem[22] = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (x4 = 60)

        // --- TEST 7: NOT-TAKEN CHECK | BLTU 0xFFFFFFFB < 10 Unsigned (FALSE -> NOT TAKEN) ---
        mem[23] = 32'b0_000000_00001_00011_110_0100_0_1100011; // bltu x3, x1, +8 (Must NOT jump!)
        mem[24] = 32'b0000000_00001_00100_000_00100_0110011; // PASS: add x4, x4, x1 (Executed! x4 = 70)

        // --- STORE FINAL RESULTS TO DATAMEM ---
        mem[25] = 32'b0000000_00100_00000_010_01100_0100011; // sw x4, 12(x0) -> DataMem[3] = 70
        mem[26] = 32'b0000000_00101_00000_010_10000_0100011; // sw x5, 16(x0) -> DataMem[4] = 0
    end
assign data_out = mem[addr];
endmodule