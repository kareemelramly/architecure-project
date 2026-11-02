/*******************************************************************************
 * Module: defines.vh
 * Project: femtoRV32
 * Author: Mohamed AboElfotouh
 * Description: Global constants, ALU operations, and opcode definitions.
 *
 * Change history:
 *   10/26/26 - Created initial definitions
 *   10/28/26 - Added branch, memory, ALU, and M-extension definitions
 *   10/30/26 - Merged definitions for full RV32I and RV32M
 ******************************************************************************/

`ifndef DEFINES_VH
`define DEFINES_VH

// Opcode fields inst[6:2]
`define OPC_LOAD      5'b00000
`define OPC_MISC_MEM  5'b00011
`define OPC_OP_IMM    5'b00100
`define OPC_AUIPC     5'b00101
`define OPC_STORE     5'b01000
`define OPC_OP        5'b01100
`define OPC_LUI       5'b01101
`define OPC_BRANCH    5'b11000
`define OPC_JALR      5'b11001
`define OPC_JAL       5'b11011
`define OPC_SYSTEM    5'b11100

// Main Control ALUOp [1:0]
`define ALUOP_ADD     2'b00
`define ALUOP_BRANCH  2'b01
`define ALUOP_RTYPE   2'b10
`define ALUOP_ITYPE   2'b11

// Writeback Selection memToReg [1:0]
`define WB_ALU        2'b00
`define WB_MEM        2'b01
`define WB_PC4        2'b10
`define WB_IMM        2'b11

// ALU Selection AluSel [4:0]
`define ALU_ADD       5'b00010
`define ALU_SUB       5'b00110
`define ALU_AND       5'b00000
`define ALU_OR        5'b00001
`define ALU_XOR       5'b00100
`define ALU_SLL       5'b01000
`define ALU_SRL       5'b01001
`define ALU_SRA       5'b01010
`define ALU_SLT       5'b00111
`define ALU_SLTU      5'b00011

// RV32M Extension AluSel
`define ALU_MUL       5'b10101
`define ALU_MULH      5'b11011
`define ALU_MULHSU    5'b11100
`define ALU_MULHU     5'b11101
`define ALU_DIV       5'b11110
`define ALU_DIVU      5'b11111
`define ALU_REM       5'b10110
`define ALU_REMU      5'b10111

// Branch funct3
`define BR_BEQ        3'b000
`define BR_BNE        3'b001
`define BR_BLT        3'b100
`define BR_BGE        3'b101
`define BR_BLTU       3'b110
`define BR_BGEU       3'b111

// Load/Store funct3
`define MEM_LB        3'b000
`define MEM_LH        3'b001
`define MEM_LW        3'b010
`define MEM_LBU       3'b100
`define MEM_LHU       3'b101
`define MEM_SB        3'b000
`define MEM_SH        3'b001
`define MEM_SW        3'b010

`endif // DEFINES_VH