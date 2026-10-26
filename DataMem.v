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
(input clk, input MemRead, input MemWrite,
input [5:0] addr, input [31:0] data_in, output [31:0] data_out);
reg [31:0] mem [0:63];
integer i;

initial begin
    for (i = 0; i < 64; i = i + 1) mem[i] = 32'd0;
    mem[0] = 32'd10;         // Positive number: 10 (0x0000000A)
    mem[1] = 32'd20;         // Positive number: 20 (0x00000014)
    mem[2] = 32'hFFFFFFFB;   // Negative signed (-5) / Huge unsigned (4294967291)
end
always @(posedge clk) begin
if(MemWrite) mem[addr] <= data_in;
end
assign data_out = (MemRead)? mem[addr] : 0;
endmodule