/*******************************************************************************
 * Module: datapath_board_pipelined.v
 * Project: femtoRV32
 * Author: Mostafa Fayed, Kareem Elramly
 * Description: FPGA top level (Nexys A7-100T) for the 3-stage pipelined
 *              femtoRV32.
 *              SW15 = reset, BTNC = one CPU clock cycle: the debounced button
 *              is the CPU clock (step mode only). The 8-digit display shows
 *              the 32-bit
 *              value chosen by SW5..SW2 (ssdSel):
 *                0 PC, 1 instruction in ID, 2 EX result, 3 memory address,
 *                4 memory data out, 5 write-back data, 6 store data,
 *                15 register x[SW12..SW8]
 *              LEDs show the 16-bit value chosen by SW1..SW0 (ledSel):
 *                00 instruction[14:0], 10 instruction[30:16], 01 flags
 *              LD15 and the decimal points light when EBREAK halted the CPU.
 *              PROGRAM_FILE picks the built-in program in UnifiedMem.v.
 *              The reset switch is synchronised to sysClk with two
 *              flip-flops (brute-force synchronizer). The CPU clock comes
 *              from a flip-flop in Debounce and is 0 during reset, so the
 *              CPU always leaves reset before its first clock edge.
 *
 * Change history:
 *   11/16/26 - rewritten around pipeline.v for MS3
 *   11/18/26 - 3-stage pipeline, input synchronizers, guideline clean-up;
 *              program selected by name (built into UnifiedMem)
 *   11/18/26 - step mode only: CpuClockGen and SW6/SW7 removed
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module datapath_board_pipelined #(
    parameter PROGRAM_FILE = "all_instr"  // all_instr, hazards, nops_halt, demo
)(
    input  wire        sysClk,
    input  wire        reset,
    input  wire        stepBtn,
    input  wire [1:0]  ledSel,
    input  wire [3:0]  ssdSel,
    input  wire [4:0]  regSel,
    output wire [15:0] leds,
    output wire [7:0]  Anode,
    output wire [6:0]  LED_out,
    output wire        dp
);

    wire        rstMeta;
    wire        rst;
    wire        cpuClk;

    wire [31:0] dbgRegData;
    wire [31:0] dbgPC;
    wire [31:0] dbgInst;
    wire [31:0] dbgAluResult;
    wire [31:0] dbgMemAddr;
    wire [31:0] dbgMemOut;
    wire [31:0] dbgWbData;
    wire [31:0] dbgStoreData;
    wire [15:0] dbgFlags;
    wire        dbgHalt;

    reg  [31:0] ssdView;
    reg  [14:0] ledView;

    // ---------------- Reset synchronizer (2 flip-flops) ----------------
    DFlipFlop rstSync0(
        .clk(sysClk),
        .rst(1'b0),
        .D(reset),
        .Q(rstMeta)
    );

    DFlipFlop rstSync1(
        .clk(sysClk),
        .rst(1'b0),
        .D(rstMeta),
        .Q(rst)
    );

    // ---------------- CPU clock: one BTNC press = one cycle ----------------
    Debounce stepDebounce(
        .clk(sysClk),
        .rst(rst),
        .in(stepBtn),
        .out(cpuClk)
    );

    // ---------------- CPU ----------------
    pipeline #(
        .PROGRAM_FILE(PROGRAM_FILE)
    ) cpu(
        .clk(cpuClk),
        .rst(rst),
        .dbgRegSel(regSel),
        .dbgRegData(dbgRegData),
        .dbgPC(dbgPC),
        .dbgInst(dbgInst),
        .dbgAluResult(dbgAluResult),
        .dbgMemAddr(dbgMemAddr),
        .dbgMemOut(dbgMemOut),
        .dbgWbData(dbgWbData),
        .dbgStoreData(dbgStoreData),
        .dbgFlags(dbgFlags),
        .dbgHalt(dbgHalt)
    );

    // ---------------- Display / LED views ----------------
    always @* begin
        case (ssdSel)
            4'd0:    ssdView = dbgPC;
            4'd1:    ssdView = dbgInst;
            4'd2:    ssdView = dbgAluResult;
            4'd3:    ssdView = dbgMemAddr;
            4'd4:    ssdView = dbgMemOut;
            4'd5:    ssdView = dbgWbData;
            4'd6:    ssdView = dbgStoreData;
            4'd15:   ssdView = dbgRegData;
            default: ssdView = 32'd0;
        endcase
    end

    always @* begin
        case (ledSel)
            2'b00:   ledView = dbgInst[14:0];
            2'b10:   ledView = dbgInst[30:16];
            2'b01:   ledView = dbgFlags[14:0];
            default: ledView = 15'd0;
        endcase
    end

    assign leds = {dbgHalt, ledView};

    SevenSegDecimal8 display(
        .clk(sysClk),
        .rst(rst),
        .dpOn(dbgHalt),
        .value(ssdView),
        .Anode(Anode),
        .LED_out(LED_out),
        .dp(dp)
    );

endmodule

`default_nettype wire
