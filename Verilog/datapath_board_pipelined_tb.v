/*******************************************************************************
 * Module: datapath_board_pipelined_tb.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Board-level testbench for datapath_board_pipelined.v with the
 *              100 MHz clock. Checks the parts that only exist on the FPGA:
 *              1. Step mode: each BTNC press gives exactly one CPU cycle
 *                 (PC moves by 4 every two presses).
 *              2. Fast run mode: all_instr.hex runs to EBREAK, LD15 lights,
 *                 and the register viewer (SW2-5 = 15) shows x30 = 0xC0DE and
 *                 x31 = 0.
 *              3. Exactly one display anode is active at a time.
 *              The debounce counter is shortened so the simulation is fast.
 *
 * Change history:
 *   11/18/26 - created
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module datapath_board_pipelined_tb;

    reg         sysClk;
    reg         reset;
    reg         stepBtn;
    reg         runMode;
    reg         fastMode;
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
        .PROGRAM_FILE("../Testing/programs/all_instr.hex")
    ) dut(
        .sysClk(sysClk),
        .reset(reset),
        .stepBtn(stepBtn),
        .runMode(runMode),
        .fastMode(fastMode),
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

    task press;
        begin
            stepBtn = 1'b1;
            repeat (40) @(posedge sysClk);
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
        sysClk = 0; reset = 1; stepBtn = 0; runMode = 0; fastMode = 0;
        ledSel = 2'b00; ssdSel = 4'd0; regSel = 5'd0; errors = 0;
        repeat (10) @(posedge sysClk);
        reset = 0;
        repeat (10) @(posedge sysClk);

        // 1. Step mode: 2 presses = C0 + C1 = PC 0 -> 4
        checkView(32'd0, "PC after reset");
        press;
        checkView(32'd4, "PC after 1 step (end of C0)");
        press;
        checkView(32'd4, "PC after 2 steps (C1)");
        for (n = 0; n < 4; n = n + 1) begin
            press;
        end
        checkView(32'd12, "PC after 6 steps");

        // 2. Fast free run to EBREAK
        reset = 1;
        repeat (10) @(posedge sysClk);
        runMode = 1; fastMode = 1;
        reset = 0;
        n = 0;
        while (!leds[15] && (n < 200000)) begin
            @(posedge sysClk);
            n = n + 1;
        end
        repeat (2000) @(posedge sysClk);
        if (!leds[15] || dp) begin
            errors = errors + 1;
            $display("FAIL: halt LED / decimal points not lit");
        end
        ssdSel = 4'd15;
        regSel = 5'd30;
        checkView(32'h0000C0DE, "x30 on display");
        regSel = 5'd31;
        checkView(32'h00000000, "x31 on display");

        if (errors == 0) $display("PASS datapath_board_pipelined_tb");
        else $display("FAIL datapath_board_pipelined_tb: %0d errors", errors);
        $finish;
    end

endmodule

`default_nettype wire
