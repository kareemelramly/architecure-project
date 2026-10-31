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
input [4:0] aluSel,
output reg [N-1:0] result, output zero );
wire signed [63:0] mul_ss = $signed(in1) * $signed(in2);
wire signed [63:0] mul_su = $signed(in1) * $signed({1'b0, in2});
wire [63:0]        mul_uu = $unsigned(in1) * $unsigned(in2);
    
always @(*) begin
if (aluSel==5'b00010)
    result = in1+in2; //ADD R & I
else if(aluSel==5'b00110)
    result = in1-in2; //SUB R & I 
else if(aluSel==5'b00000)
    result = in1&in2; //AND R & I 
else if(aluSel==5'b00001)
    result = in1|in2; //OR r & I
else if (aluSel == 5'b00100)
    result = in1^in2; //XOR R & I
else if (aluSel == 5'b01000)
    result = in1 << in2[4:0]; //SLL R & I
else if (aluSel == 5'b01001)
    result = in1 >> in2[4:0]; //SRL R & I
else if (aluSel == 5'b01010)
    result = $signed(in1) >>> in2[4:0]; //SRA R & I 
else if (aluSel == 5'b00111) 
    result = ($signed(in1) < $signed(in2)) ? 1 : 0; //SLT R & I 
else if (aluSel == 5'b00011)
    result = (in1 < in2) ? 1:0;  //SLTU R & I        
else if (aluSel == 5'b10101)
    result  = in1*in2; //MUL
else if (aluSel == 5'b11011)
    result  = mul_ss[63:32]; //MULH
else if (aluSel == 5'b11100)
    result  = mul_su[63:32]; //MULHSU
else if (aluSel == 5'b11101) 
    result  = mul_uu[63:32] ; //MULHU
else if (aluSel == 5'b11110)
    result = $signed(in1) / $signed(in2); //DIV
else if (aluSel == 5'b11111)
    result = in1 / in2; //DIVU
else if (aluSel == 5'b10110)
    result = $signed(in1) % $signed(in2); //REM
else if (aluSel == 5'b10111)
    result = in1 % in2;   //REMU   
else
    result = 0;
end
assign zero = (result == 32'd0);
endmodule
