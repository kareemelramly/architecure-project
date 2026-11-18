/*******************************************************************************
 * Module: pipeline_tb.v
 * Project: femtoRV32
 * Author: Mostafa Fayed, Kareem Elramly
 * Description: Self-checking testbench for pipeline.v. Runs one hex program
 *              (parameter PROG) and checks:
 *              1. Signature: x31 == 0 and x30 == 0xC0DE after EBREAK halts.
 *              2. Single memory port (every cycle): the memory is written
 *                 only in C1 and the fetch address is the PC in C0.
 *              3. Register file written only in C0 (WB), never in C1.
 *              4. After the halt, the PC never changes again.
 *              5. CHECK_TIMING = 1 (timing.hex): instruction k writes its
 *                 register in cycle 2k+4, i.e. 3 stages x 2 cycles, one
 *                 instruction issued every 2 cycles.
 *              TRACE = 1 prints the pipeline state every cycle (used to
 *              draw the pipeline chart in the implementation guide).
 *              Prints one PASS / FAIL line. Run from Verilog/ with
 *              sh ../Testing/run_all.sh
 *
 * Change history:
 *   11/16/26 - created for MS3 (as programs_tb)
 *   11/18/26 - renamed after the module under test, hazard monitors,
 *              6-cycle timing check
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module pipeline_tb #(
    parameter PROG         = "D:/New folder/architecure-project/MS3_3stage_submission/Testing/programs/all_instr.hex",    parameter ADDR_BITS    = 10,
    parameter CHECK_TIMING = 0,
    parameter MAX_CYCLES   = 40000,
    parameter TRACE        = 0       // 1: print one line per cycle
);

    reg         clk;
    reg         rst;
    reg  [4:0]  sel;
    wire [31:0] rdata;
    wire        halt;

    integer     cycle;
    integer     errors;
    integer     writes;
    integer     haltCycle;
    reg  [31:0] fails;
    reg  [31:0] sig;
    reg  [31:0] haltPC;

    pipeline #(
        .PROGRAM_FILE(PROG),
        .ADDR_BITS(ADDR_BITS)
    ) dut(
        .clk(clk),
        .rst(rst),
        .dbgRegSel(sel),
        .dbgRegData(rdata),
        .dbgPC(),
        .dbgInst(),
        .dbgAluResult(),
        .dbgMemAddr(),
        .dbgMemOut(),
        .dbgWbData(),
        .dbgStoreData(),
        .dbgFlags(),
        .dbgHalt(halt)
    );

    always #5 clk = ~clk;

    // Sample every cycle just before the rising edge (guideline: sample
    // before the edge, drive after it). cycle 0 = first C0 after reset.
    always @(negedge clk) begin
        if (!rst) begin
            if (TRACE) begin
                $display("TRACE %0d %0d %h %h %h %h %h %b %b %b %b %b %b",
                         cycle, dut.phase, dut.pcValue, dut.IF_ID_PC,
                         dut.IF_ID_Inst, dut.ID_EX_PC, dut.ID_EX_Inst,
                         dut.forwardA, dut.forwardB, dut.pcSrc,
                         dut.regWriteEn, dut.memWriteEn, halt);
            end
            if (dut.memWriteEn && dut.isC0) begin
                errors = errors + 1;
                $display("ERROR cycle %0d: memory write during C0 (fetch)",
                         cycle);
            end
            if (dut.isC0 &&
                (dut.memAddr !== dut.pcValue[ADDR_BITS-1:0])) begin
                errors = errors + 1;
                $display("ERROR cycle %0d: C0 address is not the PC", cycle);
            end
            if (dut.regWriteEn && dut.isC1) begin
                errors = errors + 1;
                $display("ERROR cycle %0d: register write during C1", cycle);
            end
            if (dut.regWriteEn && (dut.MEM_WB_Rd != 5'd0)) begin
                // timing.hex: instruction k (k = 0..7) writes x(k+1)
                if (CHECK_TIMING && (dut.MEM_WB_Rd <= 5'd8) &&
                    (cycle != 2 * (dut.MEM_WB_Rd - 1) + 4)) begin
                    errors = errors + 1;
                    $display("ERROR: x%0d written in cycle %0d, expected %0d",
                             dut.MEM_WB_Rd, cycle,
                             2 * (dut.MEM_WB_Rd - 1) + 4);
                end
                writes = writes + 1;
            end
            if (halt && (dut.pcValue !== haltPC) && (haltPC !== 32'hx)) begin
                errors = errors + 1;
                $display("ERROR cycle %0d: PC moved after EBREAK", cycle);
            end
            if (halt && (haltPC === 32'hx)) begin
                haltPC    = dut.pcValue;
                haltCycle = cycle;
            end
            cycle = cycle + 1;
        end
    end

    initial begin
        clk    = 1'b0;
        rst    = 1'b1;
        sel    = 5'd31;
        cycle  = 0;
        errors = 0;
        writes = 0;
        haltCycle = 0;
        haltPC = 32'hx;
        repeat (3) @(posedge clk);
        #1 rst = 1'b0;
        while (!halt && (cycle < MAX_CYCLES)) begin
            @(posedge clk);
        end
        repeat (8) @(posedge clk);    // older instructions drain to WB
        @(negedge clk);
        sel = 5'd31;
        #1 fails = rdata;
        sel = 5'd30;
        #1 sig = rdata;
        if (!halt) begin
            $display("FAIL %0s: no EBREAK within %0d cycles", PROG, cycle);
        end else if (errors != 0) begin
            $display("FAIL %0s: %0d monitor errors", PROG, errors);
        end else if (fails !== 32'd0) begin
            $display("FAIL %0s: x31 = %0d (failed check)", PROG, fails);
        end else if (sig !== 32'hC0DE) begin
            $display("FAIL %0s: x30 = %h", PROG, sig);
        end else if (CHECK_TIMING && (haltCycle != 2 * 10 + 2)) begin
            // EBREAK is instruction 10: IF 20, ID 21, halted from cycle 22
            $display("FAIL %0s: halted in cycle %0d, expected 22",
                     PROG, haltCycle);
        end else begin
            $display("PASS %0s: halted in cycle %0d, %0d register writes",
                     PROG, haltCycle, writes);
        end
        $finish;
    end

endmodule

`default_nettype wire
