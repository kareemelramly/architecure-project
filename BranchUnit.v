`timescale 1ns / 1ps

module BranchUnit(
    input branch,               // From control_unit (1 when opcode is B-type 1100011)
    input [2:0] funct3,         // inst_memory_out[14:12]
    input [31:0] readData1,     // rs1 value from RegFile
    input [31:0] readData2,     // rs2 value from RegFile
    output reg takeBranch       // Replaces (branch & AluZero) in datapath
);

    always @(*) begin
        if (branch) begin
            case (funct3)
                3'b000: takeBranch = (readData1 == readData2);                   // BEQ
                3'b001: takeBranch = (readData1 != readData2);                   // BNE
                3'b100: takeBranch = ($signed(readData1) < $signed(readData2));  // BLT
                3'b101: takeBranch = ($signed(readData1) >= $signed(readData2)); // BGE
                3'b110: takeBranch = (readData1 < readData2);                    // BLTU
                3'b111: takeBranch = (readData1 >= readData2);                   // BGEU
                default: takeBranch = 1'b0;
            endcase
        end else begin
            takeBranch = 1'b0;
        end
    end

endmodule