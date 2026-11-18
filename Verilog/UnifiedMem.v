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
 *              The program is chosen by PROGRAM_FILE: the name of one of the
 *              four built-in programs written below (all_instr, hazards,
 *              nops_halt, demo), or the path of a .hex file with one 32-bit
 *              little-endian word per line ($readmemh).
 *              Memory map (1 KB): code from 0x000, data from 0x300.
 *
 * Change history:
 *   11/13/26 - Merged InstMem and DataMem into one byte-addressable array
 *   11/16/26 - PROGRAM_FILE parameter ($readmemh); demo image ends with EBREAK
 *   11/18/26 - Word array with byte write enables (LUT RAM on the FPGA);
 *              size set by ADDR_BITS; the four board programs built in,
 *              selected by name
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module UnifiedMem #(
    parameter ADDR_BITS    = `MEM_ADDR_BITS,
    parameter PROGRAM_FILE = ""      // built-in program name or .hex path
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

    // Memory initialisation. Vivado turns this into the bitstream's initial
    // memory contents. PROGRAM_FILE = "all_instr", "hazards", "nops_halt" or
    // "demo" loads that built-in program below (no file needed); any other
    // non-empty value is a .hex file path read with $readmemh.
    // Each line: word index = byte address / 4, then address and assembly.
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem[i] = 32'd0;
        end
        if (PROGRAM_FILE == "all_instr") begin
            // every RV32I + RV32M instruction, self-checked
            mem[0] = 32'h00000f93;    // 000 addi x31, x0, 0x0
            mem[1] = 32'h00000a17;    // 004 auipc x20, 0x0
            mem[2] = 32'h2fca0a13;    // 008 addi x20, x20, 0x2fc
            mem[3] = 32'h00c00093;    // 00C addi x1, x0, 0xc
            mem[4] = 32'hffb00113;    // 010 addi x2, x0, -0x5
            mem[5] = 32'h002081b3;    // 014 add x3, x1, x2
            mem[6] = 32'h00700213;    // 018 addi x4, x0, 0x7
            mem[7] = 32'h20419c63;    // 01C bne x3, x4, 0x234
            mem[8] = 32'h402081b3;    // 020 sub x3, x1, x2
            mem[9] = 32'h01100213;    // 024 addi x4, x0, 0x11
            mem[10] = 32'h20419663;   // 028 bne x3, x4, 0x234
            mem[11] = 32'h001091b3;   // 02C sll x3, x1, x1
            mem[12] = 32'h0000c237;   // 030 lui x4, 0xc
            mem[13] = 32'h20419063;   // 034 bne x3, x4, 0x234
            mem[14] = 32'h001121b3;   // 038 slt x3, x2, x1
            mem[15] = 32'h00100213;   // 03C addi x4, x0, 0x1
            mem[16] = 32'h1e419a63;   // 040 bne x3, x4, 0x234
            mem[17] = 32'h001131b3;   // 044 sltu x3, x2, x1
            mem[18] = 32'h1e019663;   // 048 bne x3, x0, 0x234
            mem[19] = 32'h0020c1b3;   // 04C xor x3, x1, x2
            mem[20] = 32'hff700213;   // 050 addi x4, x0, -0x9
            mem[21] = 32'h1e419063;   // 054 bne x3, x4, 0x234
            mem[22] = 32'h004151b3;   // 058 srl x3, x2, x4
            mem[23] = 32'h1ff00213;   // 05C addi x4, x0, 0x1ff
            mem[24] = 32'h1c419a63;   // 060 bne x3, x4, 0x234
            mem[25] = 32'h401151b3;   // 064 sra x3, x2, x1
            mem[26] = 32'hfff00213;   // 068 addi x4, x0, -0x1
            mem[27] = 32'h1c419463;   // 06C bne x3, x4, 0x234
            mem[28] = 32'h0020e1b3;   // 070 or x3, x1, x2
            mem[29] = 32'hfff00213;   // 074 addi x4, x0, -0x1
            mem[30] = 32'h1a419e63;   // 078 bne x3, x4, 0x234
            mem[31] = 32'h0020f1b3;   // 07C and x3, x1, x2
            mem[32] = 32'h00800213;   // 080 addi x4, x0, 0x8
            mem[33] = 32'h1a419863;   // 084 bne x3, x4, 0x234
            mem[34] = 32'hffe08193;   // 088 addi x3, x1, -0x2
            mem[35] = 32'h00a00213;   // 08C addi x4, x0, 0xa
            mem[36] = 32'h1a419263;   // 090 bne x3, x4, 0x234
            mem[37] = 32'h00012193;   // 094 slti x3, x2, 0x0
            mem[38] = 32'h00100213;   // 098 addi x4, x0, 0x1
            mem[39] = 32'h18419c63;   // 09C bne x3, x4, 0x234
            mem[40] = 32'h00113193;   // 0A0 sltiu x3, x2, 0x1
            mem[41] = 32'h18019863;   // 0A4 bne x3, x0, 0x234
            mem[42] = 32'h0050c193;   // 0A8 xori x3, x1, 0x5
            mem[43] = 32'h00900213;   // 0AC addi x4, x0, 0x9
            mem[44] = 32'h18419263;   // 0B0 bne x3, x4, 0x234
            mem[45] = 32'h0030e193;   // 0B4 ori x3, x1, 0x3
            mem[46] = 32'h00f00213;   // 0B8 addi x4, x0, 0xf
            mem[47] = 32'h16419c63;   // 0BC bne x3, x4, 0x234
            mem[48] = 32'h0060f193;   // 0C0 andi x3, x1, 0x6
            mem[49] = 32'h00400213;   // 0C4 addi x4, x0, 0x4
            mem[50] = 32'h16419663;   // 0C8 bne x3, x4, 0x234
            mem[51] = 32'h00209193;   // 0CC slli x3, x1, 0x2
            mem[52] = 32'h03000213;   // 0D0 addi x4, x0, 0x30
            mem[53] = 32'h16419063;   // 0D4 bne x3, x4, 0x234
            mem[54] = 32'h0020d193;   // 0D8 srli x3, x1, 0x2
            mem[55] = 32'h00300213;   // 0DC addi x4, x0, 0x3
            mem[56] = 32'h14419a63;   // 0E0 bne x3, x4, 0x234
            mem[57] = 32'h40115193;   // 0E4 srai x3, x2, 0x1
            mem[58] = 32'hffd00213;   // 0E8 addi x4, x0, -0x3
            mem[59] = 32'h14419463;   // 0EC bne x3, x4, 0x234
            mem[60] = 32'h123451b7;   // 0F0 lui x3, 0x12345
            mem[61] = 32'h12345237;   // 0F4 lui x4, 0x12345
            mem[62] = 32'h12419e63;   // 0F8 bne x3, x4, 0x234
            mem[63] = 32'h00000197;   // 0FC auipc x3, 0x0
            mem[64] = 32'h004002ef;   // 100 jal x5, 0x104
            mem[65] = 32'hff828293;   // 104 addi x5, x5, -0x8
            mem[66] = 32'h12519663;   // 108 bne x3, x5, 0x234
            mem[67] = 32'h80f1f337;   // 10C lui x6, 0x80f1f
            mem[68] = 32'h2f330313;   // 110 addi x6, x6, 0x2f3
            mem[69] = 32'h006a2023;   // 114 sw x6, 0x0(x20)
            mem[70] = 32'h000a2183;   // 118 lw x3, 0x0(x20)
            mem[71] = 32'h10619c63;   // 11C bne x3, x6, 0x234
            mem[72] = 32'h000a0183;   // 120 lb x3, 0x0(x20)
            mem[73] = 32'hff300213;   // 124 addi x4, x0, -0xd
            mem[74] = 32'h10419663;   // 128 bne x3, x4, 0x234
            mem[75] = 32'h000a4183;   // 12C lbu x3, 0x0(x20)
            mem[76] = 32'h0f300213;   // 130 addi x4, x0, 0xf3
            mem[77] = 32'h10419063;   // 134 bne x3, x4, 0x234
            mem[78] = 32'h002a1183;   // 138 lh x3, 0x2(x20)
            mem[79] = 32'hffff8237;   // 13C lui x4, 0xffff8
            mem[80] = 32'h0f120213;   // 140 addi x4, x4, 0xf1
            mem[81] = 32'h0e419863;   // 144 bne x3, x4, 0x234
            mem[82] = 32'h002a5183;   // 148 lhu x3, 0x2(x20)
            mem[83] = 32'h00008237;   // 14C lui x4, 0x8
            mem[84] = 32'h0f120213;   // 150 addi x4, x4, 0xf1
            mem[85] = 32'h0e419063;   // 154 bne x3, x4, 0x234
            mem[86] = 32'h001a0223;   // 158 sb x1, 0x4(x20)
            mem[87] = 32'h002a1323;   // 15C sh x2, 0x6(x20)
            mem[88] = 32'h004a2183;   // 160 lw x3, 0x4(x20)
            mem[89] = 32'hfffb0237;   // 164 lui x4, 0xfffb0
            mem[90] = 32'h00c20213;   // 168 addi x4, x4, 0xc
            mem[91] = 32'h0c419463;   // 16C bne x3, x4, 0x234
            mem[92] = 32'h00108463;   // 170 beq x1, x1, 0x178
            mem[93] = 32'h0c00006f;   // 174 jal x0, 0x234
            mem[94] = 32'h00209463;   // 178 bne x1, x2, 0x180
            mem[95] = 32'h0b80006f;   // 17C jal x0, 0x234
            mem[96] = 32'h00114463;   // 180 blt x2, x1, 0x188
            mem[97] = 32'h0b00006f;   // 184 jal x0, 0x234
            mem[98] = 32'h0020d463;   // 188 bge x1, x2, 0x190
            mem[99] = 32'h0a80006f;   // 18C jal x0, 0x234
            mem[100] = 32'h0020e463;  // 190 bltu x1, x2, 0x198
            mem[101] = 32'h0a00006f;  // 194 jal x0, 0x234
            mem[102] = 32'h00117463;  // 198 bgeu x2, x1, 0x1a0
            mem[103] = 32'h0980006f;  // 19C jal x0, 0x234
            mem[104] = 32'h008003ef;  // 1A0 jal x7, 0x1a8
            mem[105] = 32'h0900006f;  // 1A4 jal x0, 0x234
            mem[106] = 32'h00000417;  // 1A8 auipc x8, 0x0
            mem[107] = 32'h01040413;  // 1AC addi x8, x8, 0x10
            mem[108] = 32'h001404e7;  // 1B0 jalr x9, 0x1(x8)
            mem[109] = 32'h0800006f;  // 1B4 jal x0, 0x234
            mem[110] = 32'h00000217;  // 1B8 auipc x4, 0x0
            mem[111] = 32'hffc20213;  // 1BC addi x4, x4, -0x4
            mem[112] = 32'h06449a63;  // 1C0 bne x9, x4, 0x234
            mem[113] = 32'h00700513;  // 1C4 addi x10, x0, 0x7
            mem[114] = 32'hffd00593;  // 1C8 addi x11, x0, -0x3
            mem[115] = 32'h02b501b3;  // 1CC <unknown>
            mem[116] = 32'hfeb00213;  // 1D0 addi x4, x0, -0x15
            mem[117] = 32'h06419063;  // 1D4 bne x3, x4, 0x234
            mem[118] = 32'h02b511b3;  // 1D8 <unknown>
            mem[119] = 32'hfff00213;  // 1DC addi x4, x0, -0x1
            mem[120] = 32'h04419a63;  // 1E0 bne x3, x4, 0x234
            mem[121] = 32'h02b531b3;  // 1E4 <unknown>
            mem[122] = 32'h00600213;  // 1E8 addi x4, x0, 0x6
            mem[123] = 32'h04419463;  // 1EC bne x3, x4, 0x234
            mem[124] = 32'h02a5a1b3;  // 1F0 <unknown>
            mem[125] = 32'hfff00213;  // 1F4 addi x4, x0, -0x1
            mem[126] = 32'h02419e63;  // 1F8 bne x3, x4, 0x234
            mem[127] = 32'h02b541b3;  // 1FC <unknown>
            mem[128] = 32'hffe00213;  // 200 addi x4, x0, -0x2
            mem[129] = 32'h02419863;  // 204 bne x3, x4, 0x234
            mem[130] = 32'h021551b3;  // 208 <unknown>
            mem[131] = 32'h02019463;  // 20C bne x3, x0, 0x234
            mem[132] = 32'h02b561b3;  // 210 <unknown>
            mem[133] = 32'h00100213;  // 214 addi x4, x0, 0x1
            mem[134] = 32'h00419e63;  // 218 bne x3, x4, 0x234
            mem[135] = 32'h021571b3;  // 21C <unknown>
            mem[136] = 32'h00700213;  // 220 addi x4, x0, 0x7
            mem[137] = 32'h00419863;  // 224 bne x3, x4, 0x234
            mem[138] = 32'h00500013;  // 228 addi x0, x0, 0x5
            mem[139] = 32'h00001463;  // 22C bne x0, x0, 0x234
            mem[140] = 32'h0080006f;  // 230 jal x0, 0x238
            mem[141] = 32'h001f8f93;  // 234 addi x31, x31, 0x1
            mem[142] = 32'h0000cf37;  // 238 lui x30, 0xc
            mem[143] = 32'h0def0f13;  // 23C addi x30, x30, 0xde
            mem[144] = 32'h00100073;  // 240 ebreak
        end else if (PROGRAM_FILE == "hazards") begin
            // back-to-back dependencies, load-use, flushes
            mem[0] = 32'h00000f93;    // 000 addi x31, x0, 0x0
            mem[1] = 32'h00000a17;    // 004 auipc x20, 0x0
            mem[2] = 32'h2fca0a13;    // 008 addi x20, x20, 0x2fc
            mem[3] = 32'h00500093;    // 00C addi x1, x0, 0x5
            mem[4] = 32'hffb08113;    // 010 addi x2, x1, -0x5
            mem[5] = 32'h00010463;    // 014 beq x2, x0, 0x1c
            mem[6] = 32'h001f8f93;    // 018 addi x31, x31, 0x1
            mem[7] = 32'h00700193;    // 01C addi x3, x0, 0x7
            mem[8] = 32'h00018463;    // 020 beq x3, x0, 0x28
            mem[9] = 32'h0080006f;    // 024 jal x0, 0x2c
            mem[10] = 32'h001f8f93;   // 028 addi x31, x31, 0x1
            mem[11] = 32'h000a2203;   // 02C lw x4, 0x0(x20)
            mem[12] = 32'h00021463;   // 030 bne x4, x0, 0x38
            mem[13] = 32'h001f8f93;   // 034 addi x31, x31, 0x1
            mem[14] = 32'h004a2283;   // 038 lw x5, 0x4(x20)
            mem[15] = 32'h00029463;   // 03C bne x5, x0, 0x44
            mem[16] = 32'h0080006f;   // 040 jal x0, 0x48
            mem[17] = 32'h001f8f93;   // 044 addi x31, x31, 0x1
            mem[18] = 32'h000a2303;   // 048 lw x6, 0x0(x20)
            mem[19] = 32'h00100393;   // 04C addi x7, x0, 0x1
            mem[20] = 32'h00031463;   // 050 bne x6, x0, 0x58
            mem[21] = 32'h001f8f93;   // 054 addi x31, x31, 0x1
            mem[22] = 32'h00300413;   // 058 addi x8, x0, 0x3
            mem[23] = 32'h00400493;   // 05C addi x9, x0, 0x4
            mem[24] = 32'h00941463;   // 060 bne x8, x9, 0x68
            mem[25] = 32'h001f8f93;   // 064 addi x31, x31, 0x1
            mem[26] = 32'h00940533;   // 068 add x10, x8, x9
            mem[27] = 32'h00700593;   // 06C addi x11, x0, 0x7
            mem[28] = 32'h00b50463;   // 070 beq x10, x11, 0x78
            mem[29] = 32'h001f8f93;   // 074 addi x31, x31, 0x1
            mem[30] = 32'h00000617;   // 078 auipc x12, 0x0
            mem[31] = 32'h01060613;   // 07C addi x12, x12, 0x10
            mem[32] = 32'h000606e7;   // 080 jalr x13, 0x0(x12)
            mem[33] = 32'h001f8f93;   // 084 addi x31, x31, 0x1
            mem[34] = 32'h00000717;   // 088 auipc x14, 0x0
            mem[35] = 32'h01870713;   // 08C addi x14, x14, 0x18
            mem[36] = 32'h00ea2423;   // 090 sw x14, 0x8(x20)
            mem[37] = 32'h008a2783;   // 094 lw x15, 0x8(x20)
            mem[38] = 32'h00078067;   // 098 jalr x0, 0x0(x15)
            mem[39] = 32'h001f8f93;   // 09C addi x31, x31, 0x1
            mem[40] = 32'h0080086f;   // 0A0 jal x16, 0xa8
            mem[41] = 32'h001f8f93;   // 0A4 addi x31, x31, 0x1
            mem[42] = 32'h00000897;   // 0A8 auipc x17, 0x0
            mem[43] = 32'h00088893;   // 0AC addi x17, x17, 0x0
            mem[44] = 32'h01181463;   // 0B0 bne x16, x17, 0xb8
            mem[45] = 32'h001f8f93;   // 0B4 addi x31, x31, 0x1
            mem[46] = 32'h000a2903;   // 0B8 lw x18, 0x0(x20)
            mem[47] = 32'h00190993;   // 0BC addi x19, x18, 0x1
            mem[48] = 32'h013a2223;   // 0C0 sw x19, 0x4(x20)
            mem[49] = 32'h004a2a83;   // 0C4 lw x21, 0x4(x20)
            mem[50] = 32'h12345b37;   // 0C8 lui x22, 0x12345
            mem[51] = 32'h679b0b13;   // 0CC addi x22, x22, 0x679
            mem[52] = 32'h016a8463;   // 0D0 beq x21, x22, 0xd8
            mem[53] = 32'h001f8f93;   // 0D4 addi x31, x31, 0x1
            mem[54] = 32'h000a2b83;   // 0D8 lw x23, 0x0(x20)
            mem[55] = 32'h017a2423;   // 0DC sw x23, 0x8(x20)
            mem[56] = 32'h008a2c03;   // 0E0 lw x24, 0x8(x20)
            mem[57] = 32'h012c0463;   // 0E4 beq x24, x18, 0xec
            mem[58] = 32'h001f8f93;   // 0E8 addi x31, x31, 0x1
            mem[59] = 32'h00000293;   // 0EC addi x5, x0, 0x0
            mem[60] = 32'h00700013;   // 0F0 addi x0, x0, 0x7
            mem[61] = 32'h00500463;   // 0F4 beq x0, x5, 0xfc
            mem[62] = 32'h001f8f93;   // 0F8 addi x31, x31, 0x1
            mem[63] = 32'h014a2623;   // 0FC sw x20, 0xc(x20)
            mem[64] = 32'h00ca2c83;   // 100 lw x25, 0xc(x20)
            mem[65] = 32'h000cad03;   // 104 lw x26, 0x0(x25)
            mem[66] = 32'h12345db7;   // 108 lui x27, 0x12345
            mem[67] = 32'h678d8d93;   // 10C addi x27, x27, 0x678
            mem[68] = 32'h01bd0463;   // 110 beq x26, x27, 0x118
            mem[69] = 32'h001f8f93;   // 114 addi x31, x31, 0x1
            mem[70] = 32'h00100e13;   // 118 addi x28, x0, 0x1
            mem[71] = 32'h01ce0e33;   // 11C add x28, x28, x28
            mem[72] = 32'h01ce0e33;   // 120 add x28, x28, x28
            mem[73] = 32'h01ce0e33;   // 124 add x28, x28, x28
            mem[74] = 32'h00800e93;   // 128 addi x29, x0, 0x8
            mem[75] = 32'h01de0463;   // 12C beq x28, x29, 0x134
            mem[76] = 32'h001f8f93;   // 130 addi x31, x31, 0x1
            mem[77] = 32'h01ca2223;   // 134 sw x28, 0x4(x20)
            mem[78] = 32'h004a2e83;   // 138 lw x29, 0x4(x20)
            mem[79] = 32'hff8e8e93;   // 13C addi x29, x29, -0x8
            mem[80] = 32'h000e8463;   // 140 beq x29, x0, 0x148
            mem[81] = 32'h001f8f93;   // 144 addi x31, x31, 0x1
            mem[82] = 32'h00000663;   // 148 beq x0, x0, 0x154
            mem[83] = 32'h000a2023;   // 14C sw x0, 0x0(x20)
            mem[84] = 32'h001f8f93;   // 150 addi x31, x31, 0x1
            mem[85] = 32'h000a2d03;   // 154 lw x26, 0x0(x20)
            mem[86] = 32'h01bd0463;   // 158 beq x26, x27, 0x160
            mem[87] = 32'h001f8f93;   // 15C addi x31, x31, 0x1
            mem[88] = 32'h008000ef;   // 160 jal x1, 0x168
            mem[89] = 32'h0140006f;   // 164 jal x0, 0x178
            mem[90] = 32'h001a2423;   // 168 sw x1, 0x8(x20)
            mem[91] = 32'h008a2103;   // 16C lw x2, 0x8(x20)
            mem[92] = 32'h00010067;   // 170 jalr x0, 0x0(x2)
            mem[93] = 32'h001f8f93;   // 174 addi x31, x31, 0x1
            mem[94] = 32'h0000cf37;   // 178 lui x30, 0xc
            mem[95] = 32'h0def0f13;   // 17C addi x30, x30, 0xde
            mem[96] = 32'h00100073;   // 180 ebreak
            mem[192] = 32'h12345678;  // 300 data
        end else if (PROGRAM_FILE == "nops_halt") begin
            // ECALL, FENCE, FENCE.TSO, PAUSE as NOPs; EBREAK
            mem[0] = 32'h00000f93;    // 000 addi x31, x0, 0x0
            mem[1] = 32'h00100093;    // 004 addi x1, x0, 0x1
            mem[2] = 32'h00000073;    // 008 ecall
            mem[3] = 32'h00108093;    // 00C addi x1, x1, 0x1
            mem[4] = 32'h0ff0000f;    // 010 fence iorw, iorw
            mem[5] = 32'h00108093;    // 014 addi x1, x1, 0x1
            mem[6] = 32'h8330000f;    // 018 fence.tso
            mem[7] = 32'h00108093;    // 01C addi x1, x1, 0x1
            mem[8] = 32'h0100000f;    // 020 fence w, 0
            mem[9] = 32'h00108093;    // 024 addi x1, x1, 0x1
            mem[10] = 32'h00500113;   // 028 addi x2, x0, 0x5
            mem[11] = 32'h00209463;   // 02C bne x1, x2, 0x34
            mem[12] = 32'h0080006f;   // 030 jal x0, 0x38
            mem[13] = 32'h001f8f93;   // 034 addi x31, x31, 0x1
            mem[14] = 32'h0000cf37;   // 038 lui x30, 0xc
            mem[15] = 32'h0def0f13;   // 03C addi x30, x30, 0xde
            mem[16] = 32'h00100073;   // 040 ebreak
            mem[17] = 32'h064f8f93;   // 044 addi x31, x31, 0x64
        end else if (PROGRAM_FILE == "demo") begin
            // 9-instruction demo for step mode
            mem[0] = 32'h00500093;    // 000 addi x1, x0, 0x5
            mem[1] = 32'h30002103;    // 004 lw x2, 0x300(x0)
            mem[2] = 32'h001101b3;    // 008 add x3, x2, x1
            mem[3] = 32'h00318463;    // 00C beq x3, x3, 0x14
            mem[4] = 32'h00100f93;    // 010 addi x31, x0, 0x1
            mem[5] = 32'h30302223;    // 014 sw x3, 0x304(x0)
            mem[6] = 32'h0000cf37;    // 018 lui x30, 0xc
            mem[7] = 32'h0def0f13;    // 01C addi x30, x30, 0xde
            mem[8] = 32'h00100073;    // 020 ebreak
            mem[192] = 32'h00000007;  // 300 data
        end else if (PROGRAM_FILE != "") begin
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