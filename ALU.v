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
    result = in1+in2; //ADD
else if(aluSel==4'b0110)
    result = in1-in2; //SUB
else if(aluSel==4'b0000)
    result = in1&in2; //AND
else if(aluSel==4'b0001)
    result = in1|in2; //OR
else if (aluSel == 4'b0100)
    result = in1^in2; //XOR 
else if (aluSel == 4'b1000)
    result = in1 << in2[4:0]; //SLL
else if (aluSel == 4'b1001)
    result = in1 >> in2[4:0]; //SRL
else if (aluSel == 4'b1010)
    result = $signed(in1) >>> in2[4:0]; //SRA
else if (aluSel == 4'b0111) 
    result = ($signed(in1) < $signed(in2)) ? 1 : 0; //SLT
else if (aluSel == 4'b0011)
    result = (in1 < in2) ? 1:0;  //SLTU
else
    result = 0;
end
assign zero = (result==0);
endmodule
