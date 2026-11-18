/*******************************************************************************
 * Module: datapath_board_pipelined.v
 * Project: femtoRV32
 * Author: Mostafa Fayed, Kareem Elramly
 * Description: FPGA wrapper (Nexys A7-100T) for the 5-stage pipelined femtoRV32.
 *              BTNC steps one CPU clock cycle (runMode = 0) or SW-selected free run.
 *              8-digit display shows a 32-bit view chosen by ssdSel:
 *              0 PC, 1 next PC, 2 instruction in ID, 3 ALU result, 4 memory address,
 *              5 memory data out, 6 write-back data, 7 store data, 15 x[regSel]
 *              LEDs show a 16-bit view chosen by ledSel (LD15 is always the halt flag):
 *              00 inst[14:0], 10 inst[30:16], 01 control flags, 11 pipeline flags
 *              Decimal points and LD15 light when the processor has halted (EBREAK).
 *
 * Change history:
 *   11/16/26 - rewritten around pipeline.v for MS3
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module datapath_board_pipelined #(parameter BP_ENABLE    = 1,
                                  parameter PROGRAM_FILE = "")(
    input  wire        sysClk,
    input  wire        stepBtn,
    input  wire        reset,
    input  wire        runMode,
    input  wire        fastMode,
    input  wire [1:0]  ledSel,
    input  wire [3:0]  ssdSel,
    input  wire [4:0]  regSel,
    output reg  [15:0] leds,
    output wire [7:0]  Anode,
    output wire [6:0]  LED_out,
    output wire        dp
);
    wire stepPulse, cpuClk;
    Debounce deb(.clk(sysClk), .in(stepBtn), .pulse(stepPulse));
    CpuClockGen cg(.sysClk(sysClk), .stepPulse(stepPulse), .runMode(runMode),
                   .fastMode(fastMode), .cpuClk(cpuClk));

    wire [31:0] dbgRegData, dbgPC, dbgNextPC, dbgInst, dbgAluResult,
                dbgMemAddr, dbgMemOut, dbgWbData, dbgStoreData;
    wire [15:0] dbgCtrlFlags, dbgPipeFlags;
    wire        dbgHalt;

    pipeline #(.BP_ENABLE(BP_ENABLE), .PROGRAM_FILE(PROGRAM_FILE)) cpu(
        .clk(cpuClk), .reset(reset), .dbgRegSel(regSel),
        .dbgRegData(dbgRegData), .dbgPC(dbgPC), .dbgNextPC(dbgNextPC),
        .dbgInst(dbgInst), .dbgAluResult(dbgAluResult),
        .dbgMemAddr(dbgMemAddr), .dbgMemOut(dbgMemOut),
        .dbgWbData(dbgWbData), .dbgStoreData(dbgStoreData),
        .dbgCtrlFlags(dbgCtrlFlags), .dbgPipeFlags(dbgPipeFlags),
        .dbgHalt(dbgHalt));

    reg [31:0] view;
    always @(*) begin
        case (ssdSel)
            4'd0:    view = dbgPC;
            4'd1:    view = dbgNextPC;
            4'd2:    view = dbgInst;
            4'd3:    view = dbgAluResult;
            4'd4:    view = dbgMemAddr;
            4'd5:    view = dbgMemOut;
            4'd6:    view = dbgWbData;
            4'd7:    view = dbgStoreData;
            4'd15:   view = dbgRegData;
            default: view = 32'd0;
        endcase
        case (ledSel)
            2'b00:   leds = dbgInst[15:0];
            2'b10:   leds = dbgInst[31:16];
            2'b01:   leds = dbgCtrlFlags;
            default: leds = dbgPipeFlags;
        endcase
        leds[15] = dbgHalt;          // LD15 = halted, in every view
    end

    SevenSegHex8 ssd(.clk(sysClk), .value(view), .dpOn(dbgHalt),
                     .Anode(Anode), .LED_out(LED_out), .dp(dp));
endmodule

`default_nettype wire
