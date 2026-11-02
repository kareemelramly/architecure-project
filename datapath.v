/*******************************************************************************
 * Module: datapath.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Top-level single-cycle RISC-V processor datapath.
 *
 * Change history:
 *   10/26/26 - Initial single-cycle datapath (7 instructions)
 *   10/27/26 - Added BranchUnit and halt integration
 *   10/29/26 - Expanded multiplexers for LUI, AUIPC, JAL, JALR
 *   10/30/26 - Unified merge of all 42 base instructions and RV32M
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module datapath(
    input clk,
    input reset
);

    wire [31:0] pcValue;
    wire [31:0] pcInput;
    wire [31:0] pcPlus4;
    wire [31:0] jumpTarget;
    wire [31:0] jalrTarget;
    wire [31:0] instMemoryOut;
    wire [31:0] readData1;
    wire [31:0] readData2;
    wire [31:0] immGenOut;
    wire [31:0] aluInputData1;
    wire [31:0] aluInputData2;
    wire [31:0] aluOutput;
    wire [31:0] dataMemoryOut;
    wire [31:0] regWriteData;
    wire [4:0]  aluSel;
    wire [1:0]  memToReg;
    wire [1:0]  aluOp;
    wire branch;
    wire memRead;
    wire memWrite;
    wire aluSource;
    wire aluSrcA;
    wire regWrite;
    wire isJal;
    wire isJalr;
    wire halt;
    wire takeBranch;
    wire aluZero;
    wire pcLoad;

    assign pcLoad = ~halt;

    N_bit_register #(32) pcRegister(
        .Load(pcLoad),
        .clk(clk),
        .rst(reset),
        .D(pcInput),
        .Q(pcValue)
    );

    assign pcPlus4 = pcValue + 32'd4;

    InstMem InstructionMemory(
        .addr(pcValue[8:2]),
        .data_out(instMemoryOut)
    );

    control_unit controlUnit(
        .inst(instMemoryOut),
        .branch(branch),
        .memRead(memRead),
        .memWrite(memWrite),
        .aluSource(aluSource),
        .aluSrcA(aluSrcA),
        .regWrite(regWrite),
        .isJal(isJal),
        .isJalr(isJalr),
        .halt(halt),
        .memToReg(memToReg),
        .aluOp(aluOp)
    );

    RegFile #(32) RegisterFile(
        .clk(clk),
        .rst(reset),
        .readreg1(instMemoryOut[19:15]),
        .readreg2(instMemoryOut[24:20]),
        .writereg(instMemoryOut[11:7]),
        .writedata(regWriteData),
        .regwrite(regWrite),
        .readdata1(readData1),
        .readdata2(readData2)
    );

    ImmGen immGenerator(
        .inst(instMemoryOut),
        .genOut(immGenOut)
    );

    alu_unit AluControl(
        .aluOp(aluOp),
        .inst(instMemoryOut),
        .aluSelection(aluSel)
    );

    assign aluInputData1 = (aluSrcA)    ? pcValue   : readData1;
    assign aluInputData2 = (aluSource) ? immGenOut : readData2;

    ALU #(32) aluModule(
        .aluSel(aluSel),
        .in1(aluInputData1),
        .in2(aluInputData2),
        .result(aluOutput),
        .zero(aluZero)
    );

    BranchUnit branchComparator(
        .branch(branch),
        .funct3(instMemoryOut[14:12]),
        .readData1(readData1),
        .readData2(readData2),
        .takeBranch(takeBranch)
    );

    DataMem DataMemory(
        .clk(clk),
        .memRead(memRead),
        .memWrite(memWrite),
        .funct3(instMemoryOut[14:12]),
        .addr(aluOutput[7:0]),
        .dataIn(readData2),
        .dataOut(dataMemoryOut)
    );

    assign jumpTarget = pcValue + immGenOut;
    assign jalrTarget = (readData1 + immGenOut) & ~32'd1;

    assign pcInput = (isJalr)              ? jalrTarget :
                     (isJal || takeBranch) ? jumpTarget : pcPlus4;

    assign regWriteData = (memToReg == `WB_ALU) ? aluOutput     :
                          (memToReg == `WB_MEM) ? dataMemoryOut :
                          (memToReg == `WB_PC4) ? pcPlus4       : immGenOut;

endmodule