`timescale 1ns / 1ps

module ImmGen (
    input [31:0] inst,
    output reg [31:0] gen_out
);
    wire [6:2] opcode = inst[6:2];

    always @(*) begin
        case (opcode)
            // I-type: Loads, I-ALU, JALR
            5'b00000, 5'b00100, 5'b11001: 
                gen_out = {{20{inst[31]}}, inst[31:20]};

            // S-type: Stores
            5'b01000: 
                gen_out = {{20{inst[31]}}, inst[31:25], inst[11:7]};

            // B-type: Branches (already byte-aligned with LSB = 0)
            5'b11000: 
                gen_out = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};

            // U-type: LUI, AUIPC (Upper 20 bits shifted by 12)
            5'b01101, 5'b00101: 
                gen_out = {inst[31:12], 12'b0};

            // J-type: JAL (already byte-aligned with LSB = 0)
            5'b11011: 
                gen_out = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

            default: 
                gen_out = 32'd0;
        endcase
    end
endmodule