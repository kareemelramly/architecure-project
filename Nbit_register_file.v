`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/29/2026 07:48:20 AM
// Design Name: 
// Module Name: Nbit_register_file
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


module RegFile #(parameter N = 32) (
input clk, rst,
input [4:0] readreg1, readreg2, writereg,
input [N-1:0] writedata,
input regwrite,
output [N-1:0] readdata1, readdata2 );
wire [N-1:0] D [0:31];
wire [31:0] choice;
Nbit_decoder #(5) uut(writereg, choice);
genvar i;
generate
for(i = 0; i < 32; i = i+1)
begin: Gen_Modules
N_bit_register  #(N) uut2(regwrite & choice[i], clk, rst, writedata, D[i]); 
end
endgenerate
assign readdata1 = (readreg1 == 5'd0) ? {N{1'b0}} : D[readreg1];
assign readdata2 = (readreg2 == 5'd0) ? {N{1'b0}} : D[readreg2];
endmodule