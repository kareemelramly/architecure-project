/*******************************************************************************
 * Module: pipeline_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Mostafa Fayed
 * Description: Self-checking testbench for pipeline.v.
 *              A reference model (a simple one-instruction-at-a-time RV32IM
 *              simulator inside this file) runs the same program next to
 *              the pipeline and every instruction is checked:
 *                - issue: each valid instruction in ID (C1) must have the
 *                  PC and instruction word the reference model expects
 *                  (this checks every branch and jump outcome and target)
 *                - register write: value and register in WB (C0), exactly
 *                  3 cycles after ID (3 stages x 2 cycles = 6 cycles)
 *                - store: address, data and size in MEM (C1), 2 cycles
 *                  after ID
 *              One PASS line is printed for each instruction when its last
 *              check succeeds.
 *              Hazards: for every instruction that reads a register written
 *              by the instruction just before it, the testbench checks that
 *              the forwarding unit fired and prints the hazard; the result
 *              check proves the forwarded value was right.
 *              Bonus 2 (RV32M): the 8 multiply/divide instructions are
 *              checked like the others and counted in the coverage.
 *              Bonus 4 (branch in ID): instructions must enter ID exactly
 *              every 2 cycles from the first to EBREAK, so no taken branch
 *              or jump loses a cycle and no hazard stalls the pipeline.
 *              Also checked every cycle: no memory write in C0, the C0
 *              memory address is the PC, no register write in C1, the PC
 *              never moves after EBREAK.
 *              At the end: all 32 registers and the data memory must match
 *              the reference model, x30 = 0xC0DE and x31 = 0 (the
 *              program's own checks), and with COVERAGE = 1 all 42 RV32I
 *              instructions and the 8 RV32M instructions must have passed.
 *              Prints "TEST PASSED" or "TEST FAILED".
 *
 * Parameters: PROG      "" (default): the full test program built into
 *                       this file (Testing/programs/full_test.s), so no
 *                       file path is needed (Vivado runs the simulation
 *                       from its own folder). Otherwise a .hex image (one
 *                       32-bit word per line), best as an absolute path.
 *             ADDR_BITS memory size of the pipeline under test
 *             VERBOSE   1: one line per instruction, 0: summary only
 *             COVERAGE  1: require every instruction to be covered
 *
 * Vivado: set pipeline_tb as simulation top and click Run Simulation.
 *         The built-in program finishes in about 500 ns (1 ns clock), so
 *         the default run time of 1000 ns is enough. Results are printed
 *         in the Tcl Console (and in simulate.log). With another PROG use
 *         Run All.
 *
 * Change history:
 *   11/18/26 - Replaces the old pipeline_tb, datapath_board_pipelined_tb
 *              and the ForwardingUnit/PhaseController/PipelineReg unit
 *              testbenches with one system-level self-checking testbench
 *   11/18/26 - Vivado: program built in (no file path), 1 ns clock so the
 *              default 1000 ns run is enough
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module pipeline_tb;

    parameter PROG       = "";          // "" = built-in full test
    parameter ADDR_BITS  = 13;
    parameter VERBOSE    = 1;
    parameter COVERAGE   = 1;
    parameter MAX_CYCLES = 20000;

    localparam WORDS  = 1 << (ADDR_BITS - 2);
    localparam QSIZE  = 16;
    localparam NINSTR = 50;     // 42 RV32I + 8 RV32M

    reg         clk;
    reg         rst;
    wire [31:0] pcOut;
    wire [31:0] instOut;
    wire [31:0] exResultOut;
    wire [31:0] memAddrOut;
    wire [31:0] memDataOut;
    wire [31:0] storeDataOut;
    wire [31:0] wbDataOut;
    wire [4:0]  wbRdOut;
    wire        halted;

    pipeline #(
        .PROGRAM_FILE(PROG),
        .ADDR_BITS(ADDR_BITS)
    ) dut(
        .clk(clk),
        .rst(rst),
        .pcOut(pcOut),
        .instOut(instOut),
        .exResultOut(exResultOut),
        .memAddrOut(memAddrOut),
        .memDataOut(memDataOut),
        .storeDataOut(storeDataOut),
        .wbDataOut(wbDataOut),
        .wbRdOut(wbRdOut),
        .halted(halted)
    );

    // 1 ns clock period (1 GHz is only a simulation speed; the design has
    // no delays) so the full test fits in Vivado's default 1000 ns run
    always #0.5 clk = ~clk;

    // =========================================================================
    // Reference model state
    // =========================================================================
    reg  [31:0] progImg [0:WORDS-1];
    reg  [31:0] refReg [0:31];
    reg  [31:0] refMem [0:WORDS-1];
    reg  [31:0] refPC;
    reg         refHalted;

    // Result of one reference step
    reg  [31:0] stInst;
    reg  [5:0]  stId;          // instruction index 0..49
    reg         stWritesReg;
    reg  [4:0]  stRd;
    reg  [31:0] stRdVal;
    reg         stIsStore;
    reg  [31:0] stStAddr;
    reg  [31:0] stStData;
    reg  [2:0]  stStF3;
    reg         stIsBranch;
    reg         stTaken;
    reg  [31:0] stNextPC;
    reg         stUsesRs1;
    reg         stUsesRs2;

    // =========================================================================
    // Instruction names and indices (0..41 RV32I, 42..49 RV32M)
    // =========================================================================
    function [8*9-1:0] instName(input [5:0] id);
        case (id)
            6'd0:  instName = "LUI";     6'd1:  instName = "AUIPC";
            6'd2:  instName = "JAL";     6'd3:  instName = "JALR";
            6'd4:  instName = "BEQ";     6'd5:  instName = "BNE";
            6'd6:  instName = "BLT";     6'd7:  instName = "BGE";
            6'd8:  instName = "BLTU";    6'd9:  instName = "BGEU";
            6'd10: instName = "LB";      6'd11: instName = "LH";
            6'd12: instName = "LW";      6'd13: instName = "LBU";
            6'd14: instName = "LHU";     6'd15: instName = "SB";
            6'd16: instName = "SH";      6'd17: instName = "SW";
            6'd18: instName = "ADDI";    6'd19: instName = "SLTI";
            6'd20: instName = "SLTIU";   6'd21: instName = "XORI";
            6'd22: instName = "ORI";     6'd23: instName = "ANDI";
            6'd24: instName = "SLLI";    6'd25: instName = "SRLI";
            6'd26: instName = "SRAI";    6'd27: instName = "ADD";
            6'd28: instName = "SUB";     6'd29: instName = "SLL";
            6'd30: instName = "SLT";     6'd31: instName = "SLTU";
            6'd32: instName = "XOR";     6'd33: instName = "SRL";
            6'd34: instName = "SRA";     6'd35: instName = "OR";
            6'd36: instName = "AND";     6'd37: instName = "FENCE";
            6'd38: instName = "FENCE.TSO"; 6'd39: instName = "PAUSE";
            6'd40: instName = "ECALL";   6'd41: instName = "EBREAK";
            6'd42: instName = "MUL";     6'd43: instName = "MULH";
            6'd44: instName = "MULHSU";  6'd45: instName = "MULHU";
            6'd46: instName = "DIV";     6'd47: instName = "DIVU";
            6'd48: instName = "REM";     6'd49: instName = "REMU";
            default: instName = "???";
        endcase
    endfunction

    // =========================================================================
    // Reference model: execute the instruction at refPC
    // =========================================================================
    reg  [31:0] a;
    reg  [31:0] b;
    reg  [31:0] immI;
    reg  [31:0] immS;
    reg  [31:0] immB;
    reg  [31:0] immU;
    reg  [31:0] immJ;
    reg  [31:0] addr;
    reg  [31:0] word;
    reg  [63:0] prod;
    reg  [6:0]  op;
    reg  [2:0]  f3;
    reg  [6:0]  f7;
    reg         known;

    task refStep;
        begin
            stInst      = refMem[refPC[ADDR_BITS-1:2]];
            op          = stInst[6:0];
            f3          = stInst[14:12];
            f7          = stInst[31:25];
            stRd        = stInst[11:7];
            a           = refReg[stInst[19:15]];
            b           = refReg[stInst[24:20]];
            immI        = {{20{stInst[31]}}, stInst[31:20]};
            immS        = {{20{stInst[31]}}, stInst[31:25], stInst[11:7]};
            immB        = {{19{stInst[31]}}, stInst[31], stInst[7],
                           stInst[30:25], stInst[11:8], 1'b0};
            immU        = {stInst[31:12], 12'd0};
            immJ        = {{11{stInst[31]}}, stInst[31], stInst[19:12],
                           stInst[20], stInst[30:21], 1'b0};
            stWritesReg = 1'b0;
            stRdVal     = 32'd0;
            stIsStore   = 1'b0;
            stIsBranch  = 1'b0;
            stTaken     = 1'b0;
            stNextPC    = refPC + 32'd4;
            stUsesRs1   = 1'b0;
            stUsesRs2   = 1'b0;
            stId        = 6'd63;
            known       = 1'b1;

            case (op)
                7'b0110111: begin                               // LUI
                    stId = 6'd0;  stWritesReg = 1'b1; stRdVal = immU;
                end
                7'b0010111: begin                               // AUIPC
                    stId = 6'd1;  stWritesReg = 1'b1; stRdVal = refPC + immU;
                end
                7'b1101111: begin                               // JAL
                    stId = 6'd2;  stWritesReg = 1'b1; stRdVal = refPC + 32'd4;
                    stIsBranch = 1'b1; stTaken = 1'b1;
                    stNextPC = refPC + immJ;
                end
                7'b1100111: begin                               // JALR
                    stId = 6'd3;  stWritesReg = 1'b1; stRdVal = refPC + 32'd4;
                    stUsesRs1 = 1'b1;
                    stIsBranch = 1'b1; stTaken = 1'b1;
                    stNextPC = (a + immI) & 32'hFFFF_FFFE;
                end
                7'b1100011: begin                               // branches
                    stUsesRs1 = 1'b1; stUsesRs2 = 1'b1; stIsBranch = 1'b1;
                    case (f3)
                        `BR_BEQ:  begin stId = 6'd4; stTaken = (a == b); end
                        `BR_BNE:  begin stId = 6'd5; stTaken = (a != b); end
                        `BR_BLT:  begin stId = 6'd6;
                                  stTaken = ($signed(a) < $signed(b)); end
                        `BR_BGE:  begin stId = 6'd7;
                                  stTaken = ($signed(a) >= $signed(b)); end
                        `BR_BLTU: begin stId = 6'd8; stTaken = (a < b); end
                        `BR_BGEU: begin stId = 6'd9; stTaken = (a >= b); end
                        default:  known = 1'b0;
                    endcase
                    if (stTaken) begin
                        stNextPC = refPC + immB;
                    end
                end
                7'b0000011: begin                               // loads
                    stUsesRs1 = 1'b1; stWritesReg = 1'b1;
                    addr = a + immI;
                    word = refMem[addr[ADDR_BITS-1:2]];
                    case (f3)
                        `MEM_LB:  begin stId = 6'd10;
                            word = word >> (addr[1:0] * 8);
                            stRdVal = {{24{word[7]}}, word[7:0]}; end
                        `MEM_LH:  begin stId = 6'd11;
                            word = word >> (addr[1] * 16);
                            stRdVal = {{16{word[15]}}, word[15:0]}; end
                        `MEM_LW:  begin stId = 6'd12; stRdVal = word; end
                        `MEM_LBU: begin stId = 6'd13;
                            word = word >> (addr[1:0] * 8);
                            stRdVal = {24'd0, word[7:0]}; end
                        `MEM_LHU: begin stId = 6'd14;
                            word = word >> (addr[1] * 16);
                            stRdVal = {16'd0, word[15:0]}; end
                        default:  known = 1'b0;
                    endcase
                end
                7'b0100011: begin                               // stores
                    stUsesRs1 = 1'b1; stUsesRs2 = 1'b1; stIsStore = 1'b1;
                    stStAddr = a + immS;
                    stStData = b;
                    stStF3   = f3;
                    word = refMem[stStAddr[ADDR_BITS-1:2]];
                    case (f3)
                        `MEM_SB: begin stId = 6'd15;
                            case (stStAddr[1:0])
                                2'd0: word[7:0]   = b[7:0];
                                2'd1: word[15:8]  = b[7:0];
                                2'd2: word[23:16] = b[7:0];
                                default: word[31:24] = b[7:0];
                            endcase
                        end
                        `MEM_SH: begin stId = 6'd16;
                            if (stStAddr[1]) word[31:16] = b[15:0];
                            else             word[15:0]  = b[15:0];
                        end
                        `MEM_SW: begin stId = 6'd17; word = b; end
                        default: known = 1'b0;
                    endcase
                    refMem[stStAddr[ADDR_BITS-1:2]] = word;
                end
                7'b0010011: begin                               // OP-IMM
                    stUsesRs1 = 1'b1; stWritesReg = 1'b1;
                    case (f3)
                        3'b000: begin stId = 6'd18; stRdVal = a + immI; end
                        3'b010: begin stId = 6'd19;
                            stRdVal = ($signed(a) < $signed(immI)); end
                        3'b011: begin stId = 6'd20; stRdVal = (a < immI); end
                        3'b100: begin stId = 6'd21; stRdVal = a ^ immI; end
                        3'b110: begin stId = 6'd22; stRdVal = a | immI; end
                        3'b111: begin stId = 6'd23; stRdVal = a & immI; end
                        3'b001: begin stId = 6'd24;
                            stRdVal = a << stInst[24:20]; end
                        default: begin
                            if (stInst[30]) begin stId = 6'd26;
                                stRdVal = $signed(a) >>> stInst[24:20];
                            end else begin stId = 6'd25;
                                stRdVal = a >> stInst[24:20];
                            end
                        end
                    endcase
                end
                7'b0110011: begin                               // OP
                    stUsesRs1 = 1'b1; stUsesRs2 = 1'b1; stWritesReg = 1'b1;
                    if (f7 == 7'b0000001) begin                 // RV32M
                        case (f3)
                            3'b000: begin stId = 6'd42; prod = a * b;
                                stRdVal = prod[31:0]; end
                            3'b001: begin stId = 6'd43;
                                prod = {{32{a[31]}}, a} * {{32{b[31]}}, b};
                                stRdVal = prod[63:32]; end
                            3'b010: begin stId = 6'd44;
                                prod = {{32{a[31]}}, a} * {32'd0, b};
                                stRdVal = prod[63:32]; end
                            3'b011: begin stId = 6'd45;
                                prod = {32'd0, a} * {32'd0, b};
                                stRdVal = prod[63:32]; end
                            3'b100: begin stId = 6'd46;
                                if (b == 32'd0) stRdVal = 32'hFFFF_FFFF;
                                else if ((a == 32'h8000_0000) &&
                                         (b == 32'hFFFF_FFFF)) stRdVal = a;
                                else stRdVal = $signed(a) / $signed(b);
                            end
                            3'b101: begin stId = 6'd47;
                                stRdVal = (b == 32'd0) ? 32'hFFFF_FFFF
                                                       : a / b; end
                            3'b110: begin stId = 6'd48;
                                if (b == 32'd0) stRdVal = a;
                                else if ((a == 32'h8000_0000) &&
                                         (b == 32'hFFFF_FFFF)) stRdVal = 0;
                                else stRdVal = $signed(a) % $signed(b);
                            end
                            default: begin stId = 6'd49;
                                stRdVal = (b == 32'd0) ? a : a % b; end
                        endcase
                    end else begin
                        case (f3)
                            3'b000: if (stInst[30]) begin stId = 6'd28;
                                        stRdVal = a - b;
                                    end else begin stId = 6'd27;
                                        stRdVal = a + b; end
                            3'b001: begin stId = 6'd29; stRdVal = a << b[4:0]; end
                            3'b010: begin stId = 6'd30;
                                stRdVal = ($signed(a) < $signed(b)); end
                            3'b011: begin stId = 6'd31; stRdVal = (a < b); end
                            3'b100: begin stId = 6'd32; stRdVal = a ^ b; end
                            3'b101: if (stInst[30]) begin stId = 6'd34;
                                        stRdVal = $signed(a) >>> b[4:0];
                                    end else begin stId = 6'd33;
                                        stRdVal = a >> b[4:0]; end
                            3'b110: begin stId = 6'd35; stRdVal = a | b; end
                            default: begin stId = 6'd36; stRdVal = a & b; end
                        endcase
                    end
                end
                7'b0001111: begin                               // MISC-MEM
                    if (stInst == 32'h8330000f)      stId = 6'd38;
                    else if (stInst == 32'h0100000f) stId = 6'd39;
                    else                             stId = 6'd37;
                end
                7'b1110011: begin                               // SYSTEM
                    if (stInst == 32'h00100073) begin
                        stId = 6'd41; refHalted = 1'b1;
                    end else begin
                        stId = 6'd40;
                    end
                end
                default: known = 1'b0;
            endcase

            if (stWritesReg && (stRd != 5'd0)) begin
                refReg[stRd] = stRdVal;
            end
            refPC = stNextPC;
        end
    endtask

    // =========================================================================
    // Expected events still in the pipeline (FIFOs)
    // =========================================================================
    reg  [5:0]  wbId   [0:QSIZE-1];
    reg  [4:0]  wbRd   [0:QSIZE-1];
    reg  [31:0] wbVal  [0:QSIZE-1];
    reg  [31:0] wbPC   [0:QSIZE-1];
    integer     wbDue  [0:QSIZE-1];
    reg  [8*84-1:0] wbNote [0:QSIZE-1];
    integer     wbHead, wbTail;

    integer     wbSeq  [0:QSIZE-1];
    integer     sSeq   [0:QSIZE-1];
    reg  [8*48-1:0] sNote [0:QSIZE-1];

    // in-order print queue: line text and done flag per issued instruction
    reg  [8*200-1:0] pText [0:QSIZE-1];
    reg         pDone  [0:QSIZE-1];
    integer     pHead;
    reg  [8*200-1:0] line;
    integer     seq;

    reg  [5:0]  sId    [0:QSIZE-1];
    reg  [31:0] sAddr  [0:QSIZE-1];
    reg  [31:0] sData  [0:QSIZE-1];
    reg  [2:0]  sF3    [0:QSIZE-1];
    reg  [31:0] sPC    [0:QSIZE-1];
    integer     sDue   [0:QSIZE-1];
    integer     sHead, sTail;

    // =========================================================================
    // Bookkeeping
    // =========================================================================
    integer     cycle;
    integer     errors;
    integer     issued;
    integer     passed;
    integer     lastIssue;
    integer     covered [0:NINSTR-1];
    integer     hzAluNext, hzLoadNext, hzBranch, hzJalr, hzStore, hzTwo;
    integer     hzTwoBranch;
    integer     takenCnt, notTakenCnt;
    integer     gapErrors;
    integer     i, missing;
    reg  [31:0] haltPC;
    reg         haltSeen;

    // previous issued instruction (for hazard classification)
    reg         prevWrites;
    reg  [4:0]  prevRd;
    reg         prevIsLoad;
    reg  [5:0]  prevId;
    reg         prev2Writes;
    reg  [4:0]  prev2Rd;

    reg         dep1;
    reg         dep2;
    reg         depOld;
    reg  [8*48-1:0] note;

    // mark instruction number n as passed and store its PASS line
    task finish(input integer n, input [31:0] pc, input [8*200-1:0] text);
        begin
            passed = passed + 1;
            $sformat(line, "PASS %4d  pc=%h  %0s", n + 1, pc, text);
            pText[n % QSIZE] = line;
            pDone[n % QSIZE] = 1'b1;
        end
    endtask

    task fail(input [8*72-1:0] msg);
        begin
            errors = errors + 1;
            $display("ERROR cycle %0d: %0s", cycle, msg);
        end
    endtask

    // =========================================================================
    // Checks. Sampled at the falling edge (middle of the cycle, all
    // combinational values settled); the pipeline registers change at the
    // rising edge.
    // =========================================================================
    always @(negedge clk) begin
        if (!rst) begin
            // ---- every cycle: single memory port and phase rules ----
            if (dut.isC0 && dut.memPortWrite) begin
                fail("memory write in C0 (fetch cycle)");
            end
            if (dut.isC0 && (dut.memPortAddr !== dut.IF_PC[ADDR_BITS-1:0]))
            begin
                fail("C0 memory address is not the PC");
            end
            if (dut.isC1 && dut.WB_RegWriteEn) begin
                fail("register write in C1");
            end
            if (haltSeen && (dut.IF_PC !== haltPC)) begin
                fail("PC moved after EBREAK");
            end

            // ---- issue: valid instruction in ID during C1 ----
            if (dut.isC1 && dut.ID_Valid) begin
                if (refHalted) begin
                    fail("instruction issued after EBREAK");
                end
                if ((lastIssue >= 0) && (cycle - lastIssue != 2)) begin
                    errors = errors + 1;
                    gapErrors = gapErrors + 1;
                    $display("ERROR cycle %0d: %0d cycles since the last ",
                             cycle, cycle - lastIssue,
                             "instruction entered ID (expected 2: no ",
                             "stall, no branch penalty)");
                end
                lastIssue = cycle;
                if (dut.IF_ID_PC !== refPC) begin
                    errors = errors + 1;
                    $display("ERROR cycle %0d: ID has PC %h, expected %h",
                             cycle, dut.IF_ID_PC, refPC);
                end
                refStep;
                seq = issued;
                issued = issued + 1;
                pDone[seq % QSIZE] = 1'b0;
                if (!known || (stId == 6'd63)) begin
                    errors = errors + 1;
                    $display("ERROR: unknown instruction %h at %h",
                             stInst, dut.IF_ID_PC);
                end
                if (dut.IF_ID_Inst !== stInst) begin
                    errors = errors + 1;
                    $display("ERROR cycle %0d: ID has %h, expected %h",
                             cycle, dut.IF_ID_Inst, stInst);
                end

                // ---- hazard classification ----
                dep1   = prevWrites && (prevRd != 5'd0) &&
                         ((stUsesRs1 && (stInst[19:15] == prevRd)) ||
                          (stUsesRs2 && (stInst[24:20] == prevRd)));
                dep2   = prev2Writes && (prev2Rd != 5'd0) &&
                         ((stUsesRs1 && (stInst[19:15] == prev2Rd)) ||
                          (stUsesRs2 && (stInst[24:20] == prev2Rd)));
                note   = "";
                if (dep1) begin
                    if (stUsesRs1 && (stInst[19:15] == prevRd) &&
                        !dut.forwarding.forwardA) begin
                        fail("RAW hazard on rs1 not forwarded");
                    end
                    if (stUsesRs2 && (stInst[24:20] == prevRd) &&
                        !dut.forwarding.forwardB) begin
                        fail("RAW hazard on rs2 not forwarded");
                    end
                    if (prevIsLoad) hzLoadNext = hzLoadNext + 1;
                    else            hzAluNext  = hzAluNext + 1;
                    if (stIsBranch && (stId != 6'd2)) begin
                        if (stId == 6'd3) hzJalr = hzJalr + 1;
                        else              hzBranch = hzBranch + 1;
                    end
                    if (stIsStore && (stInst[24:20] == prevRd)) begin
                        hzStore = hzStore + 1;
                    end
                    $sformat(note, "RAW x%0d from %0s forwarded to ID",
                             prevRd, instName(prevId));
                end else if (dep2) begin
                    // the producer was written back in the C0 just before
                    // this C1: the register file must already hold it
                    // (a, b = source values in the reference model)
                    if (stUsesRs1 && (stInst[19:15] == prev2Rd) &&
                        (dut.ID_ReadData1 !== a)) begin
                        fail("distance-2 value not yet in the register file");
                    end
                    if (stUsesRs2 && (stInst[24:20] == prev2Rd) &&
                        (dut.ID_ReadData2 !== b)) begin
                        fail("distance-2 value not yet in the register file");
                    end
                    if (stIsBranch && (stId != 6'd2)) begin
                        hzTwoBranch = hzTwoBranch + 1;
                    end
                    hzTwo = hzTwo + 1;
                    $sformat(note, "RAW x%0d (distance 2) from reg file",
                             prev2Rd);
                end

                if (stIsBranch) begin
                    if (stTaken) takenCnt = takenCnt + 1;
                    else         notTakenCnt = notTakenCnt + 1;
                end

                // ---- schedule the checks of this instruction ----
                if (stWritesReg && (stRd != 5'd0)) begin
                    wbId[wbTail % QSIZE]   = stId;
                    wbRd[wbTail % QSIZE]   = stRd;
                    wbVal[wbTail % QSIZE]  = stRdVal;
                    wbPC[wbTail % QSIZE]   = dut.IF_ID_PC;
                    wbDue[wbTail % QSIZE]  = cycle + 3;
                    if (stIsBranch) begin
                        $sformat(line,
                                 "jump -> %h (in ID, 0 lost cycles)%0s%0s",
                                 stNextPC, (note != "") ? ", " : "", note);
                        wbNote[wbTail % QSIZE] = line;
                    end else begin
                        wbNote[wbTail % QSIZE] = note;
                    end
                    wbSeq[wbTail % QSIZE]  = seq;
                    wbTail = wbTail + 1;
                end else if (stIsStore) begin
                    sId[sTail % QSIZE]   = stId;
                    sAddr[sTail % QSIZE] = stStAddr;
                    sData[sTail % QSIZE] = stStData;
                    sF3[sTail % QSIZE]   = stStF3;
                    sPC[sTail % QSIZE]   = dut.IF_ID_PC;
                    sDue[sTail % QSIZE]  = cycle + 2;
                    sNote[sTail % QSIZE] = note;
                    sSeq[sTail % QSIZE]  = seq;
                    sTail = sTail + 1;
                end else begin
                    // nothing left to check later: passed now
                    covered[stId] = covered[stId] + 1;
                    if (stIsBranch && stTaken) begin
                        $sformat(line, "%-9s taken -> %h (in ID, 0 lost cycles)%0s%0s",
                                 instName(stId), stNextPC,
                                 (note != "") ? "  " : "", note);
                    end else if (stIsBranch) begin
                        $sformat(line, "%-9s not taken%0s%0s", instName(stId),
                                 (note != "") ? "  " : "", note);
                    end else if (stId == 6'd41) begin
                        $sformat(line, "%-9s CPU halts", instName(stId));
                    end else begin
                        $sformat(line, "%-9s no effect (rd = x0 or NOP)",
                                 instName(stId));
                    end
                    finish(seq, dut.IF_ID_PC, line);
                end

                prev2Writes = prevWrites;
                prev2Rd     = prevRd;
                prevWrites  = stWritesReg;
                prevRd      = stRd;
                prevIsLoad  = (stId >= 6'd10) && (stId <= 6'd14);
                prevId      = stId;

                if (stId == 6'd41) begin
                    haltSeen = 1'b1;
                end
            end

            // ---- WB: register write in C0 ----
            if (dut.isC0 && dut.WB_RegWriteEn && (dut.MEM_WB_Rd != 5'd0))
            begin
                if (wbHead == wbTail) begin
                    errors = errors + 1;
                    $display("ERROR cycle %0d: unexpected write x%0d = %h",
                             cycle, dut.MEM_WB_Rd, dut.WB_Data);
                end else begin
                    if ((dut.MEM_WB_Rd !== wbRd[wbHead % QSIZE]) ||
                        (dut.WB_Data !== wbVal[wbHead % QSIZE])) begin
                        errors = errors + 1;
                        $display("ERROR cycle %0d: %0s at %h wrote x%0d = %h, expected x%0d = %h",
                                 cycle, instName(wbId[wbHead % QSIZE]),
                                 wbPC[wbHead % QSIZE], dut.MEM_WB_Rd,
                                 dut.WB_Data, wbRd[wbHead % QSIZE],
                                 wbVal[wbHead % QSIZE]);
                    end else if (cycle != wbDue[wbHead % QSIZE]) begin
                        errors = errors + 1;
                        $display("ERROR cycle %0d: %0s at %h written back in cycle %0d, expected %0d",
                                 cycle, instName(wbId[wbHead % QSIZE]),
                                 wbPC[wbHead % QSIZE], cycle,
                                 wbDue[wbHead % QSIZE]);
                    end else begin
                        covered[wbId[wbHead % QSIZE]] =
                            covered[wbId[wbHead % QSIZE]] + 1;
                        $sformat(line, "%-9s x%-2d = %h%0s%0s",
                                 instName(wbId[wbHead % QSIZE]),
                                 wbRd[wbHead % QSIZE], wbVal[wbHead % QSIZE],
                                 (wbNote[wbHead % QSIZE] != "") ? "  " : "",
                                 wbNote[wbHead % QSIZE]);
                        finish(wbSeq[wbHead % QSIZE], wbPC[wbHead % QSIZE],
                               line);
                    end
                    wbHead = wbHead + 1;
                end
            end

            // ---- MEM: store in C1 ----
            if (dut.isC1 && dut.memPortWrite) begin
                if (sHead == sTail) begin
                    fail("unexpected memory write");
                end else begin
                    if ((dut.memPortAddr !== sAddr[sHead % QSIZE][ADDR_BITS-1:0]) ||
                        (dut.EX_MEM_StoreData !== sData[sHead % QSIZE]) ||
                        (dut.memPortFunct3 !== sF3[sHead % QSIZE])) begin
                        errors = errors + 1;
                        $display("ERROR cycle %0d: %0s at %h stored %h to %h, expected %h to %h",
                                 cycle, instName(sId[sHead % QSIZE]),
                                 sPC[sHead % QSIZE], dut.EX_MEM_StoreData,
                                 dut.memPortAddr, sData[sHead % QSIZE],
                                 sAddr[sHead % QSIZE]);
                    end else if (cycle != sDue[sHead % QSIZE]) begin
                        fail("store not in MEM 2 cycles after ID");
                    end else begin
                        covered[sId[sHead % QSIZE]] =
                            covered[sId[sHead % QSIZE]] + 1;
                        $sformat(line, "%-9s mem[%h] <= %h%0s%0s",
                                 instName(sId[sHead % QSIZE]),
                                 sAddr[sHead % QSIZE], sData[sHead % QSIZE],
                                 (sNote[sHead % QSIZE] != "") ? "  " : "",
                                 sNote[sHead % QSIZE]);
                        finish(sSeq[sHead % QSIZE], sPC[sHead % QSIZE], line);
                    end
                    sHead = sHead + 1;
                end
            end

            // print finished instructions in program order
            while ((pHead < issued) && pDone[pHead % QSIZE]) begin
                if (VERBOSE) begin
                    $display("%0s", pText[pHead % QSIZE]);
                end
                pHead = pHead + 1;
            end

            if (haltSeen && (haltPC === 32'hx)) begin
                haltPC = dut.IF_PC;
            end
            cycle = cycle + 1;
        end
    end

    // =========================================================================
    // Run and final report
    // =========================================================================
    initial begin
        clk = 1'b0;
        rst = 1'b1;
        for (i = 0; i < 32; i = i + 1) begin
            refReg[i] = 32'd0;
        end
        // ---- program: built-in image or PROG file ----
        for (i = 0; i < WORDS; i = i + 1) begin
            progImg[i] = 32'd0;
        end
        if (PROG == "") begin
            loadFullTest;
        end else begin
            $readmemh(PROG, progImg);
        end
        // after UnifiedMem's own initial block (time 0), copy the program
        // into the pipeline memory and the reference model
        #0.1;
        for (i = 0; i < WORDS; i = i + 1) begin
            dut.memory.mem[i] = progImg[i];
            refMem[i]         = progImg[i];
        end
        for (i = 0; i < NINSTR; i = i + 1) begin
            covered[i] = 0;
        end
        refPC = 32'd0;   refHalted = 1'b0;
        cycle = 0;       errors = 0;      issued = 0;     passed = 0;
        lastIssue = -1;  wbHead = 0;      wbTail = 0;
        sHead = 0;       sTail = 0;
        hzAluNext = 0;   hzLoadNext = 0;  hzBranch = 0;
        hzJalr = 0;      hzStore = 0;     hzTwo = 0;
        hzTwoBranch = 0;
        takenCnt = 0;    notTakenCnt = 0;  gapErrors = 0;
        pHead = 0;
        prevWrites = 1'b0;  prev2Writes = 1'b0;
        prevRd = 5'd0;      prev2Rd = 5'd0;
        prevIsLoad = 1'b0;  prevId = 6'd0;
        haltSeen = 1'b0;    haltPC = 32'hx;

        if (PROG == "") begin
            $display("pipeline_tb: built-in full test (full_test.s)");
        end else begin
            $display("pipeline_tb: %0s", PROG);
        end
        // reset changes on the falling edge, away from the rising edge
        repeat (2) @(negedge clk);
        rst = 1'b0;

        while (!(haltSeen && (wbHead == wbTail) && (sHead == sTail)) &&
               (cycle < MAX_CYCLES)) begin
            @(negedge clk);
        end
        repeat (6) @(negedge clk);           // PC must stay frozen

        // ---- final state ----
        if (!haltSeen) begin
            fail("no EBREAK reached");
        end
        for (i = 1; i < 32; i = i + 1) begin
            if (dut.RegisterFile.d_reg[i] !== refReg[i]) begin
                errors = errors + 1;
                $display("ERROR: final x%0d = %h, expected %h", i,
                         dut.RegisterFile.d_reg[i], refReg[i]);
            end
        end
        for (i = 0; i < WORDS; i = i + 1) begin
            if (dut.memory.mem[i] !== refMem[i]) begin
                errors = errors + 1;
                $display("ERROR: final mem[%h] = %h, expected %h", i * 4,
                         dut.memory.mem[i], refMem[i]);
            end
        end
        if (dut.RegisterFile.d_reg[30] !== 32'h0000C0DE) begin
            fail("program did not finish (x30 != 0xC0DE)");
        end
        if (dut.RegisterFile.d_reg[31] !== 32'd0) begin
            fail("program self-check failed (x31 != 0)");
        end

        missing = 0;
        if (COVERAGE) begin
            for (i = 0; i < NINSTR; i = i + 1) begin
                if (covered[i] == 0) begin
                    missing = missing + 1;
                    errors  = errors + 1;
                    $display("ERROR: %0s never executed", instName(i));
                end
            end
        end

        $display("");
        $display("==================== SUMMARY ====================");
        $display("instructions checked : %0d of %0d issued in %0d cycles",
                 passed, issued, cycle);
        if (COVERAGE) begin
            $display("RV32I coverage       : %0d / 42 instructions",
                     42 - missingIn(0, 42));
            $display("RV32M (Bonus 2)      : %0d / 8 instructions",
                     8 - missingIn(42, 50));
        end
        $display("branches/jumps       : %0d taken, %0d not taken, all resolved in ID with 0 lost cycles (Bonus 4)",
                 takenCnt, notTakenCnt);
        $display("RAW hazards (dist 1) : %0d after ALU, %0d after load, forwarded EX_MEM/memory -> ID",
                 hzAluNext, hzLoadNext);
        $display("  used by a branch   : %0d, by JALR: %0d, as store data: %0d",
                 hzBranch, hzJalr, hzStore);
        $display("RAW hazards (dist 2) : %0d, read from the register file (%0d by a branch/JALR in ID)",
                 hzTwo, hzTwoBranch);
        if (gapErrors == 0) begin
            $display("stalls / bubbles     : 0 (one instruction entered ID every 2 cycles)");
        end else begin
            $display("stalls / bubbles     : %0d (see errors)", gapErrors);
        end
        $display("errors               : %0d", errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

    // Built-in program: Testing/programs/full_test.s (code at 0x0000,
    // data at 0x1000). Regenerate after changing full_test.s.
    task loadFullTest;
        begin
            progImg[0] = 32'h00000f93;        // 0000 li x31, 0x0
            progImg[1] = 32'h00100093;        // 0004 li x1, 0x1
            progImg[2] = 32'h00000073;        // 0008 ecall
            progImg[3] = 32'h00108093;        // 000C addi x1, x1, 0x1
            progImg[4] = 32'h0ff0000f;        // 0010 fence
            progImg[5] = 32'h00108093;        // 0014 addi x1, x1, 0x1
            progImg[6] = 32'h8330000f;        // 0018 fence.tso
            progImg[7] = 32'h00108093;        // 001C addi x1, x1, 0x1
            progImg[8] = 32'h0100000f;        // 0020 pause
            progImg[9] = 32'h00108093;        // 0024 addi x1, x1, 0x1
            progImg[10] = 32'h00500113;       // 0028 li x2, 0x5
            progImg[11] = 32'h3c209e63;       // 002C bne x1, x2, 0x408
            progImg[12] = 32'h00001a17;       // 0030 auipc x20, 0x1
            progImg[13] = 32'hfd0a0a13;       // 0034 addi x20, x20, -0x30
            progImg[14] = 32'h00c00093;       // 0038 li x1, 0xc
            progImg[15] = 32'hffb00113;       // 003C li x2, -0x5
            progImg[16] = 32'h002081b3;       // 0040 add x3, x1, x2
            progImg[17] = 32'h00700213;       // 0044 li x4, 0x7
            progImg[18] = 32'h3c419063;       // 0048 bne x3, x4, 0x408
            progImg[19] = 32'h402081b3;       // 004C sub x3, x1, x2
            progImg[20] = 32'h01100213;       // 0050 li x4, 0x11
            progImg[21] = 32'h3a419a63;       // 0054 bne x3, x4, 0x408
            progImg[22] = 32'h001091b3;       // 0058 sll x3, x1, x1
            progImg[23] = 32'h0000c237;       // 005C lui x4, 0xc
            progImg[24] = 32'h3a419463;       // 0060 bne x3, x4, 0x408
            progImg[25] = 32'h001121b3;       // 0064 slt x3, x2, x1
            progImg[26] = 32'h00100213;       // 0068 li x4, 0x1
            progImg[27] = 32'h38419e63;       // 006C bne x3, x4, 0x408
            progImg[28] = 32'h001131b3;       // 0070 sltu x3, x2, x1
            progImg[29] = 32'h38019a63;       // 0074 bnez x3, 0x408
            progImg[30] = 32'h0020c1b3;       // 0078 xor x3, x1, x2
            progImg[31] = 32'hff700213;       // 007C li x4, -0x9
            progImg[32] = 32'h38419463;       // 0080 bne x3, x4, 0x408
            progImg[33] = 32'h004151b3;       // 0084 srl x3, x2, x4
            progImg[34] = 32'h1ff00213;       // 0088 li x4, 0x1ff
            progImg[35] = 32'h36419e63;       // 008C bne x3, x4, 0x408
            progImg[36] = 32'h401151b3;       // 0090 sra x3, x2, x1
            progImg[37] = 32'hfff00213;       // 0094 li x4, -0x1
            progImg[38] = 32'h36419863;       // 0098 bne x3, x4, 0x408
            progImg[39] = 32'h0020e1b3;       // 009C or x3, x1, x2
            progImg[40] = 32'hfff00213;       // 00A0 li x4, -0x1
            progImg[41] = 32'h36419263;       // 00A4 bne x3, x4, 0x408
            progImg[42] = 32'h0020f1b3;       // 00A8 and x3, x1, x2
            progImg[43] = 32'h00800213;       // 00AC li x4, 0x8
            progImg[44] = 32'h34419c63;       // 00B0 bne x3, x4, 0x408
            progImg[45] = 32'hffe08193;       // 00B4 addi x3, x1, -0x2
            progImg[46] = 32'h00a00213;       // 00B8 li x4, 0xa
            progImg[47] = 32'h34419663;       // 00BC bne x3, x4, 0x408
            progImg[48] = 32'h00012193;       // 00C0 slti x3, x2, 0x0
            progImg[49] = 32'h00100213;       // 00C4 li x4, 0x1
            progImg[50] = 32'h34419063;       // 00C8 bne x3, x4, 0x408
            progImg[51] = 32'h00113193;       // 00CC seqz x3, x2
            progImg[52] = 32'h32019c63;       // 00D0 bnez x3, 0x408
            progImg[53] = 32'h0050c193;       // 00D4 xori x3, x1, 0x5
            progImg[54] = 32'h00900213;       // 00D8 li x4, 0x9
            progImg[55] = 32'h32419663;       // 00DC bne x3, x4, 0x408
            progImg[56] = 32'h0030e193;       // 00E0 ori x3, x1, 0x3
            progImg[57] = 32'h00f00213;       // 00E4 li x4, 0xf
            progImg[58] = 32'h32419063;       // 00E8 bne x3, x4, 0x408
            progImg[59] = 32'h0060f193;       // 00EC andi x3, x1, 0x6
            progImg[60] = 32'h00400213;       // 00F0 li x4, 0x4
            progImg[61] = 32'h30419a63;       // 00F4 bne x3, x4, 0x408
            progImg[62] = 32'h00209193;       // 00F8 slli x3, x1, 0x2
            progImg[63] = 32'h03000213;       // 00FC li x4, 0x30
            progImg[64] = 32'h30419463;       // 0100 bne x3, x4, 0x408
            progImg[65] = 32'h0020d193;       // 0104 srli x3, x1, 0x2
            progImg[66] = 32'h00300213;       // 0108 li x4, 0x3
            progImg[67] = 32'h2e419e63;       // 010C bne x3, x4, 0x408
            progImg[68] = 32'h40115193;       // 0110 srai x3, x2, 0x1
            progImg[69] = 32'hffd00213;       // 0114 li x4, -0x3
            progImg[70] = 32'h2e419863;       // 0118 bne x3, x4, 0x408
            progImg[71] = 32'h123451b7;       // 011C lui x3, 0x12345
            progImg[72] = 32'h12345237;       // 0120 lui x4, 0x12345
            progImg[73] = 32'h2e419263;       // 0124 bne x3, x4, 0x408
            progImg[74] = 32'h00000197;       // 0128 auipc x3, 0x0
            progImg[75] = 32'h004002ef;       // 012C jal x5, 0x130
            progImg[76] = 32'hff828293;       // 0130 addi x5, x5, -0x8
            progImg[77] = 32'h2c519a63;       // 0134 bne x3, x5, 0x408
            progImg[78] = 32'h80f1f337;       // 0138 lui x6, 0x80f1f
            progImg[79] = 32'h2f330313;       // 013C addi x6, x6, 0x2f3
            progImg[80] = 32'h006a2023;       // 0140 sw x6, 0x0(x20)
            progImg[81] = 32'h000a2183;       // 0144 lw x3, 0x0(x20)
            progImg[82] = 32'h2c619063;       // 0148 bne x3, x6, 0x408
            progImg[83] = 32'h000a0183;       // 014C lb x3, 0x0(x20)
            progImg[84] = 32'hff300213;       // 0150 li x4, -0xd
            progImg[85] = 32'h2a419a63;       // 0154 bne x3, x4, 0x408
            progImg[86] = 32'h000a4183;       // 0158 lbu x3, 0x0(x20)
            progImg[87] = 32'h0f300213;       // 015C li x4, 0xf3
            progImg[88] = 32'h2a419463;       // 0160 bne x3, x4, 0x408
            progImg[89] = 32'h002a1183;       // 0164 lh x3, 0x2(x20)
            progImg[90] = 32'hffff8237;       // 0168 lui x4, 0xffff8
            progImg[91] = 32'h0f120213;       // 016C addi x4, x4, 0xf1
            progImg[92] = 32'h28419c63;       // 0170 bne x3, x4, 0x408
            progImg[93] = 32'h002a5183;       // 0174 lhu x3, 0x2(x20)
            progImg[94] = 32'h00008237;       // 0178 lui x4, 0x8
            progImg[95] = 32'h0f120213;       // 017C addi x4, x4, 0xf1
            progImg[96] = 32'h28419463;       // 0180 bne x3, x4, 0x408
            progImg[97] = 32'h001a0223;       // 0184 sb x1, 0x4(x20)
            progImg[98] = 32'h002a1323;       // 0188 sh x2, 0x6(x20)
            progImg[99] = 32'h004a2183;       // 018C lw x3, 0x4(x20)
            progImg[100] = 32'hfffb0237;      // 0190 lui x4, 0xfffb0
            progImg[101] = 32'h00c20213;      // 0194 addi x4, x4, 0xc
            progImg[102] = 32'h26419863;      // 0198 bne x3, x4, 0x408
            progImg[103] = 32'h00108463;      // 019C beq x1, x1, 0x1a4
            progImg[104] = 32'h2680006f;      // 01A0 j 0x408
            progImg[105] = 32'h00209463;      // 01A4 bne x1, x2, 0x1ac
            progImg[106] = 32'h2600006f;      // 01A8 j 0x408
            progImg[107] = 32'h00114463;      // 01AC blt x2, x1, 0x1b4
            progImg[108] = 32'h2580006f;      // 01B0 j 0x408
            progImg[109] = 32'h0020d463;      // 01B4 bge x1, x2, 0x1bc
            progImg[110] = 32'h2500006f;      // 01B8 j 0x408
            progImg[111] = 32'h0020e463;      // 01BC bltu x1, x2, 0x1c4
            progImg[112] = 32'h2480006f;      // 01C0 j 0x408
            progImg[113] = 32'h00117463;      // 01C4 bgeu x2, x1, 0x1cc
            progImg[114] = 32'h2400006f;      // 01C8 j 0x408
            progImg[115] = 32'h008003ef;      // 01CC jal x7, 0x1d4
            progImg[116] = 32'h2380006f;      // 01D0 j 0x408
            progImg[117] = 32'h00000417;      // 01D4 auipc x8, 0x0
            progImg[118] = 32'h01040413;      // 01D8 addi x8, x8, 0x10
            progImg[119] = 32'h001404e7;      // 01DC jalr x9, 0x1(x8)
            progImg[120] = 32'h2280006f;      // 01E0 j 0x408
            progImg[121] = 32'h00000217;      // 01E4 auipc x4, 0x0
            progImg[122] = 32'hffc20213;      // 01E8 addi x4, x4, -0x4
            progImg[123] = 32'h20449e63;      // 01EC bne x9, x4, 0x408
            progImg[124] = 32'h00700513;      // 01F0 li x10, 0x7
            progImg[125] = 32'hffd00593;      // 01F4 li x11, -0x3
            progImg[126] = 32'h02b501b3;      // 01F8 
            progImg[127] = 32'hfeb00213;      // 01FC li x4, -0x15
            progImg[128] = 32'h20419463;      // 0200 bne x3, x4, 0x408
            progImg[129] = 32'h02b511b3;      // 0204 
            progImg[130] = 32'hfff00213;      // 0208 li x4, -0x1
            progImg[131] = 32'h1e419e63;      // 020C bne x3, x4, 0x408
            progImg[132] = 32'h02b531b3;      // 0210 
            progImg[133] = 32'h00600213;      // 0214 li x4, 0x6
            progImg[134] = 32'h1e419863;      // 0218 bne x3, x4, 0x408
            progImg[135] = 32'h02a5a1b3;      // 021C 
            progImg[136] = 32'hfff00213;      // 0220 li x4, -0x1
            progImg[137] = 32'h1e419263;      // 0224 bne x3, x4, 0x408
            progImg[138] = 32'h02b541b3;      // 0228 
            progImg[139] = 32'hffe00213;      // 022C li x4, -0x2
            progImg[140] = 32'h1c419c63;      // 0230 bne x3, x4, 0x408
            progImg[141] = 32'h021551b3;      // 0234 
            progImg[142] = 32'h1c019863;      // 0238 bnez x3, 0x408
            progImg[143] = 32'h02b561b3;      // 023C 
            progImg[144] = 32'h00100213;      // 0240 li x4, 0x1
            progImg[145] = 32'h1c419263;      // 0244 bne x3, x4, 0x408
            progImg[146] = 32'h021571b3;      // 0248 
            progImg[147] = 32'h00700213;      // 024C li x4, 0x7
            progImg[148] = 32'h1a419c63;      // 0250 bne x3, x4, 0x408
            progImg[149] = 32'h00500013;      // 0254 li x0, 0x5
            progImg[150] = 32'h1a001863;      // 0258 bnez x0, 0x408
            progImg[151] = 32'h00c00093;      // 025C li x1, 0xc
            progImg[152] = 32'hffb00113;      // 0260 li x2, -0x5
            progImg[153] = 32'h1a208263;      // 0264 beq x1, x2, 0x408
            progImg[154] = 32'h1a109063;      // 0268 bne x1, x1, 0x408
            progImg[155] = 32'h1820ce63;      // 026C blt x1, x2, 0x408
            progImg[156] = 32'h18115c63;      // 0270 bge x2, x1, 0x408
            progImg[157] = 32'h18116a63;      // 0274 bltu x2, x1, 0x408
            progImg[158] = 32'h1820f863;      // 0278 bgeu x1, x2, 0x408
            progImg[159] = 32'h00000293;      // 027C li x5, 0x0
            progImg[160] = 32'h00400313;      // 0280 li x6, 0x4
            progImg[161] = 32'h00128293;      // 0284 addi x5, x5, 0x1
            progImg[162] = 32'hfe62cee3;      // 0288 blt x5, x6, 0x284
            progImg[163] = 32'h16629e63;      // 028C bne x5, x6, 0x408
            progImg[164] = 32'h00001a17;      // 0290 auipc x20, 0x1
            progImg[165] = 32'hd78a0a13;      // 0294 addi x20, x20, -0x288
            progImg[166] = 32'h00500093;      // 0298 li x1, 0x5
            progImg[167] = 32'hffb08113;      // 029C addi x2, x1, -0x5
            progImg[168] = 32'h00010463;      // 02A0 beqz x2, 0x2a8
            progImg[169] = 32'h001f8f93;      // 02A4 addi x31, x31, 0x1
            progImg[170] = 32'h00700193;      // 02A8 li x3, 0x7
            progImg[171] = 32'h00018463;      // 02AC beqz x3, 0x2b4
            progImg[172] = 32'h0080006f;      // 02B0 j 0x2b8
            progImg[173] = 32'h001f8f93;      // 02B4 addi x31, x31, 0x1
            progImg[174] = 32'h000a2203;      // 02B8 lw x4, 0x0(x20)
            progImg[175] = 32'h00021463;      // 02BC bnez x4, 0x2c4
            progImg[176] = 32'h001f8f93;      // 02C0 addi x31, x31, 0x1
            progImg[177] = 32'h004a2283;      // 02C4 lw x5, 0x4(x20)
            progImg[178] = 32'h00029463;      // 02C8 bnez x5, 0x2d0
            progImg[179] = 32'h0080006f;      // 02CC j 0x2d4
            progImg[180] = 32'h001f8f93;      // 02D0 addi x31, x31, 0x1
            progImg[181] = 32'h000a2303;      // 02D4 lw x6, 0x0(x20)
            progImg[182] = 32'h00100393;      // 02D8 li x7, 0x1
            progImg[183] = 32'h00031463;      // 02DC bnez x6, 0x2e4
            progImg[184] = 32'h001f8f93;      // 02E0 addi x31, x31, 0x1
            progImg[185] = 32'h00300413;      // 02E4 li x8, 0x3
            progImg[186] = 32'h00400493;      // 02E8 li x9, 0x4
            progImg[187] = 32'h00941463;      // 02EC bne x8, x9, 0x2f4
            progImg[188] = 32'h001f8f93;      // 02F0 addi x31, x31, 0x1
            progImg[189] = 32'h00940533;      // 02F4 add x10, x8, x9
            progImg[190] = 32'h00700593;      // 02F8 li x11, 0x7
            progImg[191] = 32'h00b50463;      // 02FC beq x10, x11, 0x304
            progImg[192] = 32'h001f8f93;      // 0300 addi x31, x31, 0x1
            progImg[193] = 32'h00000617;      // 0304 auipc x12, 0x0
            progImg[194] = 32'h01060613;      // 0308 addi x12, x12, 0x10
            progImg[195] = 32'h000606e7;      // 030C jalr x13, x12
            progImg[196] = 32'h001f8f93;      // 0310 addi x31, x31, 0x1
            progImg[197] = 32'h00000717;      // 0314 auipc x14, 0x0
            progImg[198] = 32'h01870713;      // 0318 addi x14, x14, 0x18
            progImg[199] = 32'h00ea2423;      // 031C sw x14, 0x8(x20)
            progImg[200] = 32'h008a2783;      // 0320 lw x15, 0x8(x20)
            progImg[201] = 32'h00078067;      // 0324 jr x15
            progImg[202] = 32'h001f8f93;      // 0328 addi x31, x31, 0x1
            progImg[203] = 32'h0080086f;      // 032C jal x16, 0x334
            progImg[204] = 32'h001f8f93;      // 0330 addi x31, x31, 0x1
            progImg[205] = 32'h00000897;      // 0334 auipc x17, 0x0
            progImg[206] = 32'h00088893;      // 0338 mv x17, x17
            progImg[207] = 32'h01181463;      // 033C bne x16, x17, 0x344
            progImg[208] = 32'h001f8f93;      // 0340 addi x31, x31, 0x1
            progImg[209] = 32'h000a2903;      // 0344 lw x18, 0x0(x20)
            progImg[210] = 32'h00190993;      // 0348 addi x19, x18, 0x1
            progImg[211] = 32'h013a2223;      // 034C sw x19, 0x4(x20)
            progImg[212] = 32'h004a2a83;      // 0350 lw x21, 0x4(x20)
            progImg[213] = 32'h12345b37;      // 0354 lui x22, 0x12345
            progImg[214] = 32'h679b0b13;      // 0358 addi x22, x22, 0x679
            progImg[215] = 32'h016a8463;      // 035C beq x21, x22, 0x364
            progImg[216] = 32'h001f8f93;      // 0360 addi x31, x31, 0x1
            progImg[217] = 32'h000a2b83;      // 0364 lw x23, 0x0(x20)
            progImg[218] = 32'h017a2423;      // 0368 sw x23, 0x8(x20)
            progImg[219] = 32'h008a2c03;      // 036C lw x24, 0x8(x20)
            progImg[220] = 32'h012c0463;      // 0370 beq x24, x18, 0x378
            progImg[221] = 32'h001f8f93;      // 0374 addi x31, x31, 0x1
            progImg[222] = 32'h00000293;      // 0378 li x5, 0x0
            progImg[223] = 32'h00700013;      // 037C li x0, 0x7
            progImg[224] = 32'h00500463;      // 0380 beq x0, x5, 0x388
            progImg[225] = 32'h001f8f93;      // 0384 addi x31, x31, 0x1
            progImg[226] = 32'h014a2623;      // 0388 sw x20, 0xc(x20)
            progImg[227] = 32'h00ca2c83;      // 038C lw x25, 0xc(x20)
            progImg[228] = 32'h000cad03;      // 0390 lw x26, 0x0(x25)
            progImg[229] = 32'h12345db7;      // 0394 lui x27, 0x12345
            progImg[230] = 32'h678d8d93;      // 0398 addi x27, x27, 0x678
            progImg[231] = 32'h01bd0463;      // 039C beq x26, x27, 0x3a4
            progImg[232] = 32'h001f8f93;      // 03A0 addi x31, x31, 0x1
            progImg[233] = 32'h00100e13;      // 03A4 li x28, 0x1
            progImg[234] = 32'h01ce0e33;      // 03A8 add x28, x28, x28
            progImg[235] = 32'h01ce0e33;      // 03AC add x28, x28, x28
            progImg[236] = 32'h01ce0e33;      // 03B0 add x28, x28, x28
            progImg[237] = 32'h00800e93;      // 03B4 li x29, 0x8
            progImg[238] = 32'h01de0463;      // 03B8 beq x28, x29, 0x3c0
            progImg[239] = 32'h001f8f93;      // 03BC addi x31, x31, 0x1
            progImg[240] = 32'h01ca2223;      // 03C0 sw x28, 0x4(x20)
            progImg[241] = 32'h004a2e83;      // 03C4 lw x29, 0x4(x20)
            progImg[242] = 32'hff8e8e93;      // 03C8 addi x29, x29, -0x8
            progImg[243] = 32'h000e8463;      // 03CC beqz x29, 0x3d4
            progImg[244] = 32'h001f8f93;      // 03D0 addi x31, x31, 0x1
            progImg[245] = 32'h00000663;      // 03D4 beqz x0, 0x3e0
            progImg[246] = 32'h000a2023;      // 03D8 sw x0, 0x0(x20)
            progImg[247] = 32'h001f8f93;      // 03DC addi x31, x31, 0x1
            progImg[248] = 32'h000a2d03;      // 03E0 lw x26, 0x0(x20)
            progImg[249] = 32'h01bd0463;      // 03E4 beq x26, x27, 0x3ec
            progImg[250] = 32'h001f8f93;      // 03E8 addi x31, x31, 0x1
            progImg[251] = 32'h008000ef;      // 03EC jal 0x3f4
            progImg[252] = 32'h0140006f;      // 03F0 j 0x404
            progImg[253] = 32'h001a2423;      // 03F4 sw x1, 0x8(x20)
            progImg[254] = 32'h008a2103;      // 03F8 lw x2, 0x8(x20)
            progImg[255] = 32'h00010067;      // 03FC jr x2
            progImg[256] = 32'h001f8f93;      // 0400 addi x31, x31, 0x1
            progImg[257] = 32'h0080006f;      // 0404 j 0x40c
            progImg[258] = 32'h001f8f93;      // 0408 addi x31, x31, 0x1
            progImg[259] = 32'h0000cf37;      // 040C lui x30, 0xc
            progImg[260] = 32'h0def0f13;      // 0410 addi x30, x30, 0xde
            progImg[261] = 32'h00100073;      // 0414 ebreak
            progImg[262] = 32'h064f8f93;      // 0418 addi x31, x31, 0x64
            progImg[1026] = 32'h12345678;     // 1008 data
        end
    endtask

    function integer missingIn(input integer lo, input integer hi);
        integer k;
        begin
            missingIn = 0;
            for (k = lo; k < hi; k = k + 1) begin
                if (covered[k] == 0) missingIn = missingIn + 1;
            end
        end
    endfunction

endmodule
