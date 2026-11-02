`timescale 1ns / 1ps
// Optional waveform capture; leaves the processor and its testbench unchanged.
module waveform_capture;
    initial begin
        $dumpfile("../Testing/datapath.vcd");
        $dumpvars(1, datapath_tb.CPU);
        $dumpvars(0, datapath_tb.clk, datapath_tb.reset);
    end
endmodule
