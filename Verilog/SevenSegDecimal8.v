/*******************************************************************************
 * Module: SevenSegDecimal8.v  (contains BinToBcd8 and SevenSegDecimal8)
 * Project: femtoRV32
 * Author: Mostafa Fayed
 * Description: Eight-digit DECIMAL display driver for the Nexys A7. Same idea
 *              as the old Four_Digit_Seven_Segment_Driver_Optimized: a binary
 *              to BCD converter (shift and add-3) feeds a refresh counter that
 *              multiplexes the digits. Changes from the old driver:
 *                - 8 digits (0 to 99,999,999) instead of 4
 *                - 32-bit input; a value above 99,999,999 shows "--------"
 *                - converter is sequential (27 clocks) so the long add-3 chain
 *                  never sits in one clock path; the result is kept in a
 *                  register and only changes when the shown value changes
 *                - dpOn lights all decimal points (halt indicator)
 *                - asynchronous reset, no initial values (guidelines)
 *              Active-low anodes and segments (LED_out[6] = a ... [0] = g).
 *              Digit 0 (rightmost) is the ones digit.
 *
 * Change history:
 *   11/18/26 - created, replaces SevenSegHex8.v
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

// Binary (up to 99,999,999) to 8 BCD digits. Restarts every 28 clocks and
// copies the finished digits to bcd. tooBig is set when bin > 99,999,999.
module BinToBcd8(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] bin,
    output reg  [31:0] bcd,
    output reg         tooBig
);

    reg  [26:0] shiftBin;
    reg  [31:0] work;
    reg  [4:0]  cnt;
    // verilator lint_off UNUSEDSIGNAL
    wire [31:0] adj;                             // adj[31] is shifted out
    // verilator lint_on UNUSEDSIGNAL
    wire        big;

    assign big = (bin > 32'd99_999_999);

    // add 3 to every digit that is 5 or more (before the shift)
    assign adj[3:0]   = (work[3:0]   >= 4'd5) ? work[3:0]   + 4'd3 : work[3:0];
    assign adj[7:4]   = (work[7:4]   >= 4'd5) ? work[7:4]   + 4'd3 : work[7:4];
    assign adj[11:8]  = (work[11:8]  >= 4'd5) ? work[11:8]  + 4'd3 : work[11:8];
    assign adj[15:12] = (work[15:12] >= 4'd5) ? work[15:12] + 4'd3 : work[15:12];
    assign adj[19:16] = (work[19:16] >= 4'd5) ? work[19:16] + 4'd3 : work[19:16];
    assign adj[23:20] = (work[23:20] >= 4'd5) ? work[23:20] + 4'd3 : work[23:20];
    assign adj[27:24] = (work[27:24] >= 4'd5) ? work[27:24] + 4'd3 : work[27:24];
    assign adj[31:28] = (work[31:28] >= 4'd5) ? work[31:28] + 4'd3 : work[31:28];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            shiftBin <= 27'd0;
            work     <= 32'd0;
            cnt      <= 5'd0;
            bcd      <= 32'd0;
            tooBig   <= 1'b0;
        end else if (cnt == 5'd0) begin          // load
            shiftBin <= bin[26:0];
            work     <= 32'd0;
            cnt      <= 5'd1;
        end else if (cnt == 5'd28) begin         // publish
            bcd      <= work;
            tooBig   <= big;
            cnt      <= 5'd0;
        end else begin                           // 27 shift steps
            work     <= {adj[30:0], shiftBin[26]};
            shiftBin <= {shiftBin[25:0], 1'b0};
            cnt      <= cnt + 1'b1;
        end
    end

endmodule


module SevenSegDecimal8(
    input  wire        clk,
    input  wire        rst,
    input  wire        dpOn,
    input  wire [31:0] value,
    output reg  [7:0]  Anode,
    output reg  [6:0]  LED_out,
    output wire        dp
);

    reg  [19:0] refresh;
    wire [2:0]  sel;
    wire [31:0] digits;
    wire        tooBig;
    reg  [3:0]  nib;

    BinToBcd8 conv(
        .clk(clk),
        .rst(rst),
        .bin(value),
        .bcd(digits),
        .tooBig(tooBig)
    );

    // ~1.3 ms per digit at 100 MHz
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            refresh <= 20'd0;
        end else begin
            refresh <= refresh + 1'b1;
        end
    end

    assign sel = refresh[19:17];

    always @* begin
        Anode      = 8'b1111_1111;
        Anode[sel] = 1'b0;
        nib        = digits[sel*4 +: 4];
        if (tooBig) begin
            LED_out = 7'b1111110;                // "-"
        end else begin
            case (nib)
                4'd0:    LED_out = 7'b0000001;
                4'd1:    LED_out = 7'b1001111;
                4'd2:    LED_out = 7'b0010010;
                4'd3:    LED_out = 7'b0000110;
                4'd4:    LED_out = 7'b1001100;
                4'd5:    LED_out = 7'b0100100;
                4'd6:    LED_out = 7'b0100000;
                4'd7:    LED_out = 7'b0001111;
                4'd8:    LED_out = 7'b0000000;
                4'd9:    LED_out = 7'b0000100;
                default: LED_out = 7'b0000001;
            endcase
        end
    end

    assign dp = ~dpOn;

endmodule

`default_nettype wire
