`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/29/2026 08:30:51 AM
// Design Name: 
// Module Name: ALU
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


module ALU #(parameter N = 32) (
input [N-1:0] in1, in2,
input [3:0] aluSel,
output reg [N-1:0] result, output zero );
always @(*) begin
if (aluSel==4'b0010)
    result = in1+in2;
else if(aluSel==4'b0110)
    result = in1-in2;
else if(aluSel==4'b0000)
    result = in1&in2;
else if(aluSel==4'b0001)
    result = in1|in2;
else if (aluSel == 4'b0100)
    result = in1^in2; 
else
    result = 0;
end
assign zero = (result==0);
endmodule
