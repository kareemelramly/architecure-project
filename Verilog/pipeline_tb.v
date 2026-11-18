/*******************************************************************************
 * Module: pipeline_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Mohamed AboElfotouh
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
 *   11/13/26 - Bonus 4: ID-stage branch tests (all branch types, every
 *              forwarding distance, JALR, EBREAK, back-to-back branches)
 *   11/16/26 - ECALL is a NOP: every program now ends with EBREAK; Test 23
 *              checks ECALL/FENCE/FENCE.TSO/PAUSE as NOPs; Test 22 asserts 0 stalls
 *   11/14/26 - Test 20: 2-bit predictor state walk (SNT -> ST) with a BHT
 *              monitor, nested loops. Test 21: stale-value hazard cases
 *              (add/lw directly before a branch) over 3 passes (cold + warm
 *              predictor). Test 22: x0 write must not feed a branch.
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
            if (advance && idValid && !stall) begin
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
    pipeline #(.BP_ENABLE(1)) dut(
        .clk(clk), .reset(rst), .dbgRegSel(5'd0),
        .dbgRegData(), .dbgPC(), .dbgNextPC(), .dbgInst(), .dbgAluResult(),
        .dbgMemAddr(), .dbgMemOut(), .dbgWbData(), .dbgStoreData(),
        .dbgCtrlFlags(), .dbgPipeFlags(), .dbgHalt()
    );
    pipeline #(.BP_ENABLE(0)) dutNo(
        .clk(clk), .reset(rst), .dbgRegSel(5'd0),
        .dbgRegData(), .dbgPC(), .dbgNextPC(), .dbgInst(), .dbgAluResult(),
        .dbgMemAddr(), .dbgMemOut(), .dbgWbData(), .dbgStoreData(),
        .dbgCtrlFlags(), .dbgPipeFlags(), .dbgHalt()
    );
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
    // Predictor update log (BP-on pipeline only).
    // One entry per branch/JAL leaving ID: its PC, whether it was a
    // mispredict, and the BHT counter AFTER the update (read 1 ns after the
    // edge). Tests clear logCnt before running a program.
    // ------------------------------------------------------------------
    integer    logCnt;
    reg [31:0] logPC    [0:255];
    reg [1:0]  logState [0:255];
    reg        logMis   [0:255];
    reg        logTaken [0:255];
    reg [31:0] lgPC;
    reg        lgMis;
    reg        lgTaken;
    reg [3:0]  lgIdx;

    always @(posedge clk) begin
        if (!rst && dut.bpUpdateEn === 1'b1) begin
            lgPC    = dut.IF_ID_PC;
            lgMis   = dut.redirect;
            lgTaken = dut.idActualTaken;
            lgIdx   = dut.IF_ID_PC[5:2];
            #1;
            if (logCnt < 256) begin
                logPC[logCnt]    = lgPC;
                logState[logCnt] = dut.predictor.bht[lgIdx];
                logMis[logCnt]   = lgMis;
                logTaken[logCnt] = lgTaken;
                logCnt = logCnt + 1;
            end
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

    localparam [31:0] ECALL  = 32'h00000073;   // executes as a NOP
    localparam [31:0] EBREAK = 32'h00100073;   // the only halting instruction
    localparam [31:0] FENCE  = 32'h0FF0000F;   // NOP
    localparam [31:0] FENCET = 32'h8330000F;   // FENCE.TSO, NOP
    localparam [31:0] PAUSE  = 32'h0100000F;   // NOP

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

    // Reset both pipelines, run until both have latched EBREAK, then drain
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
            emit(EBREAK);
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
            emit(EBREAK);
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
            emit(EBREAK);
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
            emit(EBREAK);                  // 20
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
            emit(EBREAK);                  // 20
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
            emit(EBREAK);                  // 20
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
            emit(EBREAK);                  // 24
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
            $display("\n--- Test 8: EBREAK on a mispredicted path must not halt ---");
            startProg;
            emit(ADDI(1, 0, 1));          //  0
            emit(BEQ(1, 1, 12));          //  4: taken, to 16
            emit(EBREAK);                  //  8: wrong path
            emit(ADDI(5, 0, 111));        // 12: wrong path
            emit(ADDI(6, 0, 222));        // 16
            emit(EBREAK);                  // 20
            runProg;
            expectReg(5, 32'd0, "wrong-path addi squashed");
            expectReg(6, 32'd222, "correct path continued after wrong EBREAK");
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
            emit(EBREAK);
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
            emit(EBREAK);
            runProg;
            // EBREAK (index 40) is in ID in slot 41; halt latches at the end of it
            expectCount(onCycles, 84, "cycles = 2 * (N + 2)");
            expectCount(offCycles, 84, "cycles (predictor off)");
            expectCount(onRetired, 41, "retired = N + EBREAK");
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


    task test12_id_branch_hazards;
        begin
            $display("\n--- Test 12: ID-stage branch hazards (Bonus 4) ---");
            // (a) ALU result right before a branch: 1 stall, then EX/MEM forward
            startProg;
            emit(ADDI(1, 0, 3));          //  0
            emit(ADDI(2, 0, 3));          //  4
            emit(BEQ(1, 2, 8));           //  8: x2 in EX -> stall, taken to 16
            emit(ADDI(9, 0, 99));         // 12: skipped
            emit(ADDI(10, 0, 1));         // 16
            emit(EBREAK);
            runProg;
            expectReg(9, 32'd0, "ALU-use branch taken, skip");
            expectReg(10, 32'd1, "ALU-use branch target");
            expectCount(onStalls, 1, "ALU->branch: 1 stall");
            // (b) one instruction gap: forwarded from EX/MEM, no stall
            startProg;
            emit(ADDI(1, 0, 3));
            emit(ADDI(2, 0, 3));
            emit(NOP(0));
            emit(BEQ(1, 2, 8));
            emit(ADDI(9, 0, 99));
            emit(ADDI(10, 0, 1));
            emit(EBREAK);
            runProg;
            expectReg(9, 32'd0, "EX/MEM-forwarded branch skip");
            expectCount(onStalls, 0, "ALU, gap, branch: 0 stalls");
            // (c) load right before a branch: 2 stalls
            startProg;
            emit(LW(1, 512, 0));          // x1 = 10
            emit(ADDI(2, 0, 10));
            emit(LW(3, 512, 0));          // x3 = 10
            emit(BEQ(3, 2, 8));           // load in EX, then in MEM
            emit(ADDI(9, 0, 99));
            emit(ADDI(10, 0, 1));
            emit(EBREAK);
            runProg;
            expectReg(9, 32'd0, "load->branch taken, skip");
            expectCount(onStalls, 2, "load->branch: 2 stalls");
            // (d) load, gap, branch: 1 stall
            startProg;
            emit(ADDI(2, 0, 10));
            emit(LW(3, 512, 0));
            emit(NOP(0));
            emit(BNE(3, 2, 8));           // not taken
            emit(ADDI(9, 0, 7));
            emit(EBREAK);
            runProg;
            expectReg(9, 32'd7, "load,gap,bne not taken");
            expectCount(onStalls, 1, "load, gap, branch: 1 stall");
            // (e) JALR base from ALU right before it: 1 stall
            startProg;
            emit(ADDI(1, 0, 16));         //  0
            emit(JALR(2, 1, 0));          //  4: stall, jump to 16
            emit(ADDI(5, 0, 1));          //  8
            emit(ADDI(5, 0, 2));          // 12
            emit(ADDI(6, 0, 3));          // 16
            emit(EBREAK);
            runProg;
            expectReg(5, 32'd0, "jalr ALU-use skip");
            expectReg(6, 32'd3, "jalr ALU-use target");
            expectCount(onStalls, 1, "ALU->jalr: 1 stall");
            expectTwinsEqual;
            // (f) mispredict penalty is 1 slot (2 cycles) when resolved in ID
            startProg;
            emit(BEQ(0, 0, 8));           //  0: cold, taken -> mispredict
            emit(ADDI(9, 0, 99));         //  4: squashed in IF
            emit(EBREAK);                  //  8
            runProg;
            expectReg(9, 32'd0, "squashed fall-through");
            expectCount(onMispred, 1, "one mispredict");
            expectCount(onCycles, 8, "cycles: 2 instr + 1 squash slot + fill");
        end
    endtask

    // ---- Branch kinds for the exhaustive suite ----
    // kind: 0 BEQ, 1 BNE, 2 BLT, 3 BGE, 4 BLTU, 5 BGEU
    function [31:0] brInst(input integer kind, input integer rs1, input integer rs2,
                           input integer off);
        begin
            case (kind)
                0: brInst = BEQ(rs1, rs2, off);
                1: brInst = BNE(rs1, rs2, off);
                2: brInst = encB(off, rs2, rs1, 3'b100);
                3: brInst = encB(off, rs2, rs1, 3'b101);
                4: brInst = encB(off, rs2, rs1, 3'b110);
                default: brInst = encB(off, rs2, rs1, 3'b111);
            endcase
        end
    endfunction

    function brTaken(input integer kind, input integer a, input integer b);
        reg [31:0] ua, ub;
        begin
            ua = a; ub = b;
            case (kind)
                0: brTaken = (ua == ub);
                1: brTaken = (ua != ub);
                2: brTaken = ($signed(ua) <  $signed(ub));
                3: brTaken = ($signed(ua) >= $signed(ub));
                4: brTaken = (ua <  ub);
                default: brTaken = (ua >= ub);
            endcase
        end
    endfunction

    // 6 branch kinds x 2 outcomes. Operands are produced by ADDIs placed
    // `gap` NOPs before the branch (gap 0 = stall, 1 = EX/MEM forward,
    // 2+ = MEM/WB forward or register file).
    task branchSuite(input integer gap);
        integer kind, c, j, a, b, idx;
        integer bad;
        begin
            startProg;
            idx = 0;
            for (kind = 0; kind < 6; kind = kind + 1) begin
                for (c = 0; c < 2; c = c + 1) begin
                    case (kind)
                        0: begin a = 5;  b = (c == 0) ? 5 : 6; end
                        1: begin a = 5;  b = (c == 0) ? 6 : 5; end
                        2: begin a = (c == 0) ? -1 : 1;  b = (c == 0) ? 1 : -1; end
                        3: begin a = (c == 0) ? 1 : -1;  b = (c == 0) ? -1 : 1; end
                        4: begin a = (c == 0) ? 1 : -1;  b = (c == 0) ? -1 : 1; end
                        default: begin a = (c == 0) ? -1 : 1; b = (c == 0) ? 1 : -1; end
                    endcase
                    emit(ADDI(1, 0, a));
                    emit(ADDI(2, 0, b));
                    for (j = 0; j < gap; j = j + 1) emit(NOP(0));
                    emit(brInst(kind, 1, 2, 8));      // skips the next instruction if taken
                    emit(ADDI(10 + idx, 0, 1));       // x(10+idx) = 1 only if NOT taken
                    idx = idx + 1;
                end
            end
            emit(EBREAK);
            runProg;
            bad = 0;
            idx = 0;
            for (kind = 0; kind < 6; kind = kind + 1) begin
                for (c = 0; c < 2; c = c + 1) begin
                    case (kind)
                        0: begin a = 5;  b = (c == 0) ? 5 : 6; end
                        1: begin a = 5;  b = (c == 0) ? 6 : 5; end
                        2: begin a = (c == 0) ? -1 : 1;  b = (c == 0) ? 1 : -1; end
                        3: begin a = (c == 0) ? 1 : -1;  b = (c == 0) ? -1 : 1; end
                        4: begin a = (c == 0) ? 1 : -1;  b = (c == 0) ? -1 : 1; end
                        default: begin a = (c == 0) ? -1 : 1; b = (c == 0) ? 1 : -1; end
                    endcase
                    if (rgOn(10 + idx) !== (brTaken(kind, a, b) ? 32'd0 : 32'd1) ||
                        rgOff(10 + idx) !== (brTaken(kind, a, b) ? 32'd0 : 32'd1)) begin
                        bad = bad + 1;
                        $display("       kind %0d case %0d: x%0d on=%0d off=%0d, expected %0d",
                                 kind, c, 10 + idx, rgOn(10 + idx), rgOff(10 + idx),
                                 brTaken(kind, a, b) ? 0 : 1);
                    end
                    idx = idx + 1;
                end
            end
            check(bad == 0, "all 6 branch kinds x taken/not-taken correct");
            expectTwinsEqual;
        end
    endtask

    task test13_branch_suite;
        begin
            $display("\n--- Test 13: every branch type, operand distance 0 / 1 / 2 / 3 ---");
            $display("       distance 0 (ALU result right before the branch)");
            branchSuite(0);
            expectCount(onStalls, 12, "gap 0: one stall per branch");
            $display("       distance 1 (EX/MEM forward)");
            branchSuite(1);
            expectCount(onStalls, 0, "gap 1: no stalls");
            $display("       distance 2 (MEM/WB or register file)");
            branchSuite(2);
            expectCount(onStalls, 0, "gap 2: no stalls");
            $display("       distance 3");
            branchSuite(3);
            expectCount(onStalls, 0, "gap 3: no stalls");
        end
    endtask

    task test14_jalr_load;
        begin
            $display("\n--- Test 14: JALR base comes from a load (2 stalls) ---");
            startProg;
            wr32(10'h220, 32'd24);        // jump target stored in data memory
            emit(LW(1, 544, 0));          //  0: x1 = 24
            emit(JALR(2, 1, 0));          //  4: load in EX then MEM -> 2 stalls
            emit(ADDI(5, 0, 1));          //  8: skipped
            emit(ADDI(5, 0, 2));          // 12: skipped
            emit(ADDI(7, 0, 5));          // 16: skipped
            emit(NOP(0));                 // 20: skipped
            emit(ADDI(6, 0, 3));          // 24
            emit(EBREAK);                  // 28
            runProg;
            expectReg(2, 32'd8, "jalr link");
            expectReg(5, 32'd0, "skipped instructions");
            expectReg(7, 32'd0, "skipped instruction 2");
            expectReg(6, 32'd3, "jalr target executed");
            expectCount(onStalls, 2, "load->jalr: 2 stalls");
            expectTwinsEqual;
        end
    endtask

    task test15_load_gap2_branch;
        begin
            $display("\n--- Test 15: load two ahead of a branch needs no stall ---");
            startProg;
            emit(ADDI(2, 0, 10));
            emit(LW(3, 512, 0));          // x3 = 10
            emit(NOP(0));
            emit(NOP(0));
            emit(BEQ(3, 2, 8));           // taken
            emit(ADDI(9, 0, 99));         // skipped
            emit(ADDI(10, 0, 1));
            emit(EBREAK);
            runProg;
            expectReg(9, 32'd0, "taken, skipped");
            expectReg(10, 32'd1, "target executed");
            expectCount(onStalls, 0, "load, 2 gap, branch: 0 stalls");
            expectTwinsEqual;
        end
    endtask

    task test16_ebreak_no_spurious_stall;
        begin
            $display("\n--- Test 16: EBREAK (rs2 field = 1) behind a load into x1 must not stall ---");
            startProg;
            emit(LW(1, 512, 0));          // x1 = 10, rd matches EBREAK's rs2 field
            emit(EBREAK);
            runProg;
            expectReg(1, 32'd10, "lw before ebreak");
            expectCount(onStalls, 0, "no spurious stall for ebreak");
            expectCount(onCycles, 6, "halts at cycle 2 * (N + 2)");
        end
    endtask

    task test19_jalr_odd_base;
        begin
            $display("\n--- Test 19: JALR clears bit 0 of the target ---");
            startProg;
            emit(ADDI(1, 0, 17));         //  0: odd base
            emit(NOP(0));                 //  4
            emit(JALR(2, 1, 0));          //  8: target 17 & ~1 = 16
            emit(ADDI(5, 0, 1));          // 12: skipped
            emit(ADDI(6, 0, 3));          // 16
            emit(EBREAK);                  // 20
            runProg;
            expectReg(2, 32'd12, "jalr link");
            expectReg(5, 32'd0, "skipped");
            expectReg(6, 32'd3, "landed on 16, not 17");
            expectTwinsEqual;
        end
    endtask

    task test17_back_to_back_branches;
        begin
            $display("\n--- Test 17: branch whose target is another branch ---");
            startProg;
            emit(ADDI(1, 0, 1));          //  0
            emit(NOP(0));                 //  4
            emit(BEQ(1, 1, 8));           //  8: taken to 16
            emit(ADDI(9, 0, 99));         // 12: skipped
            emit(BNE(1, 0, 8));           // 16: taken to 24 (branch is a branch target)
            emit(ADDI(10, 0, 99));        // 20: skipped
            emit(ADDI(11, 0, 1));         // 24
            emit(JAL(0, 8));              // 28: to 36
            emit(ADDI(12, 0, 99));        // 32: skipped
            emit(ADDI(13, 0, 1));         // 36
            emit(EBREAK);
            runProg;
            expectReg(9, 32'd0, "first branch skip");
            expectReg(10, 32'd0, "branch at branch target skip");
            expectReg(11, 32'd1, "reached");
            expectReg(12, 32'd0, "jal skip");
            expectReg(13, 32'd1, "reached after jal");
            expectCount(onMispred, 3, "three cold control transfers");
            expectTwinsEqual;
        end
    endtask

    task test18_no_penalty_when_predicted;
        begin
            $display("\n--- Test 18: a correctly predicted taken branch has no squash ---");
            // 12-iteration loop: BP off mispredicts all 11 taken branches; BP on
            // mispredicts only the first taken branch and the exit (2), so it
            // avoids 9 mispredicts x 2 cycles (1 squashed slot) = 18 cycles.
            startProg;
            emit(ADDI(1, 0, 12));         //  0
            emit(NOP(0));                 //  4
            emit(NOP(0));                 //  8
            emit(ADDI(1, 1, -1));         // 12
            emit(NOP(0));                 // 16
            emit(BNE(1, 0, -8));          // 20: back to 12 (x1 two ahead: forwarded)
            emit(EBREAK);                  // 24
            runProg;
            expectReg(1, 32'd0, "loop counter");
            expectCount(onMispred, 2, "BP on: first taken + exit");
            expectCount(offMispred, 11, "BP off: 11 taken branches");
            expectCount(offCycles - onCycles, (11 - 2) * 2, "saved 2 cycles per avoided mispredict");
            expectTwinsEqual;
            report("predicted loop");
        end
    endtask

    // ------------------------------------------------------------------
    // Test 20 helpers: expected BHT walk
    // ------------------------------------------------------------------
    // Outcome table for branch B (1 = taken), 13 entries
    function walkOut(input integer n);
        begin
            case (n)
                0, 1, 2:        walkOut = 1'b1;
                3, 4, 5, 6:     walkOut = 1'b0;
                7, 8, 9, 10:    walkOut = 1'b1;
                11:             walkOut = 1'b0;
                default:        walkOut = 1'b1;
            endcase
        end
    endfunction

    // Counter after the n-th update of B, and whether that update was a
    // mispredict:  T,T,T,N,N,N,N,T,T,T,T,N,T
    function [1:0] expBState(input integer n);
        begin
            case (n)
                0:  expBState = 2'b10;   // allocate (weakly taken)
                1:  expBState = 2'b11;
                2:  expBState = 2'b11;
                3:  expBState = 2'b10;
                4:  expBState = 2'b01;
                5:  expBState = 2'b00;   // strongly not taken
                6:  expBState = 2'b00;   // saturated
                7:  expBState = 2'b01;
                8:  expBState = 2'b10;
                9:  expBState = 2'b11;
                10: expBState = 2'b11;
                11: expBState = 2'b10;   // single anomaly
                default: expBState = 2'b11;
            endcase
        end
    endfunction

    function expBMis(input integer n);
        begin
            case (n)
                0, 3, 4, 7, 8, 11: expBMis = 1'b1;
                default:           expBMis = 1'b0;
            endcase
        end
    endfunction

    // Inner loop branch: T,T,T,N repeated 4 times (state kept across outers)
    function [1:0] expIBState(input integer n);
        begin
            expIBState = (n == 0 || (n % 4) == 3) ? 2'b10 : 2'b11;
        end
    endfunction

    function expIBMis(input integer n);
        begin
            expIBMis = (n == 0 || (n % 4) == 3) ? 1'b1 : 1'b0;
        end
    endfunction

    task test20_predictor_state_walk;
        integer k;
        integer nB, badB, nIB, badIB;
        reg     sawSNT;
        reg [1:0] lastB;
        begin
            $display("\n--- Test 20: 2-bit predictor state walk (SNT -> WNT -> WT -> ST), nested loops ---");
            startProg;
            // outcome table for branch B at 0x200 (1 = taken)
            for (k = 0; k < 13; k = k + 1) begin
                wr32(10'h200 + 4 * k, walkOut(k));
            end
            // ---- Part A: data-driven branch B inside loop J (PCs 0x24 / 0x30) ----
            emit(ADDI(10, 0, 512));       // 0x00 outcome table pointer
            emit(ADDI(11, 0, 0));         // 0x04 iteration counter
            emit(ADDI(13, 0, 13));        // 0x08 N
            emit(ADDI(20, 0, 0));         // 0x0C not-taken count
            emit(ADDI(21, 0, 0));         // 0x10 iterations
            emit(LW(6, 0, 10));           // 0x14 loopA: next outcome
            emit(ADDI(10, 10, 4));        // 0x18
            emit(ADDI(11, 11, 1));        // 0x1C
            emit(NOP(0));                 // 0x20 keeps the lw 4 instructions from B
            emit(BNE(6, 0, 8));           // 0x24 B: branch under test
            emit(ADDI(20, 20, 1));        // 0x28 only when B not taken
            emit(ADDI(21, 21, 1));        // 0x2C
            emit(BNE(11, 13, -28));       // 0x30 J: loop back to 0x14
            // ---- Part B: nested loops, inner exit pattern T,T,T,N ----
            emit(ADDI(22, 0, 0));         // 0x34 total inner iterations
            emit(ADDI(23, 0, 0));         // 0x38 outer counter
            emit(ADDI(24, 0, 4));         // 0x3C M outer
            emit(ADDI(25, 0, 4));         // 0x40 K inner
            emit(ADDI(23, 23, 1));        // 0x44 outer:
            emit(ADDI(26, 0, 0));         // 0x48
            emit(ADDI(26, 26, 1));        // 0x4C inner:
            emit(ADDI(22, 22, 1));        // 0x50
            emit(ADDI(27, 27, 3));        // 0x54 filler
            emit(ADDI(28, 28, 7));        // 0x58 filler
            emit(BNE(26, 25, -16));       // 0x5C IB: inner loop-back
            emit(BNE(23, 24, -28));       // 0x60 OB: outer loop-back
            emit(EBREAK);                  // 0x64
            logCnt = 0;
            runProg;

            expectReg(20, 32'd5, "B not-taken count");
            expectReg(21, 32'd13, "iterations");
            expectReg(22, 32'd16, "inner iterations (4 x 4)");
            expectReg(23, 32'd4, "outer iterations");
            expectReg(27, 32'd48, "inner filler x27");
            expectReg(28, 32'd112, "inner filler x28");
            expectCount(onStalls, 0, "no hazard stalls (pure predictor)");
            expectCount(onMispred, 15, "BP on: B 6 + J 2 + IB 5 + OB 2");
            expectCount(offMispred, 35, "BP off: 8 + 12 + 12 + 3 taken");

            // ---- BHT walk of B (PC 0x24) and of the inner branch (PC 0x5C) ----
            nB = 0; badB = 0; nIB = 0; badIB = 0;
            sawSNT = 1'b0; lastB = 2'b00;
            for (k = 0; k < logCnt; k = k + 1) begin
                if (logPC[k] === 32'h24) begin
                    if (nB < 13 && (logState[k] !== expBState(nB) || logMis[k] !== expBMis(nB))) begin
                        badB = badB + 1;
                        $display("       B  #%0d: state=%b mis=%b, expected state=%b mis=%b",
                                 nB, logState[k], logMis[k], expBState(nB), expBMis(nB));
                    end
                    if (logState[k] === 2'b00) sawSNT = 1'b1;
                    lastB = logState[k];
                    nB = nB + 1;
                end
                if (logPC[k] === 32'h5C) begin
                    if (nIB < 16 && (logState[k] !== expIBState(nIB) || logMis[k] !== expIBMis(nIB))) begin
                        badIB = badIB + 1;
                        $display("       IB #%0d: state=%b mis=%b, expected state=%b mis=%b",
                                 nIB, logState[k], logMis[k], expIBState(nIB), expIBMis(nIB));
                    end
                    nIB = nIB + 1;
                end
            end
            check(nB == 13 && badB == 0, "branch B: state walk and mispredicts match");
            check(sawSNT && lastB == 2'b11, "B reached 00 (SNT) and returned to 11 (ST)");
            check(nIB == 16 && badIB == 0, "inner branch: 10,11,11,10 then 11,11,11,10");
            expectTwinsEqual;
            report("predictor walk");
        end
    endtask

    // ------------------------------------------------------------------
    // Test 21 helpers: keep every TAKEN branch in its own BTB slot
    // (index = PC[5:2]) so the warm passes are not disturbed by aliasing.
    // padT(k): the branch will sit k instructions after the current point.
    // ------------------------------------------------------------------
    reg [15:0] usedIdx;
    integer    topAddr;
    integer    pcA;

    task padT(input integer k);
        integer slotIdx;
        begin
            slotIdx = ((progPtr + 4 * k) >> 2) & 15;
            while (usedIdx[slotIdx]) begin
                emit(NOP(0));
                slotIdx = ((progPtr + 4 * k) >> 2) & 15;
            end
            usedIdx[slotIdx] = 1'b1;
        end
    endtask

    // Stale value first, then a producer (add/addi/lw) directly before the
    // branch. A branch that used the stale value flips its outcome:
    //   TAKEN case     : fall-through marker  x30 += 1   (FAIL mark)
    //   NOT-TAKEN case : fall-through marker  x29 += 1   (PASS mark)
    // Block runs 3 times: pass 1 cold predictor, passes 2-3 warm.
    task test21_stale_value_hazards;
        begin
            $display("\n--- Test 21: add/lw directly before a branch, stale values, cold + warm predictor ---");
            startProg;
            wr32(10'h200, 32'd10);
            wr32(10'h204, 32'd10);
            wr32(10'h208, 32'd20);
            wr32(10'h20C, 32'hFFFFFFFB);
            wr32(10'h210, 32'd0);
            usedIdx = 16'd0;

            emit(ADDI(10, 0, 512));       // data base
            emit(ADDI(27, 0, 3));         // 3 passes
            emit(ADDI(28, 0, 0));         // pass counter
            emit(ADDI(29, 0, 0));         // NOT-TAKEN pass marks (expect 9)
            emit(ADDI(30, 0, 0));         // FAIL marks (expect 0)
            emit(ADDI(3, 0, 10));         // constant used by the lw cases
            topAddr = progPtr;
            emit(ADDI(28, 28, 1));        // top:

            // 1: ALU -> beq, distance 1, rs1.  Taken.  1 stall
            padT(3);
            emit(ADDI(1, 0, 1));
            emit(ADDI(2, 0, 5));
            emit(ADDI(1, 2, 0));
            emit(BEQ(1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 2: ALU -> bne, distance 1.  Not taken (stale would be taken).  1 stall
            emit(ADDI(1, 0, 1));
            emit(ADDI(2, 0, 5));
            emit(ADDI(1, 2, 0));
            emit(BNE(1, 2, 8));
            emit(ADDI(29, 29, 1));
            // 3: add -> beq, distance 2 (EX/MEM forward).  Taken.  0 stalls
            padT(4);
            emit(ADDI(1, 0, 1));
            emit(ADDI(2, 0, 9));
            emit(ADD(1, 2, 0));
            emit(ADDI(4, 4, 1));
            emit(BEQ(1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 4: ALU -> blt, distance 3 (value already in the RegFile: written in C0).  Taken.  0 stalls
            padT(5);
            emit(ADDI(1, 0, 100));
            emit(ADDI(2, 0, 50));
            emit(ADDI(1, 0, 3));
            emit(ADDI(4, 4, 1));
            emit(ADDI(4, 4, 1));
            emit(brInst(2, 1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 5: ALU -> beq, distance 1, rs2 forwarded.  Taken.  1 stall
            padT(3);
            emit(ADDI(1, 0, 4));
            emit(ADDI(2, 0, 8));
            emit(ADDI(2, 0, 4));
            emit(BEQ(1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 6: both operands forwarded (rs1 distance 2, rs2 distance 1).  Taken.  1 stall
            padT(4);
            emit(ADDI(1, 0, 1));
            emit(ADDI(2, 0, 2));
            emit(ADDI(1, 0, 6));
            emit(ADDI(2, 0, 6));
            emit(BEQ(1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 7: two writers of the same rd, branch needs the newest.  Taken.  1 stall
            padT(3);
            emit(ADDI(2, 0, 7));
            emit(ADDI(1, 0, 2));
            emit(ADDI(1, 0, 7));
            emit(BEQ(1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 8: lw -> bne, distance 1.  Taken.  2 stalls
            padT(2);
            emit(ADDI(1, 0, 0));
            emit(LW(1, 0, 10));
            emit(BNE(1, 0, 8));
            emit(ADDI(30, 30, 1));
            // 9: lw -> bne, distance 1.  Not taken (value 0, stale 5 would be taken).  2 stalls
            emit(ADDI(1, 0, 5));
            emit(LW(1, 16, 10));
            emit(BNE(1, 0, 8));
            emit(ADDI(29, 29, 1));
            // 10: lw -> beq, distance 2.  Taken.  1 stall
            padT(3);
            emit(ADDI(2, 0, 99));
            emit(LW(2, 4, 10));
            emit(ADDI(4, 4, 1));
            emit(BEQ(2, 3, 8));
            emit(ADDI(30, 30, 1));
            // 11: lw -> beq, distance 3 (load data already in the RegFile).  Taken.  0 stalls
            padT(4);
            emit(ADDI(2, 0, 99));
            emit(LW(2, 4, 10));
            emit(ADDI(4, 4, 1));
            emit(ADDI(4, 4, 1));
            emit(BEQ(2, 3, 8));
            emit(ADDI(30, 30, 1));
            // 12: lw of a negative value -> blt, distance 1.  Taken.  2 stalls
            padT(2);
            emit(ADDI(1, 0, 1));
            emit(LW(1, 12, 10));
            emit(brInst(2, 1, 0, 8));
            emit(ADDI(30, 30, 1));
            // 13: lw (rs1, distance 2) + addi (rs2, distance 1).  Taken.  1 stall
            padT(4);
            emit(ADDI(1, 0, 3));
            emit(ADDI(2, 0, 99));
            emit(LW(1, 0, 10));
            emit(ADDI(2, 0, 10));
            emit(BEQ(1, 2, 8));
            emit(ADDI(30, 30, 1));
            // 14: ALU -> blt, distance 2.  Not taken (stale 1 would be taken).  0 stalls
            emit(ADDI(1, 0, 1));
            emit(ADDI(2, 0, 50));
            emit(ADDI(1, 0, 80));
            emit(ADDI(4, 4, 1));
            emit(brInst(2, 1, 2, 8));
            emit(ADDI(29, 29, 1));
            // 15: ALU -> jalr base, distance 1.  Must land on the target.  1 stall
            pcA = progPtr;
            emit(ADDI(5, 0, pcA + 12));   // stale base: points at the fail marker
            emit(ADDI(5, 0, pcA + 16));   // producer: real target
            emit(JALR(0, 5, 0));
            emit(ADDI(30, 30, 1));        // fail marker
            // loop back (target of the jalr is the instruction after the marker)
            padT(0);
            emit(BNE(28, 27, topAddr - progPtr));
            emit(EBREAK);
            runProg;

            expectReg(28, 32'd3, "passes completed");
            expectReg(30, 32'd0, "FAIL marks (taken case fell through)");
            expectReg(29, 32'd9, "NOT-TAKEN passes: 3 cases x 3");
            expectReg(4, 32'd21, "independent fillers executed");
            expectCount(onStalls, 42, "stalls: 14 per pass x 3 passes");
            expectCount(offStalls, 42, "stalls independent of predictor");
            expectCount(onMispred, 16, "BP on: 11 cold + 3 jalr + 2 loop");
            expectCount(offMispred, 38, "BP off: 33 taken + 3 jalr + 2 loop");
            check(onMispred < offMispred, "warm predictor avoids mispredicts while stalled");
            expectTwinsEqual;
            report("stale-value hazards");
        end
    endtask

    task test22_x0_write_branch;
        begin
            $display("\n--- Test 22: a discarded write to x0 must not feed a branch ---");
            startProg;
            emit(ADDI(5, 0, 0));          //  0
            emit(ADDI(0, 0, 7));          //  4: discarded write
            emit(BEQ(0, 5, 8));           //  8: x0 (=0) == x5 (=0) -> taken, skips next
            emit(ADDI(30, 0, 1));         // 12: executes only if x0 was forwarded as 7
            emit(EBREAK);                  // 16
            runProg;
            expectReg(30, 32'd0, "branch ignores discarded x0 write");
            expectTwinsEqual;
            expectCount(onStalls, 0, "x0 write -> branch: no spurious stall");
        end
    endtask

    // ECALL, FENCE, FENCE.TSO and PAUSE are NOPs. Only EBREAK halts.
    task test23_nops_and_halt;
        begin
            $display("\n--- Test 23: ECALL / FENCE / FENCE.TSO / PAUSE are NOPs, only EBREAK halts ---");
            startProg;
            emit(ADDI(1, 0, 5));
            emit(ECALL);
            emit(ADDI(2, 1, 3));          // dependent chain straight through the NOPs
            emit(FENCE);
            emit(ADDI(3, 2, 3));
            emit(FENCET);
            emit(ADDI(4, 3, 3));
            emit(PAUSE);
            emit(ADD(5, 4, 1));
            emit(ECALL);
            emit(ECALL);
            emit(ADDI(6, 0, 66));         // runs: both ECALLs did not halt
            emit(FENCE);                  // keeps the producer 2 ahead of the branch
            emit(BEQ(6, 6, 8));           // taken: skips the next FENCE
            emit(FENCE);
            emit(PAUSE);
            emit(ADDI(8, 0, 88));
            emit(EBREAK);
            emit(ADDI(7, 0, 77));         // must not execute
            runProg;
            expectReg(2, 32'd8, "dependent chain through ecall");
            expectReg(3, 32'd11, "dependent chain through fence");
            expectReg(4, 32'd14, "dependent chain through fence.tso");
            expectReg(5, 32'd19, "dependent chain through pause");
            expectReg(6, 32'd66, "ran past two ecalls");
            expectReg(8, 32'd88, "ran up to ebreak");
            expectReg(7, 32'd0, "instruction after ebreak not executed");
            expectCount(onStalls, 0, "NOPs cause no stalls");
            check(dut.haltLatch === 1'b1 && dutNo.haltLatch === 1'b1, "ebreak latched the halt");
            expectTwinsEqual;
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
        logCnt   = 0;
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
        test12_id_branch_hazards;
        test13_branch_suite;
        test14_jalr_load;
        test15_load_gap2_branch;
        test16_ebreak_no_spurious_stall;
        test17_back_to_back_branches;
        test18_no_penalty_when_predicted;
        test19_jalr_odd_base;
        test20_predictor_state_walk;
        test21_stale_value_hazards;
        test22_x0_write_branch;
        test23_nops_and_halt;

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