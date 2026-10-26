`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/06/2026 08:41:03 AM
// Design Name: 
// Module Name: datapath
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


module datapath(input clk, input reset);
wire [31:0] pcValue;
wire [31:0] readData1, readData2;
wire [31:0] data_memory_out;
wire [31:0] inst_memory_out;
wire [31:0] AluOutput;
wire [31:0] immGenOut;
wire [3:0] AluSel;
wire AluZero;
wire branch,memRead, memToReg,memWrite,ALUsource,regWrite;
wire halt;
wire [1:0] AluOp;
wire [31:0] regWriteData;
wire [31:0] aluInputData2;
wire [31:0] pcPlus4;
wire [31:0] jumpOffset;
wire [31:0] jumpTarget;
wire [31:0] pcInput;

// NEW WIRE: Branch decision output from BranchUnit
wire takeBranch;

// NEW WIRE: PC stops when ECALL / EBREAK is fetched (halt comes from control_unit)


// UPDATED: DataMem takes funct3 (LB/LH/LW/LBU/LHU/SB/SH/SW) and the full byte address AluOutput[7:0]
DataMem DataMemory(clk,memRead,memWrite,inst_memory_out[14:12],AluOutput[7:0],readData2,data_memory_out);
InstMem InstructionMemory(pcValue[7:2],inst_memory_out);
Nbit_mux2x1 #(32) regWriteInput(AluOutput,data_memory_out,memToReg,regWriteData);
RegFile #(32) RegisterFile(clk,reset,inst_memory_out[19:15],inst_memory_out[24:20],inst_memory_out[11:7],regWriteData,regWrite,readData1,readData2);
Nbit_mux2x1 #(32) aluInput2(readData2,immGenOut,ALUsource,aluInputData2);
ALU #(32) aluModule(readData1,aluInputData2,AluSel,AluOutput,AluZero);
ImmGen immGenerator(inst_memory_out,immGenOut);
alu_unit AluControl(inst_memory_out,AluOp,AluSel);
control_unit controlUnit(inst_memory_out,branch,memRead, memToReg,memWrite,ALUsource,regWrite,AluOp,halt);

// NEW MODULE INSTANTIATION: Evaluates BEQ, BNE, BLT, BGE, BLTU, BGEU
BranchUnit branchComparator(branch, inst_memory_out[14:12], readData1, readData2, takeBranch);

assign pcPlus4 = pcValue + 4;
Nbit_shift_left #(32) jumpOffsetModule(immGenOut,jumpOffset);
assign jumpTarget = jumpOffset + pcValue;

// UPDATED MUX: Uses takeBranch instead of (branch & AluZero)
Nbit_mux2x1 #(32) nextPc(pcPlus4,jumpTarget,takeBranch,pcInput);
// UPDATED: PC load is disabled while halt is high (ECALL / EBREAK)
N_bit_register pcRegister(~halt,clk,reset,pcInput,pcValue);
endmodule
