`timescale 1ns / 1ps

module datapath_tb();
    reg clk;
    reg reset;

    datapath CPU(clk, reset);

    // 20ns clock period
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        // Apply reset
        reset = 1;
        #20;
        reset = 0;

        $display("======================================================================");
        $display("Time | PC (Byte) | WordIdx | Funct3 | Branch | TakeBranch | AluOutput");
        $display("======================================================================");

        // Run for 25 clock cycles (500 ns) to complete all instructions
        #500;

        $display("======================================================================");
        $display("Final Pass Score (DataMem[3], Expected 70) : %0d", CPU.DataMemory.mem[3]);
        $display("Final Trap Count (DataMem[4], Expected 0)  : %0d", CPU.DataMemory.mem[4]);

        if (CPU.DataMemory.mem[3] == 32'd70 && CPU.DataMemory.mem[4] == 32'd0)
            $display(">>> SIMULATION PASSED: All 6 branch types (BEQ, BNE, BLT, BGE, BLTU, BGEU) work! <<<");
        else
            $display(">>> SIMULATION FAILED: Check waveform! <<<");
        $display("======================================================================");

        $finish;
    end

    // Print state at the negative edge of clk (after signals settle, before PC updates)
    always @(negedge clk) begin
        if (!reset) begin
            $display("%4t |    %3d    |   %2d    |  %b   |   %b    |     %b      |    %0d",
                     $time, CPU.pcValue, CPU.pcValue[7:2],
                     CPU.inst_memory_out[14:12], CPU.branch, CPU.takeBranch, CPU.AluOutput);
        end
    end
endmodule