`timescale 1ns / 1ps

module datapath_tb();
    reg clk;
    reg reset;
    integer errors;
    integer cycles;
    reg [31:0] lb_x6, lb_x7;

    datapath CPU(clk, reset);

    // Standalone control_unit instance used to decode ECALL / EBREAK / FENCE / FENCE.TSO / PAUSE directly
    reg  [31:0] cu_inst;
    wire cu_branch, cu_memRead, cu_memToReg, cu_memWrite, cu_ALUsource, cu_regWrite, cu_halt;
    wire [1:0] cu_memToReg;
    control_unit CU_CHECK(
        .inst(cu_inst), .branch(cu_branch), .memRead(cu_memRead), .memToReg(cu_memToReg),
        .memWrite(cu_memWrite), .ALUsource(cu_ALUsource), .ALUSrcA(), .regWrite(cu_regWrite),
        .aluOp(cu_aluOp), .isJal(), .isJalr(), .halt(cu_halt)
    );

    // 20ns clock period
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Compare a 32-bit value against its expected value
    task check;
        input [255:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got 0x%h (%0d), expected 0x%h (%0d)", name, actual, $signed(actual), expected, $signed(expected));
            end else
                $display("  [ OK ] %0s : 0x%h (%0d)", name, actual, $signed(actual));
        end
    endtask

    // Decode one instruction in the standalone control unit and check that it has no side effects
    task check_nop_decode;
        input [255:0] name;
        input [31:0] inst;
        input expected_halt;
        begin
            cu_inst = inst;
            #1;
            if ({cu_branch, cu_memRead, cu_memToReg, cu_memWrite, cu_ALUsource, cu_regWrite} !== 6'b000000 ||
                cu_halt !== expected_halt) begin
                errors = errors + 1;
                $display("  [FAIL] %0s decode : ctrl=%b halt=%b (expected halt=%b)", name,
                         {cu_branch, cu_memRead, cu_memToReg, cu_memWrite, cu_ALUsource, cu_regWrite}, cu_halt, expected_halt);
            end else
                $display("  [ OK ] %0s decode : no reg/mem/branch side effects, halt=%b", name, cu_halt);
        end
    endtask

    initial begin
        errors = 0;
        cycles = 0;

        // Apply reset
        reset = 1;
        #20;
        reset = 0;

        $display("=====================================================================================");
        $display("Time | PC (Byte) | WordIdx | Instruction | Funct3 | MemRd | MemWr | Halt | AluOutput");
        $display("=====================================================================================");

        // Run until ECALL halts the PC (increased timeout to 120 cycles to accommodate added instructions)
        while (!CPU.halt && cycles < 120) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        // Let the clock keep running to prove that the PC really stays frozen on the ECALL
        repeat (5) @(posedge clk);
        #1;

        $display("=====================================================================================");
        $display("Cycles until halt : %0d", cycles);
        $display("--- Branch tests ---");
        check("Pass Score (DataMem[3], Expected 70)", CPU.DataMemory.mem[3], 32'd70);
        check("Trap Count (DataMem[4], Expected 0)",  CPU.DataMemory.mem[4], 32'd0);

        $display("--- LB / LBU / LH / LHU ---");
        check("lb  x6  (byte 0 = 0xB2)", lb_x6, 32'hFFFFFFB2);
        check("lb  x7  (byte 3 = 0x7C)", lb_x7, 32'h0000007C);
        check("lbu x8  (byte 0 = 0xB2)",   CPU.RegisterFile.D[8],  32'h000000B2);
        check("lbu x9  (byte 1 = 0xF1)",   CPU.RegisterFile.D[9],  32'h000000F1);
        check("lh  x10 (half 0 = 0xF1B2)", CPU.RegisterFile.D[10], 32'hFFFFF1B2);
        check("lh  x11 (half 1 = 0x7C8A)", CPU.RegisterFile.D[11], 32'h00007C8A);
        check("lhu x12 (half 0 = 0xF1B2)", CPU.RegisterFile.D[12], 32'h0000F1B2);
        check("lhu x13 (half 1 = 0x7C8A)", CPU.RegisterFile.D[13], 32'h00007C8A);

        $display("--- SB / SH ---");
        check("DataMem[6] after 4x sb",    CPU.DataMemory.mem[6],  32'h0AFB140A);
        check("DataMem[7] after 2x sh",    CPU.DataMemory.mem[7],  32'h0014FFFB);
        check("lw x14 reads back sb word", CPU.RegisterFile.D[14], 32'h0AFB140A);
        check("lw x15 reads back sh word", CPU.RegisterFile.D[15], 32'h0014FFFB);
        check("DataMem[5] untouched",      CPU.DataMemory.mem[5],  32'h7C8AF1B2);

        $display("--- FENCE / FENCE.TSO / PAUSE ---");
        check("add after fences (x16 = 30)",  CPU.RegisterFile.D[16], 32'd30);
        check("sw x16 (DataMem[8] = 30)",     CPU.DataMemory.mem[8],  32'd30);
        check("xor execution (x17 = 30)",     CPU.RegisterFile.D[17], 32'd30);
        
        $display("--- R-Type Operations ---");
        check("sll  x19 (10 << 20)",          CPU.RegisterFile.D[19], 32'h00A00000);
        check("slt  x20 (-5 < 10 signed)",    CPU.RegisterFile.D[20], 32'd1);
        check("sltu x21 (0xFFFFFFFB < 10)",   CPU.RegisterFile.D[21], 32'd0);
        check("sltu x22 (10 < 0xFFFFFFFB)",   CPU.RegisterFile.D[22], 32'd1);
        check("srl  x23 (logical >> 10)",     CPU.RegisterFile.D[23], 32'h003FFFFF);
        check("sra  x24 (arithmetic >>> 10)", CPU.RegisterFile.D[24], 32'hFFFFFFFF);
        
        $display("--- OP-IMM (I-Type Arithmetic / Logical / Immediate Shifts) ---");
        check("addi x25 (10 + 5)",           CPU.RegisterFile.D[25], 32'd15);
        check("addi x26 (10 + -3)",          CPU.RegisterFile.D[26], 32'd7);
        check("xori x27 (10 ^ 15)",          CPU.RegisterFile.D[27], 32'd5);
        check("andi x28 (10 & 6)",           CPU.RegisterFile.D[28], 32'd2);
        check("ori  x30 (10 | 6)",           CPU.RegisterFile.D[30], 32'd14);
        check("slli x29 (10 << 4)",          CPU.RegisterFile.D[29], 32'h000000A0);
        check("slli x31 (-5 << 31)",         CPU.RegisterFile.D[31], 32'h80000000);

        $display("--- Appended I-Type / Upper-Immediate / JALR Tests ---");
        check("slti  x1 (10 < -5 signed)",    CPU.RegisterFile.D[1],  32'd0);
        check("sltiu x2 (-5 < 10 unsigned)",  CPU.RegisterFile.D[2],  32'd0);
        check("srli  x3 (-5 >> 4 logical)",   CPU.RegisterFile.D[3],  32'h0FFFFFFF);
        check("srai  x4 (0 >>> 2)",           CPU.RegisterFile.D[4],  32'd0);
        check("lui   x5 (0x12345 << 12)",     CPU.RegisterFile.D[5],  32'h12345000);
        check("auipc x6 (PC + 0x2000)",       CPU.RegisterFile.D[6],  32'h0000210C); // PC=268 + 0x2000
        check("jalr  x7 link register",       CPU.RegisterFile.D[7],  32'd276);      // PC + 4 (mem[68] -> 272 + 4)

        $display("--- ECALL / Execution Bounds ---");
        check("PC frozen on ECALL (byte 276)",          CPU.pcValue,            32'd276);
        check("add after ECALL not executed (x18 = 0)", CPU.RegisterFile.D[18], 32'd0);
        check("x0 still zero",                          CPU.RegisterFile.D[0],  32'd0);

        $display("--- Control unit decode ---");
        check_nop_decode("FENCE",     32'h0FF0000F, 1'b0);
        check_nop_decode("FENCE.TSO", 32'h8330000F, 1'b0);
        check_nop_decode("PAUSE",     32'h0100000F, 1'b0);
        check_nop_decode("ECALL",     32'h00000073, 1'b1);
        check_nop_decode("EBREAK",    32'h00100073, 1'b1);
        check_nop_decode("CSRRW (not ECALL/EBREAK)", 32'h30051073, 1'b0);

        $display("=====================================================================================");
        if (errors == 0)
            $display(">>> SIMULATION PASSED: All branches, loads/stores, R-type, and I-type instructions work! <<<");
        else
            $display(">>> SIMULATION FAILED: %0d check(s) failed, check waveform! <<<", errors);
        $display("=====================================================================================");

        $finish;
    end

    // Print state at the negative edge of clk (after signals settle, before PC updates)
    always @(negedge clk) begin
        if (CPU.pcValue == 32'd116) begin   // to check for both changes to registers x6 & x7 in 2 different parts of the program
            lb_x6 = CPU.RegisterFile.D[6];
            lb_x7 = CPU.RegisterFile.D[7];
        end
        if (!reset && !CPU.halt) begin
            $display("%4t |    %3d    |   %2d    |  %h  |  %b   |   %b   |   %b   |  %b   |    %0d",
                     $time, CPU.pcValue, CPU.pcValue[7:2], CPU.inst_memory_out,
                     CPU.inst_memory_out[14:12], CPU.memRead, CPU.memWrite, CPU.halt, CPU.AluOutput);
        end
    end
endmodule