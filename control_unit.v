`timescale 1ns / 1ps

module control_unit(
    input [31:0] inst,
    output reg branch,
    output reg memRead,
    output reg [1:0] memToReg,   // 00: ALU, 01: Mem, 10: PC+4, 11: Imm
    output reg memWrite,
    output reg ALUsource,        // ALU In2: 0 = rs2, 1 = Imm
    output reg ALUSrcA,          // ALU In1: 0 = rs1, 1 = PC (for AUIPC)
    output reg regWrite,
    output reg [1:0] aluOp,
    output reg isJal,
    output reg isJalr
);
    wire [6:2] opcode = inst[6:2];

    always @(*) begin
        // Safe default assignments
        branch    = 1'b0;
        memRead   = 1'b0;
        memToReg  = 2'b00;
        memWrite  = 1'b0;
        ALUsource = 1'b0;
        ALUSrcA   = 1'b0;
        regWrite  = 1'b0;
        aluOp     = 2'b00;
        isJal     = 1'b0;
        isJalr    = 1'b0;

        case (opcode)
            // R-type (add, sub, or, and, etc.)
            5'b01100: begin
                regWrite = 1'b1;
                aluOp    = 2'b10;
            end

            // I-type ALU (addi, andi, etc. for Member 1)
            5'b00100: begin
                regWrite  = 1'b1;
                ALUsource = 1'b1;
                aluOp     = 2'b10;
            end

            // Loads (lw, lb, lh, etc.)
            5'b00000: begin
                memRead   = 1'b1;
                memToReg  = 2'b01;
                ALUsource = 1'b1;
                regWrite  = 1'b1;
                aluOp     = 2'b00; // ADD
            end

            // Stores (sw, sb, sh)
            5'b01000: begin
                memWrite  = 1'b1;
                ALUsource = 1'b1;
                aluOp     = 2'b00; // ADD
            end

            // Branches (beq, bne, blt, bge, bltu, bgeu)
            5'b11000: begin
                branch = 1'b1;
                aluOp  = 2'b01;
            end

            // LUI (Load Upper Immediate)
            5'b01101: begin
                regWrite = 1'b1;
                memToReg = 2'b11; // Write immGenOut directly to rd
            end

            // AUIPC (Add Upper Immediate to PC)
            5'b00101: begin
                regWrite  = 1'b1;
                ALUSrcA   = 1'b1; // Select pcValue as ALU In1
                ALUsource = 1'b1; // Select immGenOut as ALU In2
                aluOp     = 2'b00; // ADD
                memToReg  = 2'b00; // Write ALU output to rd
            end

            // JAL (Jump and Link)
            5'b11011: begin
                isJal    = 1'b1;
                regWrite = 1'b1;
                memToReg = 2'b10; // Write PC+4 to rd
            end

            // JALR (Jump and Link Register)
            5'b11001: begin
                isJalr   = 1'b1;
                regWrite = 1'b1;
                memToReg = 2'b10; // Write PC+4 to rd
            end

            default: begin
                // Defaults already set
            end
        endcase
    end
endmodule