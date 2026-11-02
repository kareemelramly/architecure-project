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

/*
module datapath_board(input clk, input reset, input [1:0]ledSel, input[3:0]ssdSel, input ssdClk, output[15:0]leds, output [3:0] Anode, output [6:0] LED_out);
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
DataMem DataMemory(clk,memRead,memWrite,inst_memory_out[14:12],AluOutput[7:0],readData2,data_memory_out);
InstMem InstructionMemory(pcValue[7:2],inst_memory_out);
Nbit_mux2x1 #(32) regWriteInput(AluOutput,data_memory_out,memToReg,regWriteData);
RegFile #(32) RegisterFile(clk,reset,inst_memory_out[19:15],inst_memory_out[24:20],inst_memory_out[11:7],regWriteData,regWrite,readData1,readData2);
Nbit_mux2x1 #(32) aluInput2(readData2,immGenOut,ALUsource,aluInputData2);
ALU #(32) aluModule(readData1,aluInputData2,AluSel,AluOutput,AluZero);
ImmGen immGenerator(inst_memory_out,immGenOut);
alu_unit AluControl(inst_memory_out,AluOp,AluSel);
control_unit controlUnit(inst_memory_out,branch,memRead, memToReg,memWrite,ALUsource,regWrite,AluOp,halt);
assign pcPlus4 = pcValue + 4;
Nbit_shift_left #(32) jumpOffsetModule(immGenOut,jumpOffset);
assign jumpTarget = jumpOffset + pcValue;
Nbit_mux2x1 #(32) nextPc(pcPlus4,jumpTarget,branch & AluZero,pcInput);
N_bit_register pcRegister(~halt,clk,reset,pcInput,pcValue);
assign leds = ((ledSel==2'b00)?inst_memory_out[15:0]:(ledSel==2'b10)?inst_memory_out[31:16]:({2'b0,branch,memRead, memToReg,memWrite,ALUsource,regWrite,AluOp,AluSel,AluZero,branch & AluZero}));
reg [12:0] ssd_output;
always@(*) begin
    if(ssdSel==4'd0)
     ssd_output = pcValue;
    else if(ssdSel==4'd1)
     ssd_output = pcPlus4;
    else if(ssdSel==4'd2)
     ssd_output = jumpTarget;
    else if(ssdSel==4'd3)
     ssd_output = pcInput;
    else if(ssdSel==4'd4)
     ssd_output = readData1;
    else if(ssdSel==4'd5)
     ssd_output = readData2;
    else if(ssdSel==4'd6)
     ssd_output = regWriteData;
    else if(ssdSel==4'd7)
     ssd_output = immGenOut; 
    else if(ssdSel==4'd8)
     ssd_output = jumpOffset; 
    else if(ssdSel==4'd9)
     ssd_output = aluInputData2; 
    else if(ssdSel==4'd10)
     ssd_output = AluOutput; 
    else if(ssdSel==4'd11)
     ssd_output = data_memory_out;    
end
Four_Digit_Seven_Segment_Driver_Optimized(ssdClk,ssd_output,Anode,LED_out);
endmodule
*/