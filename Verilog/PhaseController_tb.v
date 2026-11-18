/*******************************************************************************
 * Module: PhaseController_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Self-checking testbench for PhaseController.v: reset gives
 *              C0, then C0 / C1 alternate every cycle and exactly one of
 *              isC0 / isC1 is high.
 *
 * Change history:
 *   11/18/26 - created (split from unit_tb.v)
 ******************************************************************************/

`timescale 1ns / 1ps

module PhaseController_tb;

    reg     clk;
    reg     rst;
    wire    phase;
    wire    isC0;
    wire    isC1;
    integer errors;
    integer i;

    PhaseController dut(
        .clk(clk),
        .rst(rst),
        .phase(phase),
        .isC0(isC0),
        .isC1(isC1)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; errors = 0;
        #12;
        if (!isC0 || isC1) errors = errors + 1;
        rst = 0;
        for (i = 0; i < 10; i = i + 1) begin
            @(negedge clk);
            if ((isC0 !== (i % 2 == 1)) || (isC1 === isC0)) begin
                errors = errors + 1;
                $display("FAIL cycle %0d: isC0=%b isC1=%b", i, isC0, isC1);
            end
        end
        if (errors == 0) $display("PASS PhaseController_tb");
        else $display("FAIL PhaseController_tb: %0d errors", errors);
        $finish;
    end

endmodule
