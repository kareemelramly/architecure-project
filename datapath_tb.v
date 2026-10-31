`timescale 1ns / 1ps

module datapath_tb();
    reg clk;
    reg reset;
    integer errors;
    integer cycles;
    // RV32I: LUI/AUIPC/JAL/JALR [0:3], branches [4:9], loads [10:14],
    // stores [15:17], OP-IMM [18:26], OP [27:36], FENCE/ECALL/EBREAK [37:39].
    // RV32M [40:47]: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU (index 40 + funct3).
    reg [47:0] covered;
    reg monitor_program;
    integer word_index;
    integer coverage_index;
    reg [31:0] expected_pc;
    reg [31:0] expected_result;
    reg [511:0] instruction_name;
    reg [31:0] lb_x6, lb_x7, slt_x20, sltu_x22, slti_x1;

    datapath CPU(clk, reset);

    // Standalone control_unit instance used to decode ECALL / EBREAK / FENCE / FENCE.TSO / PAUSE directly
    reg  [31:0] cu_inst;
    wire cu_branch, cu_memRead, cu_memWrite, cu_ALUsource, cu_ALUSrcA, cu_regWrite, cu_halt;
    wire cu_isJal, cu_isJalr;
    wire [1:0] cu_memToReg, cu_aluOp;
    control_unit CU_CHECK(
        .inst(cu_inst), .branch(cu_branch), .memRead(cu_memRead), .memToReg(cu_memToReg),
        .memWrite(cu_memWrite), .ALUsource(cu_ALUsource), .ALUSrcA(cu_ALUSrcA), .regWrite(cu_regWrite),
        .aluOp(cu_aluOp), .isJal(cu_isJal), .isJalr(cu_isJalr), .halt(cu_halt)
    );

    // 20ns clock period
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Compare a 32-bit value against its expected value
    task check;
        input [511:0] name;
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
        input [511:0] name;
        input [31:0] inst;
        input expected_halt;
        begin
            cu_inst = inst;
            #1;
            if ({cu_branch, cu_memRead, cu_memToReg, cu_memWrite, cu_ALUsource, cu_ALUSrcA, cu_regWrite, cu_isJal, cu_isJalr} !== 10'b0000000000 ||
                cu_halt !== expected_halt) begin
                errors = errors + 1;
                $display("  [FAIL] %0s decode : ctrl=%b halt=%b (expected halt=%b)", name,
                         {cu_branch, cu_memRead, cu_memToReg, cu_memWrite, cu_ALUsource, cu_ALUSrcA, cu_regWrite, cu_isJal, cu_isJalr}, cu_halt, expected_halt);
            end else
                $display("  [ OK ] %0s decode : no reg/mem/branch side effects, halt=%b", name, cu_halt);
        end
    endtask

    initial begin
        errors = 0;
        cycles = 0;
        covered = 48'b0;
        monitor_program = 1;

        // Apply reset
        reset = 1;
        #20;
        reset = 0;

        $display("=====================================================================================");
        $display("Time | PC (Byte) | WordIdx | Instruction | Funct3 | MemRd | MemWr | Halt | AluOutput");
        $display("=====================================================================================");

        // Run until ECALL halts the PC (timeout of 250 cycles leaves room for the RV32I program + the RV32M block)
        while (!CPU.halt && cycles < 250) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        check("ECALL halt before timeout", {31'b0, CPU.halt}, 32'd1);
        if (CPU.halt && CPU.inst_memory_out == 32'h00000073)
            covered[38] = 1'b1;

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
        check("slt  x20 (-5 < 10 signed)",    slt_x20, 32'd1);
        check("sltu x21 (0xFFFFFFFB < 10)",   CPU.RegisterFile.D[21], 32'd0);
        check("sltu x22 (10 < 0xFFFFFFFB)",   sltu_x22, 32'd1);
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
        check("slti  x1 (10 < -5 signed)",    slti_x1,  32'd0);
        check("sltiu x2 (-5 < 10 unsigned)",  CPU.RegisterFile.D[2],  32'd0);
        check("srli  x3 (-5 >> 4 logical)",   CPU.RegisterFile.D[3],  32'h0FFFFFFF);
        check("srai  x4 (0 >>> 2)",           CPU.RegisterFile.D[4],  32'd0);
        check("lui   x5 (0x12345 << 12)",     CPU.RegisterFile.D[5],  32'h12345000);
        check("auipc x6 (PC + 0x2000)",       CPU.RegisterFile.D[6],  32'h0000210C); // PC=268 + 0x2000
        check("jalr  x7 link register",       CPU.RegisterFile.D[7],  32'd276);      // PC + 4 (mem[68] -> 272 + 4)

        $display("--- Additional R-Type / JAL Tests ---");
        check("sub x18 (15 - 7)", CPU.RegisterFile.D[18], 32'd8);
        check("and x22 (15 & 7)", CPU.RegisterFile.D[22], 32'd7);
        check("or x20 (15 | 7)", CPU.RegisterFile.D[20], 32'd15);
        check("jal x1 link register", CPU.RegisterFile.D[1], 32'd292);
        check("jal x0 keeps x0 zero", CPU.RegisterFile.D[0], 32'd0);

        $display("--- ECALL / Execution Bounds ---");
        check("PC frozen on ECALL (byte 468)",          CPU.pcValue,            32'd468);
        check("add after ECALL not executed (x18 = 8)", CPU.RegisterFile.D[18], 32'd8);
        check("x0 still zero",                          CPU.RegisterFile.D[0],  32'd0);

        $display("--- Control unit decode ---");
        check_nop_decode("FENCE",     32'h0FF0000F, 1'b0);
        check_nop_decode("FENCE.TSO", 32'h8330000F, 1'b0);
        check_nop_decode("PAUSE",     32'h0100000F, 1'b0);
        check_nop_decode("ECALL",     32'h00000073, 1'b1);
        check_nop_decode("EBREAK",    32'h00100073, 1'b1);
        check_nop_decode("CSRRW (not ECALL/EBREAK)", 32'h30051073, 1'b0);

        // Run EBREAK separately because ECALL already stopped the main program.
        monitor_program = 0;
        @(negedge clk);
        reset = 1;
        CPU.InstructionMemory.mem[0] = 32'h00100073;
        #1;
        @(negedge clk);
        reset = 0;
        repeat (5) @(posedge clk);
        #1;
        check("EBREAK halt", {31'b0, CPU.halt}, 32'd1);
        check("PC frozen on EBREAK", CPU.pcValue, 32'd0);
        check("EBREAK has no register write", CPU.RegisterFile.D[1], 32'd0);
        covered[39] = 1'b1;
        check("RV32I coverage [31:0]", covered[31:0], 32'hFFFFFFFF);
        check("RV32I coverage [39:32]", {24'b0, covered[39:32]}, 32'h000000FF);
        check("RV32M coverage [47:40]", {24'b0, covered[47:40]}, 32'h000000FF);

        $display("=====================================================================================");
        if (errors == 0)
            $display(">>> SIMULATION PASSED: All 40 RV32I + 8 RV32M instructions checked! <<<");
        else
            $display(">>> SIMULATION FAILED: %0d check(s) failed, check waveform! <<<", errors);
        $display("=====================================================================================");

        if (errors != 0)
            $fatal(1, "Datapath checks failed");
        $finish;
    end

    // Check every executed command after its register/memory/PC updates settle.
    always @(posedge clk) begin
        if (!reset && monitor_program && !CPU.halt) begin
            word_index = CPU.pcValue[8:2];
            expected_pc = CPU.pcValue + 32'd4;
            expected_result = 32'd0;
            coverage_index = -1;
            instruction_name = "Unexpected instruction";
            case (word_index)
                0: begin instruction_name = "lw x1, 0(x0) next PC"; coverage_index = 12; expected_result = 32'h0000000A; end
                1: begin instruction_name = "lw x2, 4(x0) next PC"; coverage_index = 12; expected_result = 32'h00000014; end
                2: begin instruction_name = "lw x3, 8(x0) next PC"; coverage_index = 12; expected_result = 32'hFFFFFFFB; end
                3: begin instruction_name = "add clear score/trap next PC"; coverage_index = 27; expected_result = 32'h00000000; end
                4: begin instruction_name = "add clear score/trap next PC"; coverage_index = 27; expected_result = 32'h00000000; end
                5: begin instruction_name = "beq taken next PC"; coverage_index = 4; expected_pc = 32'd28; end
                7: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h0000000A; end
                8: begin instruction_name = "bne taken next PC"; coverage_index = 5; expected_pc = 32'd40; end
                10: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h00000014; end
                11: begin instruction_name = "blt taken next PC"; coverage_index = 6; expected_pc = 32'd52; end
                13: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h0000001E; end
                14: begin instruction_name = "bge taken next PC"; coverage_index = 7; expected_pc = 32'd64; end
                16: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h00000028; end
                17: begin instruction_name = "bltu taken next PC"; coverage_index = 8; expected_pc = 32'd76; end
                19: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h00000032; end
                20: begin instruction_name = "bgeu taken next PC"; coverage_index = 9; expected_pc = 32'd88; end
                22: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h0000003C; end
                23: begin instruction_name = "bltu not taken next PC"; coverage_index = 8; end
                24: begin instruction_name = "add branch pass score next PC"; coverage_index = 27; expected_result = 32'h00000046; end
                25: begin instruction_name = "sw pass score next PC"; coverage_index = 17; expected_result = 32'h00000046; end
                26: begin instruction_name = "sw trap count next PC"; coverage_index = 17; expected_result = 32'h00000000; end
                27: begin instruction_name = "lb negative byte next PC"; coverage_index = 10; expected_result = 32'hFFFFFFB2; end
                28: begin instruction_name = "lb positive byte next PC"; coverage_index = 10; expected_result = 32'h0000007C; end
                29: begin instruction_name = "lbu byte 0 next PC"; coverage_index = 13; expected_result = 32'h000000B2; end
                30: begin instruction_name = "lbu byte 1 next PC"; coverage_index = 13; expected_result = 32'h000000F1; end
                31: begin instruction_name = "lh negative half next PC"; coverage_index = 11; expected_result = 32'hFFFFF1B2; end
                32: begin instruction_name = "lh positive half next PC"; coverage_index = 11; expected_result = 32'h00007C8A; end
                33: begin instruction_name = "lhu half 0 next PC"; coverage_index = 14; expected_result = 32'h0000F1B2; end
                34: begin instruction_name = "lhu half 1 next PC"; coverage_index = 14; expected_result = 32'h00007C8A; end
                35: begin instruction_name = "sb byte 0 next PC"; coverage_index = 15; expected_result = 32'h0000000A; end
                36: begin instruction_name = "sb byte 1 next PC"; coverage_index = 15; expected_result = 32'h0000140A; end
                37: begin instruction_name = "sb byte 2 next PC"; coverage_index = 15; expected_result = 32'h00FB140A; end
                38: begin instruction_name = "sb byte 3 next PC"; coverage_index = 15; expected_result = 32'h0AFB140A; end
                39: begin instruction_name = "sh half 0 next PC"; coverage_index = 16; expected_result = 32'h0000FFFB; end
                40: begin instruction_name = "sh half 1 next PC"; coverage_index = 16; expected_result = 32'h0014FFFB; end
                41: begin instruction_name = "lw sb result next PC"; coverage_index = 12; expected_result = 32'h0AFB140A; end
                42: begin instruction_name = "lw sh result next PC"; coverage_index = 12; expected_result = 32'h0014FFFB; end
                43: begin instruction_name = "FENCE next PC"; coverage_index = 37; end
                44: begin instruction_name = "FENCE.TSO next PC"; coverage_index = 37; end
                45: begin instruction_name = "PAUSE next PC"; coverage_index = 37; end
                46: begin instruction_name = "add x16, x1, x2 next PC"; coverage_index = 27; expected_result = 32'h0000001E; end
                47: begin instruction_name = "sw x16, 32(x0) next PC"; coverage_index = 17; expected_result = 32'h0000001E; end
                48: begin instruction_name = "xor next PC"; coverage_index = 31; expected_result = 32'h0000001E; end
                49: begin instruction_name = "sll next PC"; coverage_index = 29; expected_result = 32'h00A00000; end
                50: begin instruction_name = "slt next PC"; coverage_index = 30; expected_result = 32'h00000001; end
                51: begin instruction_name = "sltu false next PC"; coverage_index = 32; expected_result = 32'h00000000; end
                52: begin instruction_name = "srl next PC"; coverage_index = 33; expected_result = 32'h003FFFFF; end
                53: begin instruction_name = "sra next PC"; coverage_index = 34; expected_result = 32'hFFFFFFFF; end
                54: begin instruction_name = "sltu true next PC"; coverage_index = 32; expected_result = 32'h00000001; end
                55: begin instruction_name = "addi positive next PC"; coverage_index = 18; expected_result = 32'h0000000F; end
                56: begin instruction_name = "addi negative next PC"; coverage_index = 18; expected_result = 32'h00000007; end
                57: begin instruction_name = "xori next PC"; coverage_index = 22; expected_result = 32'h00000005; end
                58: begin instruction_name = "andi next PC"; coverage_index = 26; expected_result = 32'h00000002; end
                59: begin instruction_name = "ori next PC"; coverage_index = 25; expected_result = 32'h0000000E; end
                60: begin instruction_name = "slli by 4 next PC"; coverage_index = 19; expected_result = 32'h000000A0; end
                61: begin instruction_name = "slli by 31 next PC"; coverage_index = 19; expected_result = 32'h80000000; end
                62: begin instruction_name = "slti next PC"; coverage_index = 20; expected_result = 32'h00000000; end
                63: begin instruction_name = "sltiu next PC"; coverage_index = 21; expected_result = 32'h00000000; end
                64: begin instruction_name = "srli next PC"; coverage_index = 23; expected_result = 32'h0FFFFFFF; end
                65: begin instruction_name = "srai next PC"; coverage_index = 24; expected_result = 32'h00000000; end
                66: begin instruction_name = "lui next PC"; coverage_index = 0; expected_result = 32'h12345000; end
                67: begin instruction_name = "auipc next PC"; coverage_index = 1; expected_result = 32'h0000210C; end
                68: begin instruction_name = "jalr next PC"; coverage_index = 3; expected_result = 32'h00000114; end
                69: begin instruction_name = "sub next PC"; coverage_index = 28; expected_result = 32'h00000008; end
                70: begin instruction_name = "and next PC"; coverage_index = 36; expected_result = 32'h00000007; end
                71: begin instruction_name = "or next PC"; coverage_index = 35; expected_result = 32'h0000000F; end
                72: begin instruction_name = "jal link and skip next PC"; coverage_index = 2; expected_result = 32'h00000124; expected_pc = 32'd296; end
                74: begin instruction_name = "jal x0 skip next PC"; coverage_index = 2; expected_result = 32'h00000000; expected_pc = 32'd300; end
                // ---- RV32M block (mem[75]..mem[116]) ----
                75: begin instruction_name = "addi x2 (A) next PC"; coverage_index = -1; expected_result = 32'hFFFFFFFF; end
                76: begin instruction_name = "addi x4 (B) next PC"; coverage_index = -1; expected_result = 32'hFFFFFFFF; end
                77: begin instruction_name = "mul (-1,-1) next PC"; coverage_index = 40; expected_result = 32'h00000001; end
                78: begin instruction_name = "mulh (-1,-1) next PC"; coverage_index = 41; expected_result = 32'h00000000; end
                79: begin instruction_name = "mulhsu (-1,-1) next PC"; coverage_index = 42; expected_result = 32'hFFFFFFFF; end
                80: begin instruction_name = "mulhu (-1,-1) next PC"; coverage_index = 43; expected_result = 32'hFFFFFFFE; end
                81: begin instruction_name = "div (-1,-1) next PC"; coverage_index = 44; expected_result = 32'h00000001; end
                82: begin instruction_name = "divu (-1,-1) next PC"; coverage_index = 45; expected_result = 32'h00000001; end
                83: begin instruction_name = "rem (-1,-1) next PC"; coverage_index = 46; expected_result = 32'h00000000; end
                84: begin instruction_name = "remu (-1,-1) next PC"; coverage_index = 47; expected_result = 32'h00000000; end
                85: begin instruction_name = "addi x2 (A) next PC"; coverage_index = -1; expected_result = 32'hFFFFFFEC; end
                86: begin instruction_name = "addi x4 (B) next PC"; coverage_index = -1; expected_result = 32'h00000007; end
                87: begin instruction_name = "mul (-20,7) next PC"; coverage_index = 40; expected_result = 32'hFFFFFF74; end
                88: begin instruction_name = "mulh (-20,7) next PC"; coverage_index = 41; expected_result = 32'hFFFFFFFF; end
                89: begin instruction_name = "mulhsu (-20,7) next PC"; coverage_index = 42; expected_result = 32'hFFFFFFFF; end
                90: begin instruction_name = "mulhu (-20,7) next PC"; coverage_index = 43; expected_result = 32'h00000006; end
                91: begin instruction_name = "div (-20,7) next PC"; coverage_index = 44; expected_result = 32'hFFFFFFFE; end
                92: begin instruction_name = "divu (-20,7) next PC"; coverage_index = 45; expected_result = 32'h24924921; end
                93: begin instruction_name = "rem (-20,7) next PC"; coverage_index = 46; expected_result = 32'hFFFFFFFA; end
                94: begin instruction_name = "remu (-20,7) next PC"; coverage_index = 47; expected_result = 32'h00000005; end
                95: begin instruction_name = "addi x4 (B) next PC"; coverage_index = -1; expected_result = 32'h00000000; end
                96: begin instruction_name = "mul (-20,0) next PC"; coverage_index = 40; expected_result = 32'h00000000; end
                97: begin instruction_name = "mulh (-20,0) next PC"; coverage_index = 41; expected_result = 32'h00000000; end
                98: begin instruction_name = "mulhsu (-20,0) next PC"; coverage_index = 42; expected_result = 32'h00000000; end
                99: begin instruction_name = "mulhu (-20,0) next PC"; coverage_index = 43; expected_result = 32'h00000000; end
                100: begin instruction_name = "div (-20,0) next PC"; coverage_index = 44; expected_result = 32'hFFFFFFFF; end
                101: begin instruction_name = "divu (-20,0) next PC"; coverage_index = 45; expected_result = 32'hFFFFFFFF; end
                102: begin instruction_name = "rem (-20,0) next PC"; coverage_index = 46; expected_result = 32'hFFFFFFEC; end
                103: begin instruction_name = "remu (-20,0) next PC"; coverage_index = 47; expected_result = 32'hFFFFFFEC; end
                104: begin instruction_name = "lui x2 (A) next PC"; coverage_index = -1; expected_result = 32'h80000000; end
                105: begin instruction_name = "addi x4 (B) next PC"; coverage_index = -1; expected_result = 32'hFFFFFFFF; end
                106: begin instruction_name = "mul (INT_MIN,-1) next PC"; coverage_index = 40; expected_result = 32'h80000000; end
                107: begin instruction_name = "mulh (INT_MIN,-1) next PC"; coverage_index = 41; expected_result = 32'h00000000; end
                108: begin instruction_name = "mulhsu (INT_MIN,-1) next PC"; coverage_index = 42; expected_result = 32'h80000000; end
                109: begin instruction_name = "mulhu (INT_MIN,-1) next PC"; coverage_index = 43; expected_result = 32'h7FFFFFFF; end
                110: begin instruction_name = "div (INT_MIN,-1) next PC"; coverage_index = 44; expected_result = 32'h80000000; end
                111: begin instruction_name = "divu (INT_MIN,-1) next PC"; coverage_index = 45; expected_result = 32'h00000000; end
                112: begin instruction_name = "rem (INT_MIN,-1) next PC"; coverage_index = 46; expected_result = 32'h00000000; end
                113: begin instruction_name = "remu (INT_MIN,-1) next PC"; coverage_index = 47; expected_result = 32'h80000000; end
                114: begin instruction_name = "addi x2 (restore) next PC"; coverage_index = -1; expected_result = 32'h00000000; end
                115: begin instruction_name = "addi x4 (restore) next PC"; coverage_index = -1; expected_result = 32'h00000000; end
                116: begin instruction_name = "addi x21 (restore) next PC"; coverage_index = -1; expected_result = 32'h00000000; end
                default: begin
                    errors = errors + 1;
                    $display("  [FAIL] Unexpected executed word index %0d", word_index);
                end
            endcase
            #1;
            check(instruction_name, CPU.pcValue, expected_pc);
            case (word_index)
                0: check("lw x1, 0(x0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[0][11:7]], expected_result);
                1: check("lw x2, 4(x0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[1][11:7]], expected_result);
                2: check("lw x3, 8(x0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[2][11:7]], expected_result);
                3: check("add clear score/trap result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[3][11:7]], expected_result);
                4: check("add clear score/trap result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[4][11:7]], expected_result);
                7: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[7][11:7]], expected_result);
                10: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[10][11:7]], expected_result);
                13: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[13][11:7]], expected_result);
                16: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[16][11:7]], expected_result);
                19: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[19][11:7]], expected_result);
                22: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[22][11:7]], expected_result);
                24: check("add branch pass score result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[24][11:7]], expected_result);
                25: check("sw pass score result", CPU.DataMemory.mem[3], expected_result);
                26: check("sw trap count result", CPU.DataMemory.mem[4], expected_result);
                27: check("lb negative byte result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[27][11:7]], expected_result);
                28: check("lb positive byte result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[28][11:7]], expected_result);
                29: check("lbu byte 0 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[29][11:7]], expected_result);
                30: check("lbu byte 1 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[30][11:7]], expected_result);
                31: check("lh negative half result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[31][11:7]], expected_result);
                32: check("lh positive half result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[32][11:7]], expected_result);
                33: check("lhu half 0 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[33][11:7]], expected_result);
                34: check("lhu half 1 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[34][11:7]], expected_result);
                35: check("sb byte 0 result", CPU.DataMemory.mem[6], expected_result);
                36: check("sb byte 1 result", CPU.DataMemory.mem[6], expected_result);
                37: check("sb byte 2 result", CPU.DataMemory.mem[6], expected_result);
                38: check("sb byte 3 result", CPU.DataMemory.mem[6], expected_result);
                39: check("sh half 0 result", CPU.DataMemory.mem[7], expected_result);
                40: check("sh half 1 result", CPU.DataMemory.mem[7], expected_result);
                41: check("lw sb result result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[41][11:7]], expected_result);
                42: check("lw sh result result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[42][11:7]], expected_result);
                46: check("add x16, x1, x2 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[46][11:7]], expected_result);
                47: check("sw x16, 32(x0) result", CPU.DataMemory.mem[8], expected_result);
                48: check("xor result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[48][11:7]], expected_result);
                49: check("sll result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[49][11:7]], expected_result);
                50: check("slt result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[50][11:7]], expected_result);
                51: check("sltu false result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[51][11:7]], expected_result);
                52: check("srl result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[52][11:7]], expected_result);
                53: check("sra result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[53][11:7]], expected_result);
                54: check("sltu true result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[54][11:7]], expected_result);
                55: check("addi positive result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[55][11:7]], expected_result);
                56: check("addi negative result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[56][11:7]], expected_result);
                57: check("xori result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[57][11:7]], expected_result);
                58: check("andi result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[58][11:7]], expected_result);
                59: check("ori result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[59][11:7]], expected_result);
                60: check("slli by 4 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[60][11:7]], expected_result);
                61: check("slli by 31 result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[61][11:7]], expected_result);
                62: check("slti result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[62][11:7]], expected_result);
                63: check("sltiu result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[63][11:7]], expected_result);
                64: check("srli result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[64][11:7]], expected_result);
                65: check("srai result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[65][11:7]], expected_result);
                66: check("lui result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[66][11:7]], expected_result);
                67: check("auipc result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[67][11:7]], expected_result);
                68: check("jalr result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[68][11:7]], expected_result);
                69: check("sub result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[69][11:7]], expected_result);
                70: check("and result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[70][11:7]], expected_result);
                71: check("or result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[71][11:7]], expected_result);
                72: check("jal link and skip result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[72][11:7]], expected_result);
                74: check("jal x0 skip result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[74][11:7]], expected_result);
                // ---- RV32M block ----
                75: check("addi x2 (A) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[75][11:7]], expected_result);
                76: check("addi x4 (B) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[76][11:7]], expected_result);
                77: check("mul (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[77][11:7]], expected_result);
                78: check("mulh (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[78][11:7]], expected_result);
                79: check("mulhsu (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[79][11:7]], expected_result);
                80: check("mulhu (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[80][11:7]], expected_result);
                81: check("div (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[81][11:7]], expected_result);
                82: check("divu (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[82][11:7]], expected_result);
                83: check("rem (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[83][11:7]], expected_result);
                84: check("remu (-1,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[84][11:7]], expected_result);
                85: check("addi x2 (A) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[85][11:7]], expected_result);
                86: check("addi x4 (B) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[86][11:7]], expected_result);
                87: check("mul (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[87][11:7]], expected_result);
                88: check("mulh (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[88][11:7]], expected_result);
                89: check("mulhsu (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[89][11:7]], expected_result);
                90: check("mulhu (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[90][11:7]], expected_result);
                91: check("div (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[91][11:7]], expected_result);
                92: check("divu (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[92][11:7]], expected_result);
                93: check("rem (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[93][11:7]], expected_result);
                94: check("remu (-20,7) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[94][11:7]], expected_result);
                95: check("addi x4 (B) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[95][11:7]], expected_result);
                96: check("mul (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[96][11:7]], expected_result);
                97: check("mulh (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[97][11:7]], expected_result);
                98: check("mulhsu (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[98][11:7]], expected_result);
                99: check("mulhu (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[99][11:7]], expected_result);
                100: check("div (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[100][11:7]], expected_result);
                101: check("divu (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[101][11:7]], expected_result);
                102: check("rem (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[102][11:7]], expected_result);
                103: check("remu (-20,0) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[103][11:7]], expected_result);
                104: check("lui x2 (A) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[104][11:7]], expected_result);
                105: check("addi x4 (B) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[105][11:7]], expected_result);
                106: check("mul (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[106][11:7]], expected_result);
                107: check("mulh (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[107][11:7]], expected_result);
                108: check("mulhsu (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[108][11:7]], expected_result);
                109: check("mulhu (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[109][11:7]], expected_result);
                110: check("div (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[110][11:7]], expected_result);
                111: check("divu (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[111][11:7]], expected_result);
                112: check("rem (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[112][11:7]], expected_result);
                113: check("remu (INT_MIN,-1) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[113][11:7]], expected_result);
                114: check("addi x2 (restore) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[114][11:7]], expected_result);
                115: check("addi x4 (restore) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[115][11:7]], expected_result);
                116: check("addi x21 (restore) result", CPU.RegisterFile.D[CPU.InstructionMemory.mem[116][11:7]], expected_result);
            endcase
            if (coverage_index >= 0)
                covered[coverage_index] = 1'b1;
            if (word_index == 50) slt_x20 = CPU.RegisterFile.D[20];
            if (word_index == 54) sltu_x22 = CPU.RegisterFile.D[22];
            if (word_index == 62) slti_x1 = CPU.RegisterFile.D[1];
        end
    end

    // Print state at the negative edge of clk (after signals settle, before PC updates)
    always @(negedge clk) begin
        if (CPU.pcValue == 32'd116) begin   // to check for both changes to registers x6 & x7 in 2 different parts of the program
            lb_x6 = CPU.RegisterFile.D[6];
            lb_x7 = CPU.RegisterFile.D[7];
        end
        if (!reset && !CPU.halt) begin
            $display("%4t |    %3d    |   %2d    |  %h  |  %b   |   %b   |   %b   |  %b   |    %0d",
                     $time, CPU.pcValue, CPU.pcValue[8:2], CPU.inst_memory_out,
                     CPU.inst_memory_out[14:12], CPU.memRead, CPU.memWrite, CPU.halt, CPU.AluOutput);
        end
    end
endmodule