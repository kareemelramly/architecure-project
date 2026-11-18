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
 * Parameters: PROG      program image (.hex, one 32-bit word per line)
 *             ADDR_BITS memory size of the pipeline under test
 *             VERBOSE   1: one line per instruction, 0: summary only
 *             COVERAGE  1: require every instruction to be covered
 *
 * Change history:
 *   11/18/26 - Replaces the old pipeline_tb, datapath_board_pipelined_tb
 *              and the ForwardingUnit/PhaseController/PipelineReg unit
 *              testbenches with one system-level self-checking testbench
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module pipeline_tb;

    parameter PROG       = "../Testing/programs/full_test.hex";
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
    wire [31:0] wbDataOut;
    wire        halted;

    pipeline #(
        .PROGRAM_FILE(PROG),
        .ADDR_BITS(ADDR_BITS)
    ) dut(
        .clk(clk),
        .rst(rst),
        .pcOut(pcOut),
        .instOut(instOut),
        .wbDataOut(wbDataOut),
        .halted(halted)
    );

    always #5 clk = ~clk;

    // =========================================================================
    // Reference model state
    // =========================================================================
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
                        !dut.ID_ForwardA) begin
                        fail("RAW hazard on rs1 not forwarded");
                    end
                    if (stUsesRs2 && (stInst[24:20] == prevRd) &&
                        !dut.ID_ForwardB) begin
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
        for (i = 0; i < WORDS; i = i + 1) begin
            refMem[i] = 32'd0;
        end
        $readmemh(PROG, refMem);
        for (i = 0; i < NINSTR; i = i + 1) begin
            covered[i] = 0;
        end
        refPC = 32'd0;   refHalted = 1'b0;
        cycle = 0;       errors = 0;      issued = 0;     passed = 0;
        lastIssue = -1;  wbHead = 0;      wbTail = 0;
        sHead = 0;       sTail = 0;
        hzAluNext = 0;   hzLoadNext = 0;  hzBranch = 0;
        hzJalr = 0;      hzStore = 0;     hzTwo = 0;
        takenCnt = 0;    notTakenCnt = 0;  gapErrors = 0;
        pHead = 0;
        prevWrites = 1'b0;  prev2Writes = 1'b0;
        prevRd = 5'd0;      prev2Rd = 5'd0;
        prevIsLoad = 1'b0;  prevId = 6'd0;
        haltSeen = 1'b0;    haltPC = 32'hx;

        $display("pipeline_tb: %0s", PROG);
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
        $display("RAW hazards (dist 2) : %0d, read from the register file",
                 hzTwo);
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
