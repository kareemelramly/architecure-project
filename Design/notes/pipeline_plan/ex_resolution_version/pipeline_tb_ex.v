/*******************************************************************************
 * Module: pipeline_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Self-checking testbench for the pipelined femtoRV32.
 *              Two pipelines run side by side on the same clock:
 *                dut   : BP_ENABLE = 1 (BTB + 2-bit BHT)
 *                dutNo : BP_ENABLE = 0 (always predict not taken)
 *              Both must end with identical architectural state. The
 *              single-cycle datapath is used as the golden reference for the
 *              full-program regression (the same program, ported to the
 *              unified memory map: data at 0x200, load/store imm + 512).
 *
 * Change history:
 *   11/13/26 - Directed hazard tests, predictor tests, regression vs datapath
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

// Counts events at the posedge (pre-edge values, one count per C0/C1 slot)
module PerfMonitor(
    input clk,
    input rst,
    input advance,
    input idValid,
    input stall,
    input redirect,
    input halt,
    output reg [31:0] cycles,
    output reg [31:0] retired,
    output reg [31:0] mispred,
    output reg [31:0] stalls
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycles  <= 32'd0;
            retired <= 32'd0;
            mispred <= 32'd0;
            stalls  <= 32'd0;
        end else if (!halt) begin
            cycles <= cycles + 32'd1;
            if (advance && idValid && !stall && !redirect) begin
                retired <= retired + 32'd1;
            end
            if (advance && redirect) begin
                mispred <= mispred + 32'd1;
            end
            if (advance && stall) begin
                stalls <= stalls + 32'd1;
            end
        end
    end

endmodule

module pipeline_tb;

    reg clk;
    reg rst;
    reg rstRef;

    integer errors;
    integer checks;
    integer progPtr;
    integer t;
    integer timeouts;

    // Device under test (predictor on), twin (predictor off), golden reference
    pipeline #(.BP_ENABLE(1)) dut(.clk(clk), .reset(rst));
    pipeline #(.BP_ENABLE(0)) dutNo(.clk(clk), .reset(rst));
    datapath refCpu(.clk(clk), .reset(rstRef));

    wire [31:0] onCycles, onRetired, onMispred, onStalls;
    wire [31:0] offCycles, offRetired, offMispred, offStalls;

    PerfMonitor monOn(
        .clk(clk), .rst(rst),
        .advance(dut.advance), .idValid(dut.idValid), .stall(dut.stall),
        .redirect(dut.redirect), .halt(dut.haltLatch),
        .cycles(onCycles), .retired(onRetired),
        .mispred(onMispred), .stalls(onStalls)
    );

    PerfMonitor monOff(
        .clk(clk), .rst(rst),
        .advance(dutNo.advance), .idValid(dutNo.idValid), .stall(dutNo.stall),
        .redirect(dutNo.redirect), .halt(dutNo.haltLatch),
        .cycles(offCycles), .retired(offRetired),
        .mispred(offMispred), .stalls(offStalls)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Structural monitors (run for the whole simulation)
    //   1. memory is never written during C0 (the fetch phase)
    //   2. the PC only changes at the end of C1
    // ------------------------------------------------------------------
    integer portViol;
    integer pcViol;
    reg        advSample;
    reg [31:0] pcSample;

    always @(posedge clk) begin
        advSample <= dut.advance;
        pcSample  <= dut.pcValue;
    end

    always @(negedge clk) begin
        if (dut.isFetch && dut.memWriteEn) portViol = portViol + 1;
        if (!rst && !advSample && (dut.pcValue !== pcSample) && (pcSample !== 32'bx)) begin
            pcViol = pcViol + 1;
        end
    end

    // ------------------------------------------------------------------
    // Check helpers
    // ------------------------------------------------------------------
    task check(input cond, input [8*64-1:0] name);
        begin
            checks = checks + 1;
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    function [31:0] rgOn(input integer n);
        begin
            rgOn = (n == 0) ? 32'd0 : dut.RegisterFile.d_reg[n];
        end
    endfunction

    function [31:0] rgOff(input integer n);
        begin
            rgOff = (n == 0) ? 32'd0 : dutNo.RegisterFile.d_reg[n];
        end
    endfunction

    function [31:0] rgRef(input integer n);
        begin
            rgRef = (n == 0) ? 32'd0 : refCpu.RegisterFile.d_reg[n];
        end
    endfunction

    function [31:0] memWordOn(input integer a);
        begin
            memWordOn = {dut.memory.mem[a+3], dut.memory.mem[a+2],
                         dut.memory.mem[a+1], dut.memory.mem[a]};
        end
    endfunction

    function [31:0] memWordOff(input integer a);
        begin
            memWordOff = {dutNo.memory.mem[a+3], dutNo.memory.mem[a+2],
                          dutNo.memory.mem[a+1], dutNo.memory.mem[a]};
        end
    endfunction

    task expectReg(input integer n, input [31:0] val, input [8*40-1:0] name);
        begin
            checks = checks + 1;
            if (rgOn(n) === val && rgOff(n) === val) begin
                $display("[PASS] %0s: x%0d = 0x%08h", name, n, val);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s: x%0d on=0x%08h off=0x%08h expected=0x%08h",
                         name, n, rgOn(n), rgOff(n), val);
            end
        end
    endtask

    task expectMem(input integer a, input [31:0] val, input [8*40-1:0] name);
        begin
            checks = checks + 1;
            if (memWordOn(a) === val && memWordOff(a) === val) begin
                $display("[PASS] %0s: mem[0x%03h] = 0x%08h", name, a, val);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s: mem[0x%03h] on=0x%08h off=0x%08h expected=0x%08h",
                         name, a, memWordOn(a), memWordOff(a), val);
            end
        end
    endtask

    task expectCount(input [31:0] got, input [31:0] want, input [8*40-1:0] name);
        begin
            checks = checks + 1;
            if (got === want) begin
                $display("[PASS] %0s = %0d", name, got);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s = %0d, expected %0d", name, got, want);
            end
        end
    endtask

    // Predictor on and off must end in the same architectural state
    task expectTwinsEqual;
        integer n;
        integer bad;
        begin
            bad = 0;
            for (n = 1; n < 32; n = n + 1) begin
                if (rgOn(n) !== rgOff(n)) begin
                    bad = bad + 1;
                    $display("       twin mismatch x%0d: on=0x%08h off=0x%08h",
                             n, rgOn(n), rgOff(n));
                end
            end
            check(bad == 0, "predictor on/off end with identical regs");
        end
    endtask

    // ------------------------------------------------------------------
    // Tiny assembler
    // ------------------------------------------------------------------
    function [31:0] encR(input [6:0] f7, input integer rs2, input integer rs1,
                         input [2:0] f3, input integer rd);
        begin
            encR = {f7, rs2[4:0], rs1[4:0], f3, rd[4:0], 7'b0110011};
        end
    endfunction

    function [31:0] encI(input integer imm, input integer rs1,
                         input [2:0] f3, input integer rd, input [6:0] op);
        begin
            encI = {imm[11:0], rs1[4:0], f3, rd[4:0], op};
        end
    endfunction

    function [31:0] encS(input integer imm, input integer rs2,
                         input integer rs1, input [2:0] f3);
        begin
            encS = {imm[11:5], rs2[4:0], rs1[4:0], f3, imm[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] encB(input integer off, input integer rs2,
                         input integer rs1, input [2:0] f3);
        begin
            encB = {off[12], off[10:5], rs2[4:0], rs1[4:0], f3,
                    off[4:1], off[11], 7'b1100011};
        end
    endfunction

    function [31:0] ADD (input integer rd, input integer rs1, input integer rs2);
        begin ADD = encR(7'b0000000, rs2, rs1, 3'b000, rd); end
    endfunction
    function [31:0] AND (input integer rd, input integer rs1, input integer rs2);
        begin AND = encR(7'b0000000, rs2, rs1, 3'b111, rd); end
    endfunction
    function [31:0] ADDI(input integer rd, input integer rs1, input integer imm);
        begin ADDI = encI(imm, rs1, 3'b000, rd, 7'b0010011); end
    endfunction
    function [31:0] NOP(input integer unused);
        begin NOP = encI(0, 0, 3'b000, 0, 7'b0010011); end
    endfunction
    function [31:0] LW (input integer rd, input integer imm, input integer rs1);
        begin LW = encI(imm, rs1, 3'b010, rd, 7'b0000011); end
    endfunction
    function [31:0] LB (input integer rd, input integer imm, input integer rs1);
        begin LB = encI(imm, rs1, 3'b000, rd, 7'b0000011); end
    endfunction
    function [31:0] LH (input integer rd, input integer imm, input integer rs1);
        begin LH = encI(imm, rs1, 3'b001, rd, 7'b0000011); end
    endfunction
    function [31:0] LBU(input integer rd, input integer imm, input integer rs1);
        begin LBU = encI(imm, rs1, 3'b100, rd, 7'b0000011); end
    endfunction
    function [31:0] LHU(input integer rd, input integer imm, input integer rs1);
        begin LHU = encI(imm, rs1, 3'b101, rd, 7'b0000011); end
    endfunction
    function [31:0] SW (input integer rs2, input integer imm, input integer rs1);
        begin SW = encS(imm, rs2, rs1, 3'b010); end
    endfunction
    function [31:0] SH (input integer rs2, input integer imm, input integer rs1);
        begin SH = encS(imm, rs2, rs1, 3'b001); end
    endfunction
    function [31:0] SB (input integer rs2, input integer imm, input integer rs1);
        begin SB = encS(imm, rs2, rs1, 3'b000); end
    endfunction
    function [31:0] BEQ(input integer rs1, input integer rs2, input integer off);
        begin BEQ = encB(off, rs2, rs1, 3'b000); end
    endfunction
    function [31:0] BNE(input integer rs1, input integer rs2, input integer off);
        begin BNE = encB(off, rs2, rs1, 3'b001); end
    endfunction
    function [31:0] JAL(input integer rd, input integer off);
        begin
            JAL = {off[20], off[10:1], off[11], off[19:12], rd[4:0], 7'b1101111};
        end
    endfunction
    function [31:0] JALR(input integer rd, input integer rs1, input integer imm);
        begin JALR = encI(imm, rs1, 3'b000, rd, 7'b1100111); end
    endfunction
    function [31:0] LUI(input integer rd, input integer imm20);
        begin LUI = {imm20[19:0], rd[4:0], 7'b0110111}; end
    endfunction

    localparam [31:0] ECALL = 32'h00000073;

    // ------------------------------------------------------------------
    // Memory loading (both pipelines get the same image)
    // ------------------------------------------------------------------
    task wr32(input integer a, input [31:0] w);
        begin
            dut.memory.mem[a]     = w[7:0];
            dut.memory.mem[a+1]   = w[15:8];
            dut.memory.mem[a+2]   = w[23:16];
            dut.memory.mem[a+3]   = w[31:24];
            dutNo.memory.mem[a]   = w[7:0];
            dutNo.memory.mem[a+1] = w[15:8];
            dutNo.memory.mem[a+2] = w[23:16];
            dutNo.memory.mem[a+3] = w[31:24];
        end
    endtask

    task clearMem;
        integer i;
        begin
            for (i = 0; i < 1024; i = i + 1) begin
                dut.memory.mem[i]   = 8'd0;
                dutNo.memory.mem[i] = 8'd0;
            end
        end
    endtask

    // Standard data section (same values as the original DataMem)
    task stdData;
        begin
            wr32(10'h200, 32'd10);
            wr32(10'h204, 32'd20);
            wr32(10'h208, 32'hFFFFFFFB);
            wr32(10'h214, 32'h7C8AF1B2);
        end
    endtask

    task startProg;
        begin
            clearMem;
            stdData;
            progPtr = 0;
        end
    endtask

    task emit(input [31:0] w);
        begin
            wr32(progPtr, w);
            progPtr = progPtr + 4;
        end
    endtask

    // Reset both pipelines, run until both have latched ECALL, then drain
    task runProg;
        begin
            rst = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            t = 0;
            while (!(dut.haltLatch === 1'b1 && dutNo.haltLatch === 1'b1) && t < 20000) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= 20000) begin
                timeouts = timeouts + 1;
                $display("[FAIL] timeout waiting for halt");
                errors = errors + 1;
            end
            repeat (16) @(posedge clk);
            @(negedge clk);
        end
    endtask

    task report(input [8*30-1:0] name);
        begin
            $display("       %0s: BP on : cycles=%0d retired=%0d CPI=%0f mispredicts=%0d stalls=%0d",
                     name, onCycles, onRetired,
                     (onRetired == 0) ? 0.0 : (onCycles * 1.0) / onRetired,
                     onMispred, onStalls);
            $display("       %0s: BP off: cycles=%0d retired=%0d CPI=%0f mispredicts=%0d stalls=%0d",
                     name, offCycles, offRetired,
                     (offRetired == 0) ? 0.0 : (offCycles * 1.0) / offRetired,
                     offMispred, offStalls);
        end
    endtask

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    integer i;

    task test1_forwarding;
        begin
            $display("\n--- Test 1: EX/MEM and MEM/WB forwarding, regfile distance 3, x0 guard ---");
            startProg;
            emit(ADDI(1, 0, 5));
            emit(ADDI(2, 0, 7));
            emit(ADD(3, 1, 2));           // x1 from MEM/WB, x2 from EX/MEM
            emit(ADD(5, 3, 2));           // x3 from EX/MEM
            emit(ADD(6, 5, 3));           // x5 EX/MEM, x3 MEM/WB
            emit(ADDI(8, 0, 3));
            emit(NOP(0));
            emit(NOP(0));
            emit(ADD(9, 8, 8));           // distance 3: regfile written in C0
            emit(ADDI(11, 0, 1));
            emit(ADDI(11, 11, 1));
            emit(ADDI(11, 11, 1));
            emit(ADD(10, 11, 11));        // EX/MEM must win over MEM/WB
            emit(ADDI(0, 0, 99));         // write to x0 must not be forwarded
            emit(ADD(12, 0, 1));
            emit(ECALL);
            runProg;
            expectReg(3, 32'd12, "add fwd both operands");
            expectReg(5, 32'd19, "add fwd from EX/MEM");
            expectReg(6, 32'd31, "add fwd EX/MEM + MEM/WB");
            expectReg(9, 32'd6, "distance-3 regfile path");
            expectReg(11, 32'd3, "chained addi forward");
            expectReg(10, 32'd6, "EX/MEM priority over MEM/WB");
            expectReg(12, 32'd5, "x0 never forwarded");
            expectCount(onStalls, 0, "no stalls without loads");
            expectTwinsEqual;
            report("forwarding");
        end
    endtask

    task test2_loaduse;
        begin
            $display("\n--- Test 2: load-use hazard (one bubble) ---");
            startProg;
            emit(ADDI(1, 0, 12));
            emit(LW(6, 512, 0));          // x6 = 10
            emit(AND(7, 6, 1));           // load-use: stall, x7 = 10 & 12 = 8
            emit(ADD(8, 7, 7));           // x7 from EX/MEM, no stall: 16
            emit(LW(4, 516, 0));          // x4 = 20
            emit(NOP(0));
            emit(ADD(5, 4, 4));           // distance 2: no stall: 40
            emit(ECALL);
            runProg;
            expectReg(6, 32'd10, "lw result");
            expectReg(7, 32'd8, "and after load-use");
            expectReg(8, 32'd16, "add after and");
            expectReg(5, 32'd40, "load distance 2, no stall");
            expectCount(onStalls, 1, "exactly one load-use stall");
            expectCount(offStalls, 1, "stall count independent of BP");
            expectTwinsEqual;
            report("load-use");
        end
    endtask

    task test3_store;
        begin
            $display("\n--- Test 3: store data forwarding and store/load ordering ---");
            startProg;
            emit(LW(5, 512, 0));          // x5 = 10
            emit(SW(5, 520, 0));          // store data from a load (stall + MEM/WB)
            emit(ADDI(4, 0, 77));
            emit(SW(4, 524, 0));          // store data from EX/MEM, imm must survive
            emit(LW(6, 524, 0));          // x6 = 77
            emit(SW(4, 528, 0));
            emit(LW(7, 528, 0));          // store then load back to back
            emit(ECALL);
            runProg;
            expectMem(10'h208, 32'd10, "sw of loaded value");
            expectMem(10'h20C, 32'd77, "sw of forwarded ALU value");
            expectReg(6, 32'd77, "lw after sw");
            expectReg(7, 32'd77, "sw then lw adjacent");
            expectTwinsEqual;
        end
    endtask

    task test4_jal_lui;
        begin
            $display("\n--- Test 4: LUI / JAL results forwarded (exResult) ---");
            startProg;
            emit(LUI(1, 20'h12345));      //  0
            emit(ADD(2, 1, 1));           //  4: LUI result forwarded
            emit(JAL(3, 8));              //  8: x3 = 12, jump to 16
            emit(ADDI(9, 0, 99));         // 12: skipped
            emit(ADD(4, 3, 3));           // 16: JAL link forwarded: 24
            emit(ECALL);                  // 20
            runProg;
            expectReg(1, 32'h12345000, "lui");
            expectReg(2, 32'h2468A000, "lui forwarded");
            expectReg(3, 32'd12, "jal link");
            expectReg(4, 32'd24, "jal link forwarded");
            expectReg(9, 32'd0, "jal skipped instruction");
            expectTwinsEqual;
        end
    endtask

    task test5_jalr;
        begin
            $display("\n--- Test 5: JALR with forwarded base ---");
            startProg;
            emit(ADDI(1, 0, 16));         //  0
            emit(JALR(2, 1, 0));          //  4: x2 = 8, jump to 16
            emit(ADDI(5, 0, 1));          //  8: skipped
            emit(ADDI(5, 0, 2));          // 12: skipped
            emit(ADDI(6, 0, 3));          // 16
            emit(ECALL);                  // 20
            runProg;
            expectReg(2, 32'd8, "jalr link");
            expectReg(5, 32'd0, "jalr skipped instructions");
            expectReg(6, 32'd3, "jalr target executed");
            expectTwinsEqual;
        end
    endtask

    task test6_loop_bne;
        begin
            $display("\n--- Test 6: bne loop (taken 5 times), predictor learns ---");
            startProg;
            emit(ADDI(1, 0, 0));          //  0
            emit(ADDI(2, 0, 6));          //  4
            emit(ADDI(1, 1, 3));          //  8
            emit(ADDI(2, 2, -1));         // 12
            emit(BNE(2, 0, -8));          // 16: back to 8
            emit(ECALL);                  // 20
            runProg;
            expectReg(1, 32'd18, "loop accumulator");
            expectReg(2, 32'd0, "loop counter");
            expectCount(onRetired, 21, "retired (predictor on)");
            expectCount(offRetired, 21, "retired (predictor off)");
            expectCount(onMispred, 2, "BP on: first taken + exit");
            expectCount(offMispred, 5, "BP off: every taken branch");
            check(onCycles < offCycles, "predictor reduces total cycles");
            expectTwinsEqual;
            report("bne loop");
        end
    endtask

    task test7_loop_jal;
        begin
            $display("\n--- Test 7: jal-back loop with beq exit ---");
            startProg;
            emit(ADDI(1, 0, 0));          //  0
            emit(ADDI(2, 0, 4));          //  4
            emit(BEQ(2, 0, 16));          //  8: exit to 24 when x2 == 0
            emit(ADDI(1, 1, 5));          // 12
            emit(ADDI(2, 2, -1));         // 16
            emit(JAL(0, -12));            // 20: back to 8
            emit(ECALL);                  // 24
            runProg;
            expectReg(1, 32'd20, "jal loop accumulator");
            expectReg(2, 32'd0, "jal loop counter");
            expectCount(onRetired, 20, "retired (predictor on)");
            expectCount(onMispred, 2, "BP on: first jal + final beq");
            expectCount(offMispred, 5, "BP off: 4 jal + final beq");
            expectTwinsEqual;
            report("jal loop");
        end
    endtask

    task test8_wrong_path_halt;
        begin
            $display("\n--- Test 8: ECALL on a mispredicted path must not halt ---");
            startProg;
            emit(ADDI(1, 0, 1));          //  0
            emit(BEQ(1, 1, 12));          //  4: taken, to 16
            emit(ECALL);                  //  8: wrong path
            emit(ADDI(5, 0, 111));        // 12: wrong path
            emit(ADDI(6, 0, 222));        // 16
            emit(ECALL);                  // 20
            runProg;
            expectReg(5, 32'd0, "wrong-path addi squashed");
            expectReg(6, 32'd222, "correct path continued after wrong ECALL");
            expectCount(onMispred, 1, "one mispredict (cold branch)");
            expectTwinsEqual;
        end
    endtask

    task test9_subword;
        begin
            $display("\n--- Test 9: sub-word loads and stores through the unified memory ---");
            startProg;
            emit(LB(1, 520, 0));          // 0xFB sign extended
            emit(LBU(2, 520, 0));
            emit(LH(3, 522, 0));          // 0xFFFF sign extended
            emit(LHU(4, 522, 0));
            emit(ADDI(5, 0, 127));
            emit(SB(5, 513, 0));          // byte 1 of 10 -> 0x00007F0A
            emit(LW(6, 512, 0));
            emit(ADDI(7, 0, -2));
            emit(SH(7, 514, 0));          // upper half -> 0xFFFE7F0A
            emit(LW(8, 512, 0));
            emit(LW(9, 532, 0));          // 0x7C8AF1B2 data word
            emit(ECALL);
            runProg;
            expectReg(1, 32'hFFFFFFFB, "lb sign extend");
            expectReg(2, 32'h000000FB, "lbu zero extend");
            expectReg(3, 32'hFFFFFFFF, "lh sign extend");
            expectReg(4, 32'h0000FFFF, "lhu zero extend");
            expectReg(6, 32'h00007F0A, "sb then lw");
            expectReg(8, 32'hFFFE7F0A, "sh then lw");
            expectReg(9, 32'h7C8AF1B2, "data word");
            expectTwinsEqual;
        end
    endtask

    task test10_cpi;
        begin
            $display("\n--- Test 10: straight-line code issues one instruction every 2 cycles ---");
            startProg;
            for (i = 0; i < 40; i = i + 1) begin
                emit(ADDI(1 + (i % 8), 0, i));
            end
            emit(ECALL);
            runProg;
            // ECALL (index 40) is in ID in slot 41; halt latches at the end of it
            expectCount(onCycles, 84, "cycles = 2 * (N + 2)");
            expectCount(offCycles, 84, "cycles (predictor off)");
            expectCount(onRetired, 41, "retired = N + ECALL");
            expectCount(onStalls, 0, "no stalls");
            expectCount(onMispred, 0, "no mispredicts");
            report("straight line");
        end
    endtask

    // Full regression: golden single-cycle datapath vs both pipelines
    task test11_regression;
        integer k;
        integer bad;
        integer imm;
        reg [31:0] w;
        reg [31:0] refWord;
        begin
            $display("\n--- Test 11: full program regression vs single-cycle datapath ---");
            clearMem;
            // Port: loads/stores use x0 as base, so imm + 512 moves them into
            // the data region; PC-relative code and the jalr-through-x0 target
            // (inside the instruction region) are unchanged.
            for (k = 0; k < 128; k = k + 1) begin
                w = refCpu.InstructionMemory.mem[k];
                if (w[6:2] == 5'b00000 && w[19:15] == 5'd0) begin
                    imm = w[31:20] + 12'd512;
                    w = {imm[11:0], w[19:0]};
                end else if (w[6:2] == 5'b01000 && w[19:15] == 5'd0) begin
                    imm = {w[31:25], w[11:7]} + 12'd512;
                    w = {imm[11:5], w[24:12], imm[4:0], w[6:0]};
                end
                wr32(4 * k, w);
            end
            for (k = 0; k < 64; k = k + 1) begin
                wr32(10'h200 + 4 * k, refCpu.DataMemory.mem[k]);
            end

            // Start the reference together with both pipelines
            rst = 1'b1;
            rstRef = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            rstRef = 1'b0;
            t = 0;
            while (!(dut.haltLatch === 1'b1 && dutNo.haltLatch === 1'b1 &&
                     refCpu.halt === 1'b1) && t < 20000) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= 20000) begin
                timeouts = timeouts + 1;
                errors = errors + 1;
                $display("[FAIL] regression timeout");
            end
            repeat (16) @(posedge clk);
            @(negedge clk);

            bad = 0;
            for (k = 1; k < 32; k = k + 1) begin
                if (rgOn(k) !== rgRef(k)) begin
                    bad = bad + 1;
                    $display("       BP on  x%0d: pipe=0x%08h ref=0x%08h", k, rgOn(k), rgRef(k));
                end
            end
            check(bad == 0, "BP on : all 31 registers match single-cycle");

            bad = 0;
            for (k = 1; k < 32; k = k + 1) begin
                if (rgOff(k) !== rgRef(k)) begin
                    bad = bad + 1;
                    $display("       BP off x%0d: pipe=0x%08h ref=0x%08h", k, rgOff(k), rgRef(k));
                end
            end
            check(bad == 0, "BP off: all 31 registers match single-cycle");

            bad = 0;
            for (k = 0; k < 64; k = k + 1) begin
                refWord = refCpu.DataMemory.mem[k];
                if (memWordOn(10'h200 + 4 * k) !== refWord ||
                    memWordOff(10'h200 + 4 * k) !== refWord) begin
                    bad = bad + 1;
                    $display("       data word %0d: on=0x%08h off=0x%08h ref=0x%08h", k,
                             memWordOn(10'h200 + 4 * k), memWordOff(10'h200 + 4 * k), refWord);
                end
            end
            check(bad == 0, "data memory matches single-cycle (64 words)");
            report("full program");
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        errors   = 0;
        checks   = 0;
        timeouts = 0;
        portViol = 0;
        pcViol   = 0;
        rst      = 1'b1;
        rstRef   = 1'b1;   // reference stays in reset until the regression

        if ($test$plusargs("vcd")) begin
            $dumpfile("pipeline.vcd");
            $dumpvars(0, pipeline_tb);
        end

        #1;
        test1_forwarding;
        test2_loaduse;
        test3_store;
        test4_jal_lui;
        test5_jalr;
        test6_loop_bne;
        test7_loop_jal;
        test8_wrong_path_halt;
        test9_subword;
        test10_cpi;
        test11_regression;

        $display("\n--- Structural checks over the whole run ---");
        expectCount(portViol, 0, "memory writes during C0 (fetch)");
        expectCount(pcViol, 0, "PC changes outside end of C1");

        $display("\n=================================================");
        if (errors == 0) begin
            $display("ALL %0d CHECKS PASSED", checks);
        end else begin
            $display("%0d of %0d CHECKS FAILED", errors, checks);
        end
        $display("=================================================");
        $finish;
    end

endmodule
