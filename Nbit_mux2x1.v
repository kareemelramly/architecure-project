`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/22/2026 08:25:43 AM
// Design Name: 
// Module Name: Nbit_mux2x1
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


module Nbit_mux2x1 #(parameter N = 32)(
input [N-1: 0] a, input [N-1: 0] b, input s, output [N-1:0] c);

genvar i;

generate
for(i = 0; i < N; i = i+1)
begin: Gen_Modules
mux2x1 uut(a[i],b[i],s,c[i]);
end
endgenerate
endmodule
