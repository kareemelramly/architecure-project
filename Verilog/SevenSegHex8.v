/*******************************************************************************
 * Module: SevenSegHex8.v
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Eight-digit hexadecimal display driver. Active-low anodes and
 *              segments (same polarity as Four_Digit_Seven_Segment_Driver_
 *              Optimized.v). Digit 0 is the least significant nibble.
 *              dpOn lights all decimal points (used as the halt indicator).
 *
 * Change history:
 *   11/16/26 - created for the MS3 board wrapper
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module SevenSegHex8(
    input  wire        clk,
    input  wire [31:0] value,
    input  wire        dpOn,
    output reg  [7:0]  Anode,
    output reg  [6:0]  LED_out,
    output wire        dp
);
    reg [19:0] refresh = 20'd0;
    always @(posedge clk) refresh <= refresh + 1'b1;

    wire [2:0] sel = refresh[19:17];
    reg  [3:0] nib;

    always @(*) begin
        Anode = 8'b1111_1111;
        Anode[sel] = 1'b0;
        nib = value[sel*4 +: 4];
        case (nib)
            4'h0: LED_out = 7'b0000001;
            4'h1: LED_out = 7'b1001111;
            4'h2: LED_out = 7'b0010010;
            4'h3: LED_out = 7'b0000110;
            4'h4: LED_out = 7'b1001100;
            4'h5: LED_out = 7'b0100100;
            4'h6: LED_out = 7'b0100000;
            4'h7: LED_out = 7'b0001111;
            4'h8: LED_out = 7'b0000000;
            4'h9: LED_out = 7'b0000100;
            4'hA: LED_out = 7'b0001000;
            4'hB: LED_out = 7'b1100000;
            4'hC: LED_out = 7'b0110001;
            4'hD: LED_out = 7'b1000010;
            4'hE: LED_out = 7'b0110000;
            default: LED_out = 7'b0111000;
        endcase
    end
    assign dp = ~dpOn;
endmodule

`default_nettype wire
