`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/22/2026 07:38:33 AM
// Design Name: 
// Module Name: N_bit_register
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


module Nbit_shift_left #(parameter N = 32)(
input [N-1: 0] a, output [N-1:0] c);
genvar i;
generate
for(i = 0; i < (N-1); i = i+1)
begin: Gen_Modules
assign c[i+1]=a[i];
end
assign c[0] = 0;
endgenerate
endmodule
