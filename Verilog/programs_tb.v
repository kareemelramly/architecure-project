/*******************************************************************************
 * Module: programs_tb.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Runs one assembled test program (hex file) on the pipeline and
 *              checks the signature: x31 == 0 (no failed checks) and
 *              x30 == 0xC0DE (program reached its end), then halt latched.
 *              Run from Verilog/ with: sh ../Testing/programs/run_all.sh
 *
 * Change history:
 *   11/16/26 - created for MS3
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module programs_tb #(parameter PROG = "../Testing/programs/all_instr.hex",
                     parameter BP = 1);
    reg clk = 1'b0, reset = 1'b1;
    reg  [4:0]  sel = 5'd31;
    wire [31:0] rdata;
    wire        halt;
    always #5 clk = ~clk;

    pipeline #(.BP_ENABLE(BP), .PROGRAM_FILE(PROG)) dut(
        .clk(clk), .reset(reset), .dbgRegSel(sel), .dbgRegData(rdata),
        .dbgPC(), .dbgNextPC(), .dbgInst(), .dbgAluResult(), .dbgMemAddr(),
        .dbgMemOut(), .dbgWbData(), .dbgStoreData(), .dbgCtrlFlags(),
        .dbgPipeFlags(), .dbgHalt(halt));

    integer cycles = 0;
    reg [31:0] fails, sig;
    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        while (!halt && cycles < 20000) begin @(posedge clk); cycles = cycles + 1; end
        repeat (12) @(posedge clk);   // let older instructions drain to write-back
        @(negedge clk);
        sel = 5'd31; #1 fails = rdata;
        sel = 5'd30; #1 sig   = rdata;
        if (!halt)                 $display("FAIL %0s (BP=%0d): no halt in %0d cycles", PROG, BP, cycles);
        else if (fails !== 32'd0)  $display("FAIL %0s (BP=%0d): x31 = %0d failed checks", PROG, BP, fails);
        else if (sig !== 32'hC0DE) $display("FAIL %0s (BP=%0d): x30 = %h", PROG, BP, sig);
        else                       $display("PASS %0s (BP=%0d): %0d cycles", PROG, BP, cycles);
        $finish;
    end
endmodule

`default_nettype wire
