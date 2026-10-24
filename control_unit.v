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


module control_unit(input [31:0] inst,
output reg branch,memRead, memToReg,memWrite,ALUsource,regWrite,
output reg [1:0] aluOp);
always @(*) begin
if (inst[6:2]==5'b01100)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00010001;
else if(inst[6:2]==5'b00000)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b01100011;
else if(inst[6:2]==5'b01000)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00000110;
else if(inst[6:2]==5'b11000)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b10001000;
end
endmodule
