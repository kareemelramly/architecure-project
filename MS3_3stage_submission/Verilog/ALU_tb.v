/*******************************************************************************
 * Module: ALU_tb.v
 * Project: femtoRV32
 * Author: Mohamed AboElfotouh
 * Description: Self-checking testbench for ALU.v. Every operation is checked
 *              against a behavioural reference model on corner values
 *              (0, 1, -1, 0x80000000, 0x7FFFFFFF, ...) and 2000 random pairs,
 *              including RV32M division by zero and -2^31 / -1.
 *
 * Change history:
 *   11/18/26 - created
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module ALU_tb;

    reg  [4:0]  aluSel;
    reg  [31:0] in1;
    reg  [31:0] in2;
    wire [31:0] result;
    wire        zero;
    reg  [31:0] expected;
    reg  [63:0] wide;
    integer     errors;
    integer     checks;
    integer     i;
    integer     j;
    integer     k;
    reg  [31:0] corner [0:7];
    reg  [4:0]  ops [0:17];

    ALU #(32) dut(
        .aluSel(aluSel),
        .in1(in1),
        .in2(in2),
        .result(result),
        .zero(zero)
    );

    // Behavioural reference ($signed is fine in a testbench)
    task reference;
        begin
            case (aluSel)
                `ALU_ADD:  expected = in1 + in2;
                `ALU_SUB:  expected = in1 - in2;
                `ALU_AND:  expected = in1 & in2;
                `ALU_OR:   expected = in1 | in2;
                `ALU_XOR:  expected = in1 ^ in2;
                `ALU_SLL:  expected = in1 << in2[4:0];
                `ALU_SRL:  expected = in1 >> in2[4:0];
                `ALU_SRA:  expected = $signed(in1) >>> in2[4:0];
                `ALU_SLT:  expected = ($signed(in1) < $signed(in2));
                `ALU_SLTU: expected = (in1 < in2);
                `ALU_MUL: begin
                    wide = in1 * in2;
                    expected = wide[31:0];
                end
                `ALU_MULH: begin
                    wide = $signed({{32{in1[31]}}, in1}) *
                           $signed({{32{in2[31]}}, in2});
                    expected = wide[63:32];
                end
                `ALU_MULHSU: begin
                    wide = $signed({{32{in1[31]}}, in1}) *
                           $signed({32'd0, in2});
                    expected = wide[63:32];
                end
                `ALU_MULHU: begin
                    wide = {32'd0, in1} * {32'd0, in2};
                    expected = wide[63:32];
                end
                `ALU_DIV: begin
                    if (in2 == 0) expected = 32'hFFFFFFFF;
                    else if (in1 == 32'h80000000 && in2 == 32'hFFFFFFFF)
                        expected = 32'h80000000;
                    else expected = $signed(in1) / $signed(in2);
                end
                `ALU_DIVU: expected = (in2 == 0) ? 32'hFFFFFFFF : in1 / in2;
                `ALU_REM: begin
                    if (in2 == 0) expected = in1;
                    else if (in1 == 32'h80000000 && in2 == 32'hFFFFFFFF)
                        expected = 32'd0;
                    else expected = $signed(in1) % $signed(in2);
                end
                `ALU_REMU: expected = (in2 == 0) ? in1 : in1 % in2;
                default:   expected = 32'd0;
            endcase
        end
    endtask

    task check;
        begin
            #1;
            reference;
            checks = checks + 1;
            if ((result !== expected) || (zero !== (expected == 0))) begin
                errors = errors + 1;
                if (errors < 10) begin
                    $display("FAIL sel=%b in1=%h in2=%h got %h expected %h",
                             aluSel, in1, in2, result, expected);
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        corner[0] = 32'd0;          corner[1] = 32'd1;
        corner[2] = 32'hFFFFFFFF;   corner[3] = 32'h80000000;
        corner[4] = 32'h7FFFFFFF;   corner[5] = 32'd7;
        corner[6] = 32'hFFFFFFFD;   corner[7] = 32'h12345678;
        ops[0]  = `ALU_ADD;  ops[1]  = `ALU_SUB;    ops[2]  = `ALU_AND;
        ops[3]  = `ALU_OR;   ops[4]  = `ALU_XOR;    ops[5]  = `ALU_SLL;
        ops[6]  = `ALU_SRL;  ops[7]  = `ALU_SRA;    ops[8]  = `ALU_SLT;
        ops[9]  = `ALU_SLTU; ops[10] = `ALU_MUL;    ops[11] = `ALU_MULH;
        ops[12] = `ALU_MULHSU; ops[13] = `ALU_MULHU; ops[14] = `ALU_DIV;
        ops[15] = `ALU_DIVU; ops[16] = `ALU_REM;    ops[17] = `ALU_REMU;
        for (k = 0; k < 18; k = k + 1) begin
            aluSel = ops[k];
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    in1 = corner[i];
                    in2 = corner[j];
                    check;
                end
            end
            for (i = 0; i < 2000; i = i + 1) begin
                in1 = $random;
                in2 = (i % 7 == 0) ? ($random % 16) : $random;
                check;
            end
        end
        if (errors == 0) $display("PASS ALU_tb: %0d checks", checks);
        else             $display("FAIL ALU_tb: %0d of %0d checks",
                                  errors, checks);
        $finish;
    end

endmodule
