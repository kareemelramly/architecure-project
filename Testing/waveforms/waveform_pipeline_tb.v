/*******************************************************************************
 * Module: waveform_pipeline_tb.v
 * Project: femtoRV32
 * Author: Kareem Elramly
 * Description: Dumps report waveforms for wave.hex in one configuration
 *              (set with -P: BRANCH_IN_ID, BP). Run from Verilog/:
 *   iverilog -g2012 -s waveform_pipeline_tb -Pwaveform_pipeline_tb.BRANCH_IN_ID=1 \
 *     -o /tmp/w.out ../Testing/waveforms/waveform_pipeline_tb.v <rtl files>
 *   vvp /tmp/w.out +vcd=../Testing/waveforms/wave_id.vcd
 *
 * Change history:
 *   11/16/26 - created for the MS3 report
 ******************************************************************************/

`timescale 1ns / 1ps

module waveform_pipeline_tb #(parameter BRANCH_IN_ID = 1, parameter BP = 1);
    reg clk = 1'b0, reset = 1'b1;
    reg [8*80-1:0] vcdName;
    always #5 clk = ~clk;

    pipeline #(.BP_ENABLE(BP), .BRANCH_IN_ID(BRANCH_IN_ID),
               .PROGRAM_FILE("../Testing/waveforms/wave.hex")) dut(
        .clk(clk), .reset(reset), .dbgRegSel(5'd0), .dbgRegData(),
        .dbgPC(), .dbgNextPC(), .dbgInst(), .dbgAluResult(), .dbgMemAddr(),
        .dbgMemOut(), .dbgWbData(), .dbgStoreData(), .dbgCtrlFlags(),
        .dbgPipeFlags(), .dbgHalt());

    initial begin
        if (!$value$plusargs("vcd=%s", vcdName)) vcdName = "wave.vcd";
        $dumpfile(vcdName);
        $dumpvars(1, dut.clk, dut.phase, dut.pcValue, dut.idInst, dut.ID_EX_Inst,
                  dut.stall, dut.redirect, dut.squash, dut.haltLatch,
                  dut.regWriteEn, dut.MEM_WB_Rd, dut.regWriteData, dut.memAddr,
                  dut.predictTakenEff);
        #12 reset = 1'b0;
        wait (dut.haltLatch === 1'b1);
        repeat (6) @(posedge clk);
        $finish;
    end
endmodule
