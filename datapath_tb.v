`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/06/2026 08:41:27 AM
// Design Name: 
// Module Name: datapath_tb
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


module datapath_tb();
reg clk; reg reset;
datapath CPU(clk,reset);
initial begin
clk = 0;
forever #10 clk = ~clk;
end
initial begin
reset=1; #20;
reset=0;
end
endmodule
