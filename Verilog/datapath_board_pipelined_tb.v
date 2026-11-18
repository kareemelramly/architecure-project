/*******************************************************************************
 * Module: datapath_board_pipelined_tb.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Board-level testbench for datapath_board_pipelined.v with the
 *              100 MHz clock, step mode only (BTNC = CPU clock). Checks:
 *              1. Each BTNC press gives exactly one CPU cycle, also with a
 *                 bouncing button (PC moves by 4 every two presses).
 *              2. Pressing until EBREAK: all_instr halts, LD15 and the dots
 *                 light, and the register viewer (SW5-SW2 = 15) shows
 *                 x30 = 0xC0DE and x31 = 0; the PC stays at 0x244.
 *              3. Exactly one display anode is active at a time.
 *              The debounce counter is shortened so the simulation is fast.
 *
 * Change history:
 *   11/18/26 - created
 *   11/18/26 - step mode only (CpuClockGen and run modes removed)
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module datapath_board_pipelined_tb;

    reg         sysClk;
    reg         reset;
    reg         stepBtn;
    reg  [1:0]  ledSel;
    reg  [3:0]  ssdSel;
    reg  [4:0]  regSel;
    wire [15:0] leds;
    wire [7:0]  Anode;
    wire [6:0]  LED_out;
    wire        dp;
    wire [7:0]  anodeOn;
    integer     errors;
    integer     n;

    datapath_board_pipelined #(
        .PROGRAM_FILE("all_instr")
    ) dut(
        .sysClk(sysClk),
        .reset(reset),
        .stepBtn(stepBtn),
        .ledSel(ledSel),
        .ssdSel(ssdSel),
        .regSel(regSel),
        .leds(leds),
        .Anode(Anode),
        .LED_out(LED_out),
        .dp(dp)
    );

    defparam dut.stepDebounce.CNT_BITS = 4;

    always #5 sysClk = ~sysClk;     // 100 MHz

    // One press: a few bounces, held, released with a bounce
    task press;
        begin
            stepBtn = 1'b1;
            repeat (3) @(posedge sysClk);
            stepBtn = 1'b0;
            repeat (2) @(posedge sysClk);
            stepBtn = 1'b1;
            repeat (40) @(posedge sysClk);
            stepBtn = 1'b0;
            repeat (2) @(posedge sysClk);
            stepBtn = 1'b1;
            repeat (2) @(posedge sysClk);
            stepBtn = 1'b0;
            repeat (40) @(posedge sysClk);
        end
    endtask

    task checkView(input [31:0] v, input [8*24-1:0] msg);
        begin
            #1;
            if (dut.ssdView !== v) begin
                errors = errors + 1;
                $display("FAIL %0s: display %h expected %h",
                         msg, dut.ssdView, v);
            end
        end
    endtask


    // Read the eight displayed decimal digits by watching the anodes and
    // segments for one full refresh round (digit 0 = ones)
    reg [31:0] shown;
    function [3:0] segToDigit(input [6:0] s);
        case (s)
            7'b0000001: segToDigit = 4'd0;
            7'b1001111: segToDigit = 4'd1;
            7'b0010010: segToDigit = 4'd2;
            7'b0000110: segToDigit = 4'd3;
            7'b1001100: segToDigit = 4'd4;
            7'b0100100: segToDigit = 4'd5;
            7'b0100000: segToDigit = 4'd6;
            7'b0001111: segToDigit = 4'd7;
            7'b0000000: segToDigit = 4'd8;
            7'b0000100: segToDigit = 4'd9;
            default:    segToDigit = 4'hF;
        endcase
    endfunction

    task checkDecimal(input [31:0] bcdExpected, input [8*24-1:0] msg);
        integer k;
        begin
            repeat (200) @(posedge sysClk);       // converter settles
            shown = 32'd0;
            for (k = 0; k < 8; k = k + 1) begin
                wait (Anode == ~(8'd1 << k));
                #1;
                shown[k*4 +: 4] = segToDigit(LED_out);
                wait (Anode != ~(8'd1 << k));
            end
            if (shown !== bcdExpected) begin
                errors = errors + 1;
                $display("FAIL %0s: digits %h expected %h",
                         msg, shown, bcdExpected);
            end
        end
    endtask

    // Exactly one active-low anode: anodeOn is one-hot
    assign anodeOn = ~Anode;

    always @(posedge sysClk) begin
        if (!reset && ((anodeOn == 8'd0) ||
                       ((anodeOn & (anodeOn - 8'd1)) != 8'd0))) begin
            errors = errors + 1;
            $display("FAIL: anodes %b", Anode);
        end
    end

    initial begin
        sysClk = 0; reset = 1; stepBtn = 0;
        ledSel = 2'b00; ssdSel = 4'd0; regSel = 5'd0; errors = 0;
        repeat (10) @(posedge sysClk);
        reset = 0;
        repeat (10) @(posedge sysClk);

        // 1. One press = one cycle, even with bounces: PC 0 -> 4 -> 4 -> 8
        checkView(32'd0, "PC after reset");
        press;
        checkView(32'd4, "PC after 1 press (end of C0)");
        press;
        checkView(32'd4, "PC after 2 presses (C1)");
        for (n = 0; n < 4; n = n + 1) begin
            press;
        end
        checkView(32'd12, "PC after 6 presses");

        // 2. Keep pressing until EBREAK halts the CPU
        n = 6;
        while (!leds[15] && (n < 400)) begin
            press;
            n = n + 1;
        end
        for (n = 0; n < 4; n = n + 1) begin
            press;                      // older instructions finish
        end
        if (!leds[15] || dp) begin
            errors = errors + 1;
            $display("FAIL: halt LED / decimal points not lit");
        end
        checkView(32'h00000244, "PC frozen after EBREAK");
        ssdSel = 4'd15;
        regSel = 5'd30;
        checkView(32'h0000C0DE, "x30 on display");
        checkDecimal(32'h00049374, "x30 shows 49374");   // 0xC0DE = 49374
        regSel = 5'd31;
        checkView(32'h00000000, "x31 on display");

        if (errors == 0) $display("PASS datapath_board_pipelined_tb");
        else $display("FAIL datapath_board_pipelined_tb: %0d errors", errors);
        $finish;
    end

endmodule

`default_nettype wire
