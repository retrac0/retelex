// mf8_encoder -- differential Manchester, mf8-spec.md 9.2.
//
// A transition at every cell boundary, and one more at mid-cell for a 0.  In
// 74HC it is a JK wired J = K = EN, clocked by the half-bit clock HB, with
// EN = H OR NOT(bit) -- one gate and one flip-flop.
//
// The exchange unit's line is 1024 kbps / 2.048 MBaud (mf8-unit.md 4.2).  A
// line bit is four ticks of 4.096 MHz.  Tick 0 of each nibble is the boundary
// (H was 1, EN is 1 whatever the bit); tick 2 is mid-cell (H is 0, EN is NOT
// the bit).  The unit owns that crystal; this model shares the exchange's
// 4.096 MHz, which is the same divide (Q1).
`timescale 1ns/1ps

module mf8_encoder (
    input            clk,
    input            rst_n,
    input      [2:0] tick,
    input            bit_in,      // the frame bit for this line cell
    output reg       line
);
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                               line <= 1'b0;
        else if (tick[1:0] == 2'd0)               line <= ~line;   // boundary: always
        else if (tick[1:0] == 2'd2 && !bit_in)    line <= ~line;   // mid-cell: a 0
endmodule
