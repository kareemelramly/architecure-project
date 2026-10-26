`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/06/2026 08:14:56 AM
// Design Name: 
// Module Name: DataMem
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


module DataMem
(input clk, input MemRead, input MemWrite, input [2:0] funct3,
input [7:0] addr, input [31:0] data_in, output [31:0] data_out);
reg [31:0] mem [0:63];
integer i;

initial begin
    for (i = 0; i < 64; i = i + 1) mem[i] = 32'd0;
    mem[0] = 32'd10;         // Positive number: 10 (0x0000000A)
    mem[1] = 32'd20;         // Positive number: 20 (0x00000014)
    mem[2] = 32'hFFFFFFFB;   // Negative signed (-5) / Huge unsigned (4294967291)
    mem[5] = 32'h7C8AF1B2;   // Byte/half test word: bytes B2,F1,8A,7C (little-endian) | halves F1B2,7C8A
end

// addr is the byte address: addr[7:2] selects the word, addr[1:0] selects the byte inside it
wire [5:0] wordAddr = addr[7:2];
wire [31:0] word = mem[wordAddr];

// Selected byte / halfword of the addressed word
reg [7:0] selByte;
reg [15:0] selHalf;
always @(*) begin
    case (addr[1:0])
        2'b00: selByte = word[7:0];
        2'b01: selByte = word[15:8];
        2'b10: selByte = word[23:16];
        2'b11: selByte = word[31:24];
    endcase
    selHalf = (addr[1]) ? word[31:16] : word[15:0];
end

// Load: funct3 = 000 LB, 001 LH, 010 LW, 100 LBU, 101 LHU
reg [31:0] loadData;
always @(*) begin
    case (funct3)
        3'b000:  loadData = {{24{selByte[7]}},selByte};   // LB  (sign extended)
        3'b001:  loadData = {{16{selHalf[15]}},selHalf};  // LH  (sign extended)
        3'b100:  loadData = {24'b0,selByte};              // LBU (zero extended)
        3'b101:  loadData = {16'b0,selHalf};              // LHU (zero extended)
        default: loadData = word;                         // LW
    endcase
end

// Store: funct3 = 000 SB, 001 SH, 010 SW (only the addressed bytes of the word are changed)
reg [31:0] storeData;
always @(*) begin
    case (funct3[1:0])
        2'b00: begin                                       // SB
            case (addr[1:0])
                2'b00: storeData = {word[31:8],data_in[7:0]};
                2'b01: storeData = {word[31:16],data_in[7:0],word[7:0]};
                2'b10: storeData = {word[31:24],data_in[7:0],word[15:0]};
                2'b11: storeData = {data_in[7:0],word[23:0]};
            endcase
        end
        2'b01: storeData = (addr[1]) ? {data_in[15:0],word[15:0]} : {word[31:16],data_in[15:0]}; // SH
        default: storeData = data_in;                      // SW
    endcase
end

always @(posedge clk) begin
if(MemWrite) mem[wordAddr] <= storeData;
end
assign data_out = (MemRead)? loadData : 0;
endmodule