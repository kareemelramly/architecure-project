`timescale 1ns / 1ps

module DataMem(
    input clk, input MemRead, input MemWrite,
    input [5:0] addr, input [31:0] data_in, output [31:0] data_out
);
    reg [31:0] mem [0:63];
    integer i;

    initial begin
        for (i = 0; i < 64; i = i + 1) mem[i] = 32'd0;
        mem[0] = 32'd10;         // Positive 10
        mem[1] = 32'd20;         // Positive 20
        mem[2] = 32'hFFFFFFFB;   // Negative -5 (Signed) / 4294967291 (Unsigned)
    end

    always @(posedge clk) begin
        if (MemWrite) mem[addr] <= data_in;
    end

    assign data_out = (MemRead) ? mem[addr] : 32'd0;
endmodule