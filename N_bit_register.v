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
module DFlipFlop(input clk, input rst, input D, output reg Q);
always @ (posedge clk or posedge rst) begin // Asynchronous Reset
if (rst)
Q <= 1'b0;
else
Q <= D;
end
endmodule

module mux2x1(input a, b, s, output c);
wire d, e;
assign d = a & ~s;
assign e = b & s;
assign c = d | e;
endmodule

module N_bit_register #(parameter N = 32)(
input Load, clk, input rst, input [N-1:0] D, output  [N-1:0] Q);

genvar i;
wire [N-1:0] w;
wire [N-1:0] in;
assign w = Q;
generate
for(i = 0; i < N; i = i+1)
begin: Gen_Modules
mux2x1 uut(w[i],D[i],Load,in[i]); 
DFlipFlop utt(clk,rst,in[i],Q[i]);
end
endgenerate
endmodule
