/*******************************************************************************
 * Module: RegFile.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: 32x32-bit Register File with x0 hardwired to zero.
 *
 * Change history:
 *   10/26/26 - Initial register file implementation
 *   11/01/26 - Ensured x0 is strictly hardwired to zero on reads and writes
 ******************************************************************************/

`timescale 1ns / 1ps

module RegFile #(
    parameter N = 32
)(
    input         clk,
    input         rst,
    input         regwrite,
    input  [4:0]  readreg1,
    input  [4:0]  readreg2,
    input  [4:0]  writereg,
    input  [N-1:0] writedata,
    output [N-1:0] readdata1,
    output [N-1:0] readdata2
);

    wire [N-1:0] d_reg [0:31];
    wire [31:0]  choice;
    genvar i;

    Nbit_decoder #(5) uut_dec(
        .in(writereg),
        .out(choice)
    );

    assign d_reg[0] = {N{1'b0}};

    generate
        for (i = 1; i < 32; i = i + 1) begin: Gen_Regs
            wire reg_load;
            assign reg_load = regwrite & choice[i];

            N_bit_register #(N) u_reg(
                .clk(clk),
                .rst(rst),
                .Load(reg_load),
                .D(writedata),
                .Q(d_reg[i])
            );
        end
    endgenerate

    assign readdata1 = (readreg1 == 5'd0) ? {N{1'b0}} : d_reg[readreg1];
    assign readdata2 = (readreg2 == 5'd0) ? {N{1'b0}} : d_reg[readreg2];

endmodule