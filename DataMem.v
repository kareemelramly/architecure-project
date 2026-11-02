/*******************************************************************************
 * Module: DataMem.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Moustafa Fayed (GammaZep45), Mohamed AboElfotouh
 * Description: Byte-addressable Data Memory supporting loads/stores for
 *              byte, halfword, and full 32-bit words.
 *
 * Change history:
 *   10/26/26 - Word-aligned Data Memory
 *   10/27/26 - Added byte and halfword load/store masking
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"

module DataMem(
    input         clk,
    input         memRead,
    input         memWrite,
    input  [2:0]  funct3,
    input  [7:0]  addr,
    input  [31:0] dataIn,
    output [31:0] dataOut
);

    reg [31:0] mem [0:63];
    wire [5:0] wordAddr;
    wire [31:0] word;
    reg  [7:0]  selByte;
    reg  [15:0] selHalf;
    reg  [31:0] loadData;
    reg  [31:0] storeData;
    integer i;

    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            mem[i] = 32'd0;
        end
        mem[0] = 32'd10;
        mem[1] = 32'd20;
        mem[2] = 32'hFFFFFFFB;
        mem[5] = 32'h7C8AF1B2;
    end

    assign wordAddr = addr[7:2];
    assign word     = mem[wordAddr];

    always @* begin
        case (addr[1:0])
            2'b00:   selByte = word[7:0];
            2'b01:   selByte = word[15:8];
            2'b10:   selByte = word[23:16];
            2'b11:   selByte = word[31:24];
            default: selByte = word[7:0];
        endcase
        selHalf = (addr[1]) ? word[31:16] : word[15:0];
    end

    always @* begin
        case (funct3)
            `MEM_LB:  loadData = {{24{selByte[7]}}, selByte};
            `MEM_LH:  loadData = {{16{selHalf[15]}}, selHalf};
            `MEM_LBU: loadData = {24'b0, selByte};
            `MEM_LHU: loadData = {16'b0, selHalf};
            default:  loadData = word;
        endcase
    end

    always @* begin
        case (funct3[1:0])
            2'b00: begin
                case (addr[1:0])
                    2'b00: storeData = {word[31:8], dataIn[7:0]};
                    2'b01: storeData = {word[31:16], dataIn[7:0], word[7:0]};
                    2'b10: storeData = {word[31:24], dataIn[7:0], word[15:0]};
                    2'b11: storeData = {dataIn[7:0], word[23:0]};
                    default: storeData = word;
                endcase
            end
            2'b01: begin
                storeData = (addr[1]) ? {dataIn[15:0], word[15:0]} :
                                        {word[31:16], dataIn[15:0]};
            end
            default: begin
                storeData = dataIn;
            end
        endcase
    end

    always @(posedge clk) begin
        if (memWrite) begin
            mem[wordAddr] <= storeData;
        end
    end

    assign dataOut = (memRead) ? loadData : 32'd0;

endmodule