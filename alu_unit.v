`timescale 1ns / 1ps

module alu_unit(
    input [31:0] inst,
    input [1:0] aluOp,
    output reg [4:0] AluSelection
);

always @(*) begin
    if (aluOp == 2'b00)
         AluSelection = 5'b00010; // Load/Store -> ADD
         
    // M Extension 
    else if (aluOp == 2'b10 && inst[31:25] == 7'b0000001) begin
        case (inst[14:12])
            3'b000: AluSelection = 5'b10101; 
            3'b001: AluSelection = 5'b11011; 
            3'b010: AluSelection = 5'b11100; 
            3'b011: AluSelection = 5'b11101; 
            3'b100: AluSelection = 5'b11110; 
            3'b101: AluSelection = 5'b11111; 
            3'b110: AluSelection = 5'b10110; 
            3'b111: AluSelection = 5'b10111; 
            default: AluSelection = 5'b00000;
        endcase
    end
    
    // Branch instructions
    else if(aluOp == 2'b01)
         AluSelection = 5'b00110; 
         
    // R-Type logic (aluOp == 2'b10)
    else if(aluOp == 2'b10 && inst[14:12] == 3'b000 && inst[30] == 1'b0)
         AluSelection = 5'b00010; // ADD
    else if(aluOp == 2'b10 && inst[14:12] == 3'b000 && inst[30] == 1'b1)
         AluSelection = 5'b00110; // SUB
    else if(aluOp == 2'b10 && inst[14:12] == 3'b111 && inst[30] == 1'b0)
         AluSelection = 5'b00000; // AND
    else if(aluOp == 2'b10 && inst[14:12] == 3'b110 && inst[30] == 1'b0)
         AluSelection = 5'b00001; // OR
    else if(aluOp == 2'b10 && inst[14:12] == 3'b100 && inst[30] == 1'b0)
         AluSelection = 5'b00100; // XOR
    else if(aluOp == 2'b10 && inst[14:12] == 3'b001 && inst[30] == 1'b0)
         AluSelection = 5'b01000; // SLL
    else if(aluOp == 2'b10 && inst[14:12] == 3'b101 && inst[30] == 1'b0)
         AluSelection = 5'b01001; // SRL
    else if(aluOp == 2'b10 && inst[14:12] == 3'b101 && inst[30] == 1'b1)
         AluSelection = 5'b01010; // SRA
    else if(aluOp == 2'b10 && inst[14:12] == 3'b010 && inst[30] == 1'b0)
         AluSelection = 5'b00111; // SLT
    else if(aluOp == 2'b10 && inst[14:12] == 3'b011 && inst[30] == 1'b0)
         AluSelection = 5'b00011; // SLTU
         
    // I-Type 
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b000)
         AluSelection = 5'b00010; // ADDI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b100)
         AluSelection = 5'b00100; // XORI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b110)
         AluSelection = 5'b00001; // ORI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b111)
         AluSelection = 5'b00000; // ANDI (Fixed 5'b0000 to 5'b00000)
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b001)
         AluSelection = 5'b01000; // SLLI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b101 && inst[31:25] == 7'b0000000)
         AluSelection = 5'b01001; // SRLI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b101 && inst[30] == 1'b1)
         AluSelection = 5'b01010; // SRAI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b010)
         AluSelection = 5'b00111; // SLTI
    else if((aluOp == 2'b11 || (aluOp == 2'b10 && inst[6:0] == 7'b0010011)) && inst[14:12] == 3'b011)
         AluSelection = 5'b00011; // SLTIU
         
    else
         AluSelection = 5'b00000; // Fallback to safe 0 instead of X
end
endmodule