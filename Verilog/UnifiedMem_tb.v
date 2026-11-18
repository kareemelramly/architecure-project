/*******************************************************************************
 * Module: UnifiedMem_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Self-checking testbench for UnifiedMem.v: little-endian word
 *              read, LB/LBU/LH/LHU extension, SB/SH/SW byte-granular writes,
 *              memRead = 0 gives 0, and no write without memWrite.
 *
 * Change history:
 *   11/18/26 - created (split from unit_tb.v)
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module UnifiedMem_tb;

    reg         clk;
    reg         memRead;
    reg         memWrite;
    reg  [2:0]  funct3;
    reg  [9:0]  addr;
    reg  [31:0] dataIn;
    wire [31:0] dataOut;
    integer     errors;

    UnifiedMem #(
        .ADDR_BITS(10),
        .PROGRAM_FILE("")
    ) dut(
        .clk(clk),
        .memRead(memRead),
        .memWrite(memWrite),
        .funct3(funct3),
        .addr(addr),
        .dataIn(dataIn),
        .dataOut(dataOut)
    );

    always #5 clk = ~clk;

    task store(input [9:0] a, input [2:0] f, input [31:0] d);
        begin
            @(negedge clk);
            addr = a; funct3 = f; dataIn = d; memWrite = 1'b1;
            @(negedge clk);
            memWrite = 1'b0;
        end
    endtask

    task checkOut(input [9:0] a, input [2:0] f, input [31:0] v,
                input [8*24-1:0] msg);
        begin
            addr = a; funct3 = f;
            #1;
            if (dataOut !== v) begin
                errors = errors + 1;
                $display("FAIL %0s: got %h expected %h", msg, dataOut, v);
            end
        end
    endtask

    initial begin
        clk = 0; errors = 0; memRead = 1; memWrite = 0;
        funct3 = `MEM_LW; addr = 0; dataIn = 0;
        store(10'h300, `MEM_SW, 32'h80F1F2F3);
        checkOut(10'h300, `MEM_LW,  32'h80F1F2F3, "lw");
        checkOut(10'h300, `MEM_LB,  32'hFFFFFFF3, "lb sign");
        checkOut(10'h300, `MEM_LBU, 32'h000000F3, "lbu");
        checkOut(10'h302, `MEM_LH,  32'hFFFF80F1, "lh sign");
        checkOut(10'h302, `MEM_LHU, 32'h000080F1, "lhu");
        checkOut(10'h301, `MEM_LB,  32'hFFFFFFF2, "lb byte 1");
        store(10'h305, `MEM_SB, 32'hAABBCCDD);
        checkOut(10'h304, `MEM_LW,  32'h0000DD00, "sb writes 1 byte");
        store(10'h306, `MEM_SH, 32'h11223344);
        checkOut(10'h304, `MEM_LW,  32'h3344DD00, "sh writes 2 bytes");
        @(negedge clk);
        addr = 10'h304; funct3 = `MEM_SW; dataIn = 32'hFFFFFFFF;
        @(negedge clk);
        checkOut(10'h304, `MEM_LW,  32'h3344DD00, "no write w/o memWrite");
        memRead = 0;
        checkOut(10'h304, `MEM_LW,  32'h00000000, "memRead=0 -> 0");
        if (errors == 0) $display("PASS UnifiedMem_tb");
        else             $display("FAIL UnifiedMem_tb: %0d errors", errors);
        $finish;
    end

endmodule
