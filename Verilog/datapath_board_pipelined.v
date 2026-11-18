/*******************************************************************************
 * Module: datapath_board_pipelined.v
 * Project: femtoRV32
 * Author: Mostafa Fayed, Kareem Elramly
 * Description: FPGA top level (Nexys A7-100T) for the 3-stage pipelined
 *              femtoRV32.
 *              SW15 = reset, BTNC = one CPU clock cycle: the debounced button
 *              is the CPU clock (step mode only).
 *              The 8-digit display shows, in decimal, the value chosen by
 *              SW3..SW1 (ssdSel):
 *                0 PC (IF)               4 memory data out
 *                1 instruction in ID     5 store data (MEM)
 *                2 EX result             6 write-back data
 *                3 memory address        7 write-back register number
 *              LD14..LD0 show the instruction in ID, chosen by SW0 (ledSel):
 *                0 instruction[14:0], 1 instruction[30:16]
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
 *   11/18/26 - register viewer (regSel, SW12..SW8) removed with the
 *              register file debug port
 *   11/18/26 - CPU debug ports removed: views reduced to PC, instruction
 *              and write-back data; flag view removed
 *   11/18/26 - ssdSel on SW3..SW1 with 8 views; default program demo
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module datapath_board_pipelined #(
    parameter PROGRAM_FILE = "quick"  // quick, all_instr, demo, hazards,
                                      // nops_halt
)(
    input  wire        sysClk,
    input  wire        reset,
    input  wire        stepBtn,
    input  wire        ledSel,
    input  wire [2:0]  ssdSel,
    output wire [15:0] leds,
    output wire [7:0]  Anode,
    output wire [6:0]  LED_out,
    output wire        dp
);

    wire        rstMeta;
    wire        rst;
    wire        cpuClk;

    wire [31:0] cpuPC;
    wire [31:0] cpuInst;
    wire [31:0] cpuExResult;
    wire [31:0] cpuMemAddr;
    wire [31:0] cpuMemData;
    wire [31:0] cpuStoreData;
    wire [31:0] cpuWbData;
    wire [4:0]  cpuWbRd;
    wire        cpuHalted;

    reg  [31:0] ssdView;
    wire [14:0] ledView;

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
        .pcOut(cpuPC),
        .instOut(cpuInst),
        .exResultOut(cpuExResult),
        .memAddrOut(cpuMemAddr),
        .memDataOut(cpuMemData),
        .storeDataOut(cpuStoreData),
        .wbDataOut(cpuWbData),
        .wbRdOut(cpuWbRd),
        .halted(cpuHalted)
    );

    // ---------------- Display / LED views ----------------
    always @* begin
        case (ssdSel)
            3'd0:    ssdView = cpuPC;
            3'd1:    ssdView = cpuInst;
            3'd2:    ssdView = cpuExResult;
            3'd3:    ssdView = cpuMemAddr;
            3'd4:    ssdView = cpuMemData;
            3'd5:    ssdView = cpuStoreData;
            3'd6:    ssdView = cpuWbData;
            default: ssdView = {27'd0, cpuWbRd};
        endcase
    end

    assign ledView = (ledSel) ? cpuInst[30:16] : cpuInst[14:0];
    assign leds    = {cpuHalted, ledView};

    SevenSegDecimal8 display(
        .clk(sysClk),
        .rst(rst),
        .dpOn(cpuHalted),
        .value(ssdView),
        .Anode(Anode),
        .LED_out(LED_out),
        .dp(dp)
    );

endmodule

`default_nettype wire
