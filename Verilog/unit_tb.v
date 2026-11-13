`timescale 1ns / 1ps
`include "defines.vh"
module unit_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    integer errors = 0;
    task check(input cond, input [8*48-1:0] msg);
        begin if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end end
    endtask
    // phase
    wire phase, isFetch, advance;
    PhaseController pc0(.clk(clk), .rst(rst), .phase(phase), .isFetch(isFetch), .advance(advance));
    // memory
    reg memRead, memWrite; reg [2:0] f3; reg [9:0] addr; reg [31:0] din; wire [31:0] dout;
    UnifiedMem mem0(.clk(clk), .memRead(memRead), .memWrite(memWrite), .funct3(f3), .addr(addr), .dataIn(din), .dataOut(dout));
    // predictor
    reg [31:0] pcIF, upPC, upTgt; reg upEn, upT; wire pT; wire [31:0] pTgt;
    BranchPredictor bp(.clk(clk), .rst(rst), .pcIF(pcIF), .predictTaken(pT), .predictTarget(pTgt),
        .updateEn(upEn), .updatePC(upPC), .actualTaken(upT), .actualTarget(upTgt));
    // forwarding unit
    reg [4:0] rs1, rs2, exRd, wbRd; reg exWr, wbWr; wire [1:0] fA, fB;
    ForwardingUnit fu(.idExRs1(rs1), .idExRs2(rs2), .exMemRd(exRd), .memWbRd(wbRd),
        .exMemRegWrite(exWr), .memWbRegWrite(wbWr), .forwardA(fA), .forwardB(fB));
    // pipeline register
    reg prLoad, prFlush; reg [7:0] prD; wire [7:0] prQ;
    PipelineReg #(8) pr(.clk(clk), .rst(rst), .load(prLoad), .flush(prFlush), .D(prD), .Q(prQ));
    task upd(input [31:0] p, input t, input [31:0] tg);
        begin upPC = p; upT = t; upTgt = tg; upEn = 1; @(posedge clk); #1 upEn = 0; end
    endtask
    initial begin
        memRead = 1; memWrite = 0; f3 = `MEM_LW; addr = 0; din = 0; upEn = 0; pcIF = 32'h40;
        #12 rst = 0;
        // phase toggles 0,1,0,1
        @(posedge clk); #1 check(phase == 1, "phase after 1 edge");
        @(posedge clk); #1 check(phase == 0, "phase after 2 edges");
        // memory: fetch word 0, data word 0x200
        addr = 10'h000; #1 check(dout == 32'b001000000000_00000_010_00001_0000011, "fetch word0");
        addr = 10'h200; #1 check(dout == 32'd10, "lw 0x200");
        addr = 10'h208; f3 = `MEM_LB; #1 check(dout == 32'hFFFFFFFB, "lb sign");
        f3 = `MEM_LBU; #1 check(dout == 32'h000000FB, "lbu");
        addr = 10'h216; f3 = `MEM_LHU; #1 check(dout == 32'h00007C8A, "lhu upper half");
        // sb then sh then readback
        addr = 10'h201; f3 = `MEM_SB; din = 32'hAB; memWrite = 1; @(posedge clk); #1 memWrite = 0;
        addr = 10'h200; f3 = `MEM_LW; #1 check(dout == 32'h0000AB0A, "sb byte1");
        addr = 10'h202; f3 = `MEM_SH; din = 32'h1234; memWrite = 1; @(posedge clk); #1 memWrite = 0;
        addr = 10'h200; f3 = `MEM_LW; #1 check(dout == 32'h1234AB0A, "sh upper half");
        memRead = 0; #1 check(dout == 0, "memRead=0 -> 0");
        // predictor: unseen -> not taken
        #1 check(pT == 0, "cold miss NT");
        upd(32'h40, 1, 32'h10); #1 check(pT == 1 && pTgt == 32'h10, "alloc weak T");
        upd(32'h40, 1, 32'h10); upd(32'h40, 1, 32'h10); // -> 11
        upd(32'h40, 0, 0); #1 check(pT == 1, "11->10 still T");
        upd(32'h40, 0, 0); #1 check(pT == 0, "10->01 NT");
        upd(32'h40, 0, 0); upd(32'h40, 0, 0); #1 check(pT == 0, "sat at 00");
        upd(32'h40, 1, 32'h10); #1 check(pT == 0, "00->01 NT");
        // alias: same index, different tag, not-taken must not touch entry
        upd(32'h440, 0, 0); upd(32'h40, 1, 32'h10); #1 check(pT == 1, "01->10 T, alias untouched");
        pcIF = 32'h440; #1 check(pT == 0, "alias PC miss");
        // ---- ForwardingUnit ----
        rs1 = 5; rs2 = 6; exRd = 5; wbRd = 6; exWr = 1; wbWr = 1; #1;
        check(fA == 2'b10 && fB == 2'b01, "fwd: A from EX/MEM, B from MEM/WB");
        exRd = 5; wbRd = 5; rs2 = 5; #1;
        check(fA == 2'b10 && fB == 2'b10, "fwd: EX/MEM has priority");
        exWr = 0; #1;
        check(fA == 2'b01 && fB == 2'b01, "fwd: falls to MEM/WB without regwrite");
        wbWr = 0; #1;
        check(fA == 2'b00 && fB == 2'b00, "fwd: returns to 00 (no latch)");
        rs1 = 0; rs2 = 0; exRd = 0; wbRd = 0; exWr = 1; wbWr = 1; #1;
        check(fA == 2'b00 && fB == 2'b00, "fwd: x0 never forwarded");
        // ---- PipelineReg ----
        prLoad = 0; prFlush = 0; prD = 8'hA5; @(posedge clk); #1;
        check(prQ == 8'h00, "pipereg: holds when load=0");
        prLoad = 1; @(posedge clk); #1;
        check(prQ == 8'hA5, "pipereg: loads");
        prLoad = 0; prD = 8'h3C; @(posedge clk); #1;
        check(prQ == 8'hA5, "pipereg: holds loaded value");
        prFlush = 1; @(posedge clk); #1;
        check(prQ == 8'h00, "pipereg: flush clears even with load=0");
        prLoad = 1; prD = 8'hFF; @(posedge clk); #1;
        check(prQ == 8'h00, "pipereg: flush wins over load");
        prFlush = 0; prLoad = 0;
        if (errors == 0) $display("ALL UNIT TESTS PASSED"); else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule
