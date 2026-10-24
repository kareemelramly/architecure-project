`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/22/2026 08:55:04 AM
// Design Name: 
// Module Name: ImmGen
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


module ImmGen (input [31:0] inst, output [31:0] gen_out);
wire [11:0] i0 = inst[31:20];
wire [11:0] i1 = {inst[31:25],inst[11:7]};
wire [11:0] i2 = {inst[31],inst[7],inst[30:25],inst[11:8]};
wire [11:0] opt,final;
Nbit_mux2x1 #(12) uut(i0,i1,inst[5],opt);
Nbit_mux2x1 #(12) uut4(opt,i2,inst[6],final);
//wire [31:0] sign_extented = $signed(final);\
assign gen_out = $signed(final);
//wire [31:0] BEQ_value;
//Nbit_shift_left #(32) uut2 (sign_extented,BEQ_value);
//Nbit_mux2x1 #(32) uut3(sign_extented,BEQ_value,inst[6],gen_out);
endmodule
