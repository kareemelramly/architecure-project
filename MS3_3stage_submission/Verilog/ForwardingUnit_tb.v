/*******************************************************************************
 * Module: ForwardingUnit_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Self-checking testbench for ForwardingUnit.v: forwards only
 *              when MEM_WB writes a register equal to rs1 / rs2, never x0.
 *
 * Change history:
 *   11/18/26 - created (split from unit_tb.v)
 ******************************************************************************/

`timescale 1ns / 1ps

module ForwardingUnit_tb;

    reg  [4:0] exRs1;
    reg  [4:0] exRs2;
    reg  [4:0] memWbRd;
    reg        memWbRegWrite;
    wire       forwardA;
    wire       forwardB;
    integer    errors;

    ForwardingUnit dut(
        .exRs1(exRs1),
        .exRs2(exRs2),
        .memWbRd(memWbRd),
        .memWbRegWrite(memWbRegWrite),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    task checkOut(input a, input b, input [8*24-1:0] msg);
        begin
            #1;
            if ((forwardA !== a) || (forwardB !== b)) begin
                errors = errors + 1;
                $display("FAIL %0s: A=%b B=%b", msg, forwardA, forwardB);
            end
        end
    endtask

    initial begin
        errors = 0;
        exRs1 = 5; exRs2 = 6; memWbRd = 5; memWbRegWrite = 1;
        checkOut(1, 0, "rs1 matches");
        memWbRd = 6;
        checkOut(0, 1, "rs2 matches");
        exRs1 = 6;
        checkOut(1, 1, "both match");
        memWbRegWrite = 0;
        checkOut(0, 0, "no regWrite");
        memWbRegWrite = 1; memWbRd = 0; exRs1 = 0; exRs2 = 0;
        checkOut(0, 0, "x0 never forwarded");
        memWbRd = 7; exRs1 = 8; exRs2 = 9;
        checkOut(0, 0, "no match");
        if (errors == 0) $display("PASS ForwardingUnit_tb");
        else             $display("FAIL ForwardingUnit_tb: %0d errors", errors);
        $finish;
    end

endmodule
