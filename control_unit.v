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
output reg [1:0] aluOp,
output reg halt);
always @(*) begin
halt = 1'b0;
if (inst[6:2]==5'b01100)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00010001;
else if(inst[6:2]==5'b00000)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b01100011;
else if(inst[6:2]==5'b01000)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00000110;
else if(inst[6:2]==5'b11000)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b10001000;
// FENCE, FENCE.TSO, PAUSE (all share the MISC-MEM opcode): no registers, memory or PC side effects (NOP)
else if(inst[6:2]==5'b00011)
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00000000;
// SYSTEM opcode: ECALL (imm=0) and EBREAK (imm=1) stop the PC, any other SYSTEM encoding is a NOP
else if(inst[6:2]==5'b11100) begin
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00000000;
    if (inst[14:12]==3'b000 && inst[11:7]==5'b00000 && inst[19:15]==5'b00000 && inst[31:21]==11'b0)
        halt = 1'b1;
end
else
    {branch,memRead, memToReg,aluOp,memWrite,ALUsource,regWrite} = 8'b00000000;
end
endmodule
