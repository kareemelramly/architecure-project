`timescale 1ns / 1ps

module datapath_tb();
    reg clk;
    reg reset;

    datapath CPU(
        .clk(clk),
        .reset(reset)
    );

    // 20ns clock period
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        reset = 1;
        #20;
        reset = 0;

        $display("Running full instruction set validation...");
        
        // Wait 40 clock cycles to ensure all instructions complete
        #800; 

        $display("===============================================================");
        $display("                     FINAL VALIDATION RESULTS                  ");
        $display("===============================================================");

        // Verify Arithmetic (ADD / SUB / OR / AND)
        if (CPU.DataMemory.mem[4] === 32'd30 && CPU.DataMemory.mem[5] === 32'd10)
            $display(" [PASS] ALU (ADD/SUB/AND/OR): Validated");
        else
            $display(" [FAIL] ALU (ADD/SUB/AND/OR): mem[4]=%0d, mem[5]=%0d (Expected: 30, 10)", CPU.DataMemory.mem[4], CPU.DataMemory.mem[5]);

        // Verify U-Type Instructions
        if (CPU.DataMemory.mem[6] === 32'h12345000)
            $display(" [PASS] LUI: Validated (0x12345000)");
        else
            $display(" [FAIL] LUI: 0x%08h (Expected: 0x12345000)", CPU.DataMemory.mem[6]);

        if (CPU.DataMemory.mem[7] === 32'h00002050)
            $display(" [PASS] AUIPC: Validated (0x00002050)");
        else
            $display(" [FAIL] AUIPC: 0x%08h (Expected: 0x00002050)", CPU.DataMemory.mem[7]);

        // Verify Jumps & Links
        if (CPU.DataMemory.mem[8] === 32'd88)
            $display(" [PASS] JAL: Link Validated (88)");
        else
            $display(" [FAIL] JAL: %0d (Expected: 88)", CPU.DataMemory.mem[8]);

        if (CPU.DataMemory.mem[9] === 32'd100)
            $display(" [PASS] JALR: Link Validated (100)");
        else
            $display(" [FAIL] JALR: %0d (Expected: 100)", CPU.DataMemory.mem[9]);

        // Verify Conditional Branches (Error Count Check)
        if (CPU.DataMemory.mem[10] === 32'd0)
            $display(" [PASS] BRANCHES: All branches correctly taken, 0 traps hit");
        else
            $display(" [FAIL] BRANCHES: Traps triggered. Error Count: %0d", CPU.DataMemory.mem[10]);

        $display("===============================================================");
        $finish;
    end
endmodule