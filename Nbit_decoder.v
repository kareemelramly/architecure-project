`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/29/2026 08:06:02 AM
// Design Name: 
// Module Name: Nbit_decoder
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


module Nbit_decoder #(parameter N = 5)(
input [N-1: 0] in, output [(1 << N) - 1:0] out);
assign out = (1 << in);
endmodule
