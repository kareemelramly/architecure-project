`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/29/2026 09:00:11 AM
// Design Name: 
// Module Name: alu_unit
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


module alu_unit(input [31:0] inst,
input [1:0] aluOp,
output reg [3:0] AluSelection);
always @(*) begin
if (aluOp==2'b00)
     AluSelection = 4'b0010;
else if(aluOp==2'b01)
     AluSelection = 4'b0110;
else if(aluOp==2'b10 && inst[14:12]== 3'b000 && inst[30]==1'b0)
     AluSelection = 4'b0010;
else if(aluOp==2'b10 && inst[14:12]== 3'b000 && inst[30]==1'b1)
     AluSelection = 4'b0110;
else if(aluOp==2'b10 && inst[14:12]== 3'b111 && inst[30]==1'b0)
     AluSelection = 4'b0000;
else if(aluOp==2'b10 && inst[14:12]== 3'b110 && inst[30]== 1'b0)
     AluSelection = 4'b0001;
else if(aluOp==2'b10 && inst[14:12]== 3'b100 && inst[30]== 1'b0)
    AluSelection = 4'b0100; 
else if(aluOp==2'b10 && inst[14:12]== 3'b001 && inst[30]== 1'b0)
    AluSelection = 4'b1000; 
else if(aluOp == 2'b10 && inst[14:12]== 3'b101 && inst[30]== 1'b0)
    AluSelection = 4'b1001; 
else if(aluOp == 2'b10 && inst[14:12]== 3'b101 && inst[30]== 1'b1)
    AluSelection = 4'b1010; 
else if(aluOp == 2'b10 && inst[14:12]== 3'b010 && inst[30]== 1'b0)
    AluSelection = 4'b0111;
else if(aluOp == 2'b10 && inst[14:12]== 3'b011 && inst[30]== 1'b0)
    AluSelection = 4'b0011;   
//chosen aluop = 11 for i-type to avoid gate overhead in alu
else if(aluOp == 2'b11 && inst[14:12]== 3'b000)
    AluSelection  = 4'b0010; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b100)
    AluSelection  = 4'b0100; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b110)
    AluSelection  = 4'b0001; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b111)
    AluSelection  = 4'b0000; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b001)
    AluSelection  = 4'b1000; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b101 && inst[31:25] == 7'b0000000)
    AluSelection  = 4'b1001; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b101 && inst[30]==1'b1) //same funct3 but diff funct7
    AluSelection  = 4'b1010; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b010)
    AluSelection  = 4'b0111; 
else if(aluOp == 2'b11 && inst[14:12]== 3'b011)
    AluSelection  = 4'b0011; 
else
     AluSelection = 4'bx;
end
endmodule
