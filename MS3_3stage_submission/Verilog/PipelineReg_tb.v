/*******************************************************************************
 * Module: PipelineReg_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Self-checking testbench for PipelineReg.v: holds without
 *              load, loads with load, flush loads zeros and wins over load.
 *
 * Change history:
 *   11/18/26 - created (split from unit_tb.v)
 ******************************************************************************/

`timescale 1ns / 1ps

module PipelineReg_tb;

    reg        clk;
    reg        rst;
    reg        load;
    reg        flush;
    reg  [7:0] D;
    wire [7:0] Q;
    integer    errors;

    PipelineReg #(8) dut(
        .clk(clk),
        .rst(rst),
        .load(load),
        .flush(flush),
        .D(D),
        .Q(Q)
    );

    always #5 clk = ~clk;

    task step(input l, input f, input [7:0] d, input [7:0] q,
              input [8*24-1:0] msg);
        begin
            @(negedge clk);
            load = l; flush = f; D = d;
            @(negedge clk);
            if (Q !== q) begin
                errors = errors + 1;
                $display("FAIL %0s: Q=%h expected %h", msg, Q, q);
            end
        end
    endtask

    initial begin
        clk = 0; rst = 1; load = 0; flush = 0; D = 0; errors = 0;
        #12 rst = 0;
        step(0, 0, 8'hA5, 8'h00, "holds without load");
        step(1, 0, 8'hA5, 8'hA5, "loads");
        step(0, 0, 8'h3C, 8'hA5, "holds loaded value");
        step(0, 1, 8'h3C, 8'h00, "flush clears");
        step(1, 0, 8'hFF, 8'hFF, "loads again");
        step(1, 1, 8'h77, 8'h00, "flush wins over load");
        if (errors == 0) $display("PASS PipelineReg_tb");
        else             $display("FAIL PipelineReg_tb: %0d errors", errors);
        $finish;
    end

endmodule
