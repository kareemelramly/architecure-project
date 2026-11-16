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
        if (errors == 0) $display("ALL UNIT TESTS PASSED"); else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule
